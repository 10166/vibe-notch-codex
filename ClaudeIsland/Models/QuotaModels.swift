//
//  QuotaModels.swift
//  ClaudeIsland
//
//  API usage quota data models for Claude Code and Codex CLI.
//

import Foundation
import SwiftUI

// MARK: - Provider

nonisolated enum QuotaProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }
}

// MARK: - Rate Window

nonisolated struct QuotaRateWindow: Equatable, Sendable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Date?
    var resetDescription: String?

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

// MARK: - Provider Identity

nonisolated struct QuotaProviderIdentity: Equatable, Sendable {
    var email: String?
    var plan: String?
}

// MARK: - Credits Snapshot

nonisolated struct QuotaCreditsSnapshot: Equatable, Sendable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: Double?
}

// MARK: - Errors

nonisolated enum QuotaError: Equatable, Sendable {
    case noCredentials
    case networkError(String)
    case unauthorized
    case invalidResponse
    case notAvailable
}

// MARK: - Per-Provider Snapshot

nonisolated struct QuotaProviderSnapshot: Equatable, Sendable {
    var provider: QuotaProvider
    var primary: QuotaRateWindow?
    var secondary: QuotaRateWindow?
    var credits: QuotaCreditsSnapshot?
    var identity: QuotaProviderIdentity?
    var error: QuotaError?
    var updatedAt: Date
}

// MARK: - Aggregate Snapshot

nonisolated struct QuotaSnapshot: Equatable, Sendable {
    var providers: [QuotaProvider: QuotaProviderSnapshot]
    var isRefreshing: Bool
    var lastUpdatedAt: Date?

    static let empty = QuotaSnapshot(
        providers: [:],
        isRefreshing: false,
        lastUpdatedAt: nil
    )
}

// MARK: - Formatters

nonisolated enum QuotaFormatters {
    static func usagePercent(_ window: QuotaRateWindow) -> String {
        String(format: "%.0f%%", window.remainingPercent)
    }

    static func resetCountdown(from date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    static func colorForUsage(_ percent: Double) -> Color {
        if percent < 50 {
            return TerminalColors.green
        } else if percent <= 80 {
            return TerminalColors.amber
        } else {
            return TerminalColors.red
        }
    }

    static func windowLabel(_ window: QuotaRateWindow) -> String {
        guard let minutes = window.windowMinutes else {
            return "Usage"
        }
        switch minutes {
        case 300:
            return "Session (5h)"
        case 10080:
            return "Weekly (7d)"
        default:
            let hours = minutes / 60
            if hours >= 24 {
                let days = hours / 24
                return "Usage (\(days)d)"
            }
            return "Usage (\(hours)h)"
        }
    }
}
