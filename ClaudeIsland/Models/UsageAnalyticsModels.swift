//
//  UsageAnalyticsModels.swift
//  ClaudeIsland
//
//  Local-only usage analytics models for Claude Code and Codex CLI logs.
//

import Foundation

nonisolated enum UsageAnalyticsAgent: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

nonisolated enum UsageAnalyticsAgentFilter: String, CaseIterable, Identifiable {
    case all
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    func includes(_ agent: UsageAnalyticsAgent) -> Bool {
        switch self {
        case .all: return true
        case .claude: return agent == .claude
        case .codex: return agent == .codex
        }
    }
}

nonisolated enum UsageAnalyticsMetric: String, CaseIterable, Identifiable {
    case tokens
    case cost
    case sessions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tokens: return "Tokens"
        case .cost: return "Cost"
        case .sessions: return "Sessions"
        }
    }
}

nonisolated enum UsageAnalyticsRange: String, CaseIterable, Identifiable {
    case twelveWeeks
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twelveWeeks: return "12w"
        case .sixMonths: return "6m"
        case .oneYear: return "1y"
        }
    }

    var dayCount: Int {
        switch self {
        case .twelveWeeks: return 12 * 7
        case .sixMonths: return 26 * 7
        case .oneYear: return 52 * 7
        }
    }
}

nonisolated struct UsageTokenBreakdown: Equatable, Sendable {
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

nonisolated struct UsageSessionRecord: Identifiable, Equatable, Sendable {
    let id: String
    let sessionId: String
    let agent: UsageAnalyticsAgent
    let projectName: String
    let cwdHash: String
    let startedAt: Date
    let endedAt: Date
    let localDate: String
    let model: String?
    let tokens: UsageTokenBreakdown
    let estimatedCostMicros: Int64?
    let isSidechain: Bool

    var totalTokens: Int64 { tokens.totalTokens }
}

nonisolated struct UsageDayBucket: Identifiable, Equatable, Sendable {
    let localDate: String
    let date: Date
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheReadTokens: Int64
    var cacheCreationTokens: Int64
    var estimatedCostMicros: Int64?
    var sessionCount: Int

    var id: String { localDate }

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    func value(for metric: UsageAnalyticsMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(totalTokens)
        case .cost:
            return Double(estimatedCostMicros ?? 0)
        case .sessions:
            return Double(sessionCount)
        }
    }
}

nonisolated struct UsageAnalyticsSnapshot: Equatable, Sendable {
    var generatedAt: Date
    var days: [UsageDayBucket]
    var sessions: [UsageSessionRecord]
    var scannedFileCount: Int

    static let empty = UsageAnalyticsSnapshot(
        generatedAt: Date(),
        days: [],
        sessions: [],
        scannedFileCount: 0
    )
}

nonisolated enum UsageFormatters {
    static func compactTokens(_ value: Int64) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func cost(_ micros: Int64?) -> String {
        guard let micros else { return "--" }
        let dollars = Double(micros) / 1_000_000
        if dollars >= 10 {
            return String(format: "$%.0f", dollars)
        } else if dollars >= 1 {
            return String(format: "$%.2f", dollars)
        }
        return String(format: "$%.3f", dollars)
    }

    static func metricValue(_ value: Double, metric: UsageAnalyticsMetric) -> String {
        switch metric {
        case .tokens:
            return compactTokens(Int64(value))
        case .cost:
            return cost(Int64(value))
        case .sessions:
            return "\(Int(value))"
        }
    }
}
