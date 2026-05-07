//
//  CodexPaths.swift
//  ClaudeIsland
//
//  Paths for Codex CLI state.
//

import Foundation

enum CodexPaths {
    nonisolated static var codexDir: URL {
        let fm = FileManager.default
        if let envDir = Foundation.ProcessInfo.processInfo.environment["CODEX_HOME"], !envDir.isEmpty {
            let expanded = (envDir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    nonisolated static var sessionsDir: URL {
        codexDir.appendingPathComponent("sessions")
    }

    nonisolated static var hooksDir: URL {
        codexDir.appendingPathComponent("hooks")
    }

    nonisolated static var hooksFile: URL {
        codexDir.appendingPathComponent("hooks.json")
    }

    nonisolated static var configFile: URL {
        codexDir.appendingPathComponent("config.toml")
    }

    nonisolated static var sessionIndexFile: URL {
        codexDir.appendingPathComponent("session_index.jsonl")
    }

    /// Shell-safe absolute path for hook commands in hooks.json.
    nonisolated static var hookScriptShellPath: String {
        shellQuote(hooksDir.appendingPathComponent("codex-island-state.py").path)
    }

    nonisolated private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
