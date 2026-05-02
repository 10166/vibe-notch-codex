//
//  CodexSessionWatcher.swift
//  ClaudeIsland
//
//  Discovers recent Codex CLI sessions by scanning ~/.codex/sessions.
//

import Foundation
import os.log

struct CodexSessionSnapshot: Sendable {
    let sessionId: String
    let cwd: String
    let sessionFile: String
    let cliVersion: String?
    let updatedAt: Date
    let isProcessing: Bool
}

private let codexWatcherLogger = Logger(subsystem: "com.claudeisland", category: "CodexWatcher")

actor CodexSessionScanner {
    private let activeWindowSeconds: TimeInterval = 30 * 60
    private let processingWindowSeconds: TimeInterval = 12

    func scanRecentSessions() -> [CodexSessionSnapshot] {
        let fm = FileManager.default
        let sessionsDir = CodexPaths.sessionsDir
        guard fm.fileExists(atPath: sessionsDir.path),
              let enumerator = fm.enumerator(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let now = Date()
        var snapshots: [CodexSessionSnapshot] = []

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  now.timeIntervalSince(modDate) <= activeWindowSeconds,
                  let meta = parseSessionMeta(from: url) else {
                continue
            }

            snapshots.append(CodexSessionSnapshot(
                sessionId: meta.id,
                cwd: meta.cwd,
                sessionFile: url.path,
                cliVersion: meta.cliVersion,
                updatedAt: modDate,
                isProcessing: now.timeIntervalSince(modDate) <= processingWindowSeconds
            ))
        }

        return snapshots.sorted { $0.updatedAt > $1.updatedAt }
    }

    private struct SessionMeta {
        let id: String
        let cwd: String
        let cliVersion: String?
    }

    private func parseSessionMeta(from url: URL) -> SessionMeta? {
        guard let line = Self.readFirstLine(from: url),
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "session_meta",
              let payload = json["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String else {
            return nil
        }

        return SessionMeta(
            id: id,
            cwd: cwd,
            cliVersion: payload["cli_version"] as? String
        )
    }

    private static func readFirstLine(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var buffer = Data()
        let maxBytes = 2_000_000

        while buffer.count < maxBytes {
            guard let data = try? handle.read(upToCount: 8192),
                  !data.isEmpty else {
                break
            }

            if let newline = data.firstIndex(of: 0x0A) {
                buffer.append(data[..<newline])
                break
            }
            buffer.append(data)
        }

        return String(data: buffer, encoding: .utf8)
    }
}

final class CodexSessionWatcher {
    static let shared = CodexSessionWatcher()

    private let scanner = CodexSessionScanner()
    private var task: Task<Void, Never>?
    private let pollIntervalNs: UInt64 = 3_000_000_000

    private init() {}

    func start(onSnapshot: @escaping @Sendable (CodexSessionSnapshot) -> Void) {
        guard task == nil else { return }

        task = Task.detached(priority: .utility) { [scanner, pollIntervalNs] in
            while !Task.isCancelled {
                let snapshots = await scanner.scanRecentSessions()
                for snapshot in snapshots {
                    onSnapshot(snapshot)
                }
                try? await Task.sleep(nanoseconds: pollIntervalNs)
            }
        }

        codexWatcherLogger.info("Started Codex session watcher")
    }

    func stop() {
        task?.cancel()
        task = nil
        codexWatcherLogger.info("Stopped Codex session watcher")
    }
}
