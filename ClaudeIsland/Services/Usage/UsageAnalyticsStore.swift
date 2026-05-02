//
//  UsageAnalyticsStore.swift
//  ClaudeIsland
//
//  Main-actor bridge between SwiftUI and the background usage analytics engine.
//

import Combine
import Foundation

@MainActor
final class UsageAnalyticsStore: ObservableObject {
    static let shared = UsageAnalyticsStore()

    @Published private(set) var snapshot: UsageAnalyticsSnapshot = .empty
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var lastRange: UsageAnalyticsRange = .twelveWeeks

    private init() {}

    func start(range: UsageAnalyticsRange = .twelveWeeks) {
        lastRange = range
        refresh(range: range)
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                self?.refresh(range: self?.lastRange ?? .twelveWeeks)
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(range: UsageAnalyticsRange? = nil) {
        let range = range ?? lastRange
        lastRange = range
        refreshTask?.cancel()
        isRefreshing = true
        let claudeProjectsDir = ClaudePaths.projectsDir
        let codexSessionsDir = CodexPaths.sessionsDir

        refreshTask = Task { [weak self] in
            let snapshot = await UsageAnalyticsEngine.shared.refresh(
                range: range,
                claudeProjectsDir: claudeProjectsDir,
                codexSessionsDir: codexSessionsDir
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.snapshot = snapshot
                self?.isRefreshing = false
            }
        }
    }
}
