//
//  QuotaStore.swift
//  ClaudeIsland
//
//  Main-actor bridge between SwiftUI and the background quota providers.
//

import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var snapshot: QuotaSnapshot = .empty
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private init() {}

    func start() {
        refresh()
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                self?.refresh()
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        refreshTask?.cancel()
        isRefreshing = true

        refreshTask = Task { [weak self] in
            async let claudeResult = ClaudeQuotaProvider.fetch()
            async let codexResult = CodexQuotaProvider.fetch()

            let providers: [QuotaProvider: QuotaProviderSnapshot] = [
                .claude: await claudeResult,
                .codex: await codexResult,
            ]

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.snapshot = QuotaSnapshot(
                    providers: providers,
                    isRefreshing: false,
                    lastUpdatedAt: Date()
                )
                self?.isRefreshing = false
            }
        }
    }
}
