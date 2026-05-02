//
//  CodexHookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Codex CLI hooks on app launch.
//

import Foundation

struct CodexHookInstaller {
    nonisolated private static let scriptName = "codex-island-state.py"

    static func installIfNeeded() {
        let hooksDir = CodexPaths.hooksDir
        let pythonScript = hooksDir.appendingPathComponent(scriptName)

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "codex-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        enableHookFeature()
        updateHooksFile()
    }

    static func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: CodexPaths.hooksFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.contains { _, value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains(where: isCodexIslandHook)
            }
        }
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: CodexPaths.hooksDir.appendingPathComponent(scriptName))

        guard let data = try? Data(contentsOf: CodexPaths.hooksFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { removingCodexIslandHooks(from: $0) }
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        writeJSON(json, to: CodexPaths.hooksFile)
    }

    private static func updateHooksFile() {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: CodexPaths.hooksFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            if let entries = value as? [[String: Any]] {
                let cleaned = entries.compactMap { removingCodexIslandHooks(from: $0) }
                if cleaned.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = cleaned
                }
            }
        }

        let python = detectPython()
        let command = "\(python) \(CodexPaths.hookScriptShellPath)"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command, "timeout": 300]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]

        for (event, config) in [
            ("SessionStart", withoutMatcher),
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PermissionRequest", withMatcher),
            ("PostToolUse", withMatcher),
            ("Stop", withoutMatcher)
        ] {
            let existing = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = existing + config
        }

        json["hooks"] = hooks
        writeJSON(json, to: CodexPaths.hooksFile)
    }

    private static func enableHookFeature() {
        let configURL = CodexPaths.configFile
        try? FileManager.default.createDirectory(
            at: CodexPaths.codexDir,
            withIntermediateDirectories: true
        )

        let original = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = tomlByEnablingCodexHooks(original)
        guard updated != original else { return }
        try? updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func tomlByEnablingCodexHooks(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var featureStart: Int?
        var featureEnd = lines.count

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                featureStart = index
                featureEnd = lines.count
                continue
            }
            if featureStart != nil, index > featureStart!, trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                featureEnd = index
                break
            }
        }

        if let featureStart {
            for index in (featureStart + 1)..<featureEnd {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("codex_hooks") {
                    lines[index] = "codex_hooks = true"
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert("codex_hooks = true", at: featureStart + 1)
            return lines.joined(separator: "\n")
        }

        let suffix = text.hasSuffix("\n") || text.isEmpty ? "" : "\n"
        return text + suffix + "[features]\ncodex_hooks = true\n"
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) {
        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: url)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    nonisolated private static func removingCodexIslandHooks(from entry: [String: Any]) -> [String: Any]? {
        guard var entryHooks = entry["hooks"] as? [[String: Any]] else {
            return entry
        }

        entryHooks.removeAll(where: isCodexIslandHook)
        guard !entryHooks.isEmpty else { return nil }

        var updatedEntry = entry
        updatedEntry["hooks"] = entryHooks
        return updatedEntry
    }

    nonisolated private static func isCodexIslandHook(_ hook: [String: Any]) -> Bool {
        let cmd = hook["command"] as? String ?? ""
        return cmd.contains(scriptName)
    }
}
