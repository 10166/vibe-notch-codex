//
//  CodexPaths.swift
//  ClaudeIsland
//
//  Paths for Codex CLI state.
//

import Foundation

enum CodexPaths {
    static var codexDir: URL {
        let fm = FileManager.default
        if let envDir = Foundation.ProcessInfo.processInfo.environment["CODEX_HOME"], !envDir.isEmpty {
            let expanded = (envDir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static var sessionsDir: URL {
        codexDir.appendingPathComponent("sessions")
    }

    static var hooksDir: URL {
        codexDir.appendingPathComponent("hooks")
    }

    static var hooksFile: URL {
        codexDir.appendingPathComponent("hooks.json")
    }

    static var configFile: URL {
        codexDir.appendingPathComponent("config.toml")
    }

    static var sessionIndexFile: URL {
        codexDir.appendingPathComponent("session_index.jsonl")
    }

    /// Shell-safe absolute path for hook commands in hooks.json.
    static var hookScriptShellPath: String {
        shellQuote(hooksDir.appendingPathComponent("codex-island-state.py").path)
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
