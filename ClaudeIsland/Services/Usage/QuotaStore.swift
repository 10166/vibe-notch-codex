//
//  QuotaStore.swift
//  ClaudeIsland
//
//  Main-actor bridge between SwiftUI and the background quota providers.
//

import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var snapshot: QuotaSnapshot = .empty
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private static let refreshInterval: UInt64 = 10 * 60 * 1_000_000_000

    private init() {}

    func start() {
        guard periodicTask == nil else { return }
        refresh()
        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshInterval)
                refresh()
            }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        isRefreshing = true

        refreshTask = Task {
            async let claudeResult = ClaudeQuotaProvider.fetch()
            async let codexResult = CodexQuotaProvider.fetch()

            let providers: [QuotaProvider: QuotaProviderSnapshot] = [
                .claude: await claudeResult,
                .codex: await codexResult,
            ]

            guard !Task.isCancelled else { return }

            if providers != snapshot.providers {
                snapshot = QuotaSnapshot(
                    providers: providers,
                    lastUpdatedAt: Date()
                )
            }
            isRefreshing = false
        }
    }
}
