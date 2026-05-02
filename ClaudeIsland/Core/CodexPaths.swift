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

    static var sessionIndexFile: URL {
        codexDir.appendingPathComponent("session_index.jsonl")
    }
}
