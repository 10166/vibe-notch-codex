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
            let byokConfig = BYOKDetector.detect()
            async let claudeResult = Self.fetchClaudeQuota(byokConfig: byokConfig)
            async let codexResult = CodexQuotaProvider.fetch()
            async let analyticsRefresh = UsageAnalyticsEngine.shared.refresh(
                range: .twelveWeeks,
                claudeProjectsDir: ClaudePaths.projectsDir,
                codexSessionsDir: CodexPaths.sessionsDir
            )

            let rawClaudeResult = await claudeResult
            let rawCodexResult = await codexResult
            _ = await analyticsRefresh

            async let claudeWithUsage = Self.attachLocalUsage(to: rawClaudeResult, agent: .claude)
            async let codexWithUsage = Self.attachLocalUsage(to: rawCodexResult, agent: .codex)
            let providers: [QuotaProvider: QuotaProviderSnapshot] = [
                .claude: await claudeWithUsage,
                .codex: await codexWithUsage,
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

    private static func fetchClaudeQuota(byokConfig: BYOKConfiguration?) async -> QuotaProviderSnapshot {
        if let byokConfig {
            return await fetchBYOKQuota(config: byokConfig)
        }
        return await ClaudeQuotaProvider.fetch()
    }

    private static func fetchBYOKQuota(config: BYOKConfiguration) async -> QuotaProviderSnapshot {
        switch config.provider {
        case .zhiPu:
            return await ZhiPuQuotaProvider.fetch(apiKey: config.apiKey)
        case .deepSeek:
            return await DeepSeekQuotaProvider.fetch(apiKey: config.apiKey)
        case .openRouter:
            return await OpenRouterQuotaProvider.fetch(apiKey: config.apiKey)
        case .anthropicAPI, .unknown:
            return QuotaProviderSnapshot(
                provider: .claude,
                identity: QuotaProviderIdentity(email: nil, plan: "BYOK: \(config.provider.displayName)"),
                error: .notAvailable,
                updatedAt: Date()
            )
        }
    }

    private static func attachLocalUsage(to snapshot: QuotaProviderSnapshot, agent: UsageAnalyticsAgent) async -> QuotaProviderSnapshot {
        var copy = snapshot
        copy.primary = await windowWithLocalUsage(snapshot.primary, agent: agent)
        copy.secondary = await windowWithLocalUsage(snapshot.secondary, agent: agent)
        return copy
    }

    private static func windowWithLocalUsage(_ window: QuotaRateWindow?, agent: UsageAnalyticsAgent) async -> QuotaRateWindow? {
        guard let window, let interval = localWindowInterval(for: window) else {
            return window
        }
        let summary = await UsageAnalyticsEngine.shared.localUsage(
            agent: agent,
            from: interval.start,
            to: interval.end
        )
        return window.withLocalUsage(summary)
    }

    private static func localWindowInterval(for window: QuotaRateWindow) -> (start: Date, end: Date)? {
        guard let minutes = window.windowMinutes, minutes > 0 else {
            return nil
        }
        let now = Date()
        let reset = window.resetsAt ?? now
        let start = reset.addingTimeInterval(TimeInterval(-minutes * 60))
        let end = min(now, reset)
        guard start < end else { return nil }
        return (start, end)
    }
}
