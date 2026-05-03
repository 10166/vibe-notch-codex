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

nonisolated enum UsageAnalyticsAgentFilter: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum UsageAnalyticsMetric: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum UsageAnalyticsRange: String, CaseIterable, Identifiable, Sendable {
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

nonisolated protocol UsageMetricAccessible: Sendable {
    var totalTokens: Int64 { get }
    var estimatedCostMicros: Int64? { get }
    var sessionCount: Int { get }
}

extension UsageMetricAccessible {
    func value(for metric: UsageAnalyticsMetric) -> Double {
        switch metric {
        case .tokens:   return Double(totalTokens)
        case .cost:     return Double(estimatedCostMicros ?? 0)
        case .sessions: return Double(sessionCount)
        }
    }
}

nonisolated struct UsageDayBucket: Identifiable, Equatable, Sendable, UsageMetricAccessible {
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
}

nonisolated struct UsageProjectUsageSummary: Identifiable, Equatable, Sendable, UsageMetricAccessible {
    let name: String
    var totalTokens: Int64
    var estimatedCostMicros: Int64?
    var sessionCount: Int

    var id: String { name }
}

nonisolated struct UsageRangeSummary: Equatable, Sendable, UsageMetricAccessible {
    var totalTokens: Int64
    var estimatedCostMicros: Int64?
    var sessionCount: Int

    static let empty = UsageRangeSummary(
        totalTokens: 0,
        estimatedCostMicros: nil,
        sessionCount: 0
    )
}

nonisolated struct UsageDayGroupRecord: Identifiable, Equatable, Sendable, UsageMetricAccessible {
    let localDate: String
    let agent: UsageAnalyticsAgent
    let projectName: String
    let model: String?
    let tokens: UsageTokenBreakdown
    let estimatedCostMicros: Int64?
    let sessionCount: Int
    let isSidechain: Bool

    var id: String {
        "\(localDate)|\(agent.rawValue)|\(projectName)|\(model ?? "")|\(isSidechain)"
    }

    var totalTokens: Int64 { tokens.totalTokens }
}

nonisolated struct UsageAnalyticsSnapshot: Equatable, Sendable {
    var generatedAt: Date
    var days: [UsageDayBucket]
    var claudeDays: [UsageDayBucket]
    var codexDays: [UsageDayBucket]
    var allSummary: UsageRangeSummary
    var claudeSummary: UsageRangeSummary
    var codexSummary: UsageRangeSummary
    var dayGroups: [String: [UsageDayGroupRecord]]
    var sessions: [UsageSessionRecord]
    var scannedFileCount: Int

    static let empty = UsageAnalyticsSnapshot(
        generatedAt: Date(),
        days: [],
        claudeDays: [],
        codexDays: [],
        allSummary: .empty,
        claudeSummary: .empty,
        codexSummary: .empty,
        dayGroups: [:],
        sessions: [],
        scannedFileCount: 0
    )

    func days(for filter: UsageAnalyticsAgentFilter) -> [UsageDayBucket] {
        switch filter {
        case .all: return days
        case .claude: return claudeDays
        case .codex: return codexDays
        }
    }

    func summary(for filter: UsageAnalyticsAgentFilter) -> UsageRangeSummary {
        switch filter {
        case .all: return allSummary
        case .claude: return claudeSummary
        case .codex: return codexSummary
        }
    }

    func groups(on localDate: String, for filter: UsageAnalyticsAgentFilter) -> [UsageDayGroupRecord] {
        let groups = dayGroups[localDate] ?? []
        guard filter != .all else { return groups }
        return groups.filter { filter.includes($0.agent) }
    }
}

nonisolated enum UsageAnalyticsAggregation {
    static func projectSummaries(from sessions: [UsageSessionRecord]) -> [UsageProjectUsageSummary] {
        Dictionary(grouping: sessions, by: \.projectName)
            .map { projectName, projectSessions in
                UsageProjectUsageSummary(
                    name: projectName,
                    totalTokens: projectSessions.reduce(0) { $0 + $1.totalTokens },
                    estimatedCostMicros: sumCostMicros(projectSessions),
                    sessionCount: projectSessions.count
                )
            }
            .sorted {
                if $0.totalTokens == $1.totalTokens {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.totalTokens > $1.totalTokens
            }
    }

    static func sumCostMicros(_ sessions: [UsageSessionRecord]) -> Int64? {
        var total: Int64 = 0
        var found = false
        for session in sessions {
            if let cost = session.estimatedCostMicros {
                total += cost
                found = true
            }
        }
        return found ? total : nil
    }

    static func projectSummaries(from groups: [UsageDayGroupRecord]) -> [UsageProjectUsageSummary] {
        Dictionary(grouping: groups, by: \.projectName)
            .map { projectName, projectGroups in
                UsageProjectUsageSummary(
                    name: projectName,
                    totalTokens: projectGroups.reduce(0) { $0 + $1.totalTokens },
                    estimatedCostMicros: sumCostMicros(projectGroups),
                    sessionCount: projectGroups.reduce(0) { $0 + $1.sessionCount }
                )
            }
            .sorted {
                if $0.totalTokens == $1.totalTokens {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.totalTokens > $1.totalTokens
            }
    }

    static func sumCostMicros(_ groups: [UsageDayGroupRecord]) -> Int64? {
        var total: Int64 = 0
        var found = false
        for group in groups {
            if let cost = group.estimatedCostMicros {
                total += cost
                found = true
            }
        }
        return found ? total : nil
    }
}

nonisolated enum UsageProjectAttribution {
    static func projectName(from cwd: String?, fallback: String) -> String {
        guard let cwd = canonicalCwd(cwd), !cwd.isEmpty else { return fallback }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func resolvedClaudeCwd(cwd: String?, isSidechain: Bool, parentCwd: String?) -> String? {
        let canonical = canonicalCwd(cwd)
        guard isSidechain else { return canonical }
        return canonical ?? parentCwd
    }

    static func canonicalCwd(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let marker = "/.claude/worktrees/agent-"
        guard let markerRange = cwd.range(of: marker) else { return cwd }

        let projectPath = String(cwd[..<markerRange.lowerBound])
        return projectPath.isEmpty ? cwd : projectPath
    }
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
