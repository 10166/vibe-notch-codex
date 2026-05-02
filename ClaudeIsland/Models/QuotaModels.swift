//
//  QuotaModels.swift
//  ClaudeIsland
//
//  API usage quota data models for Claude Code and Codex CLI.
//

import Foundation
import SwiftUI

// MARK: - Provider

public nonisolated enum QuotaProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }
}

// MARK: - Rate Window

public nonisolated struct QuotaRateWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?
    public var resetDescription: String?

    public init(usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil, resetDescription: String? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

// MARK: - Provider Identity

public nonisolated struct QuotaProviderIdentity: Equatable, Sendable {
    public var email: String?
    public var plan: String?

    public init(email: String? = nil, plan: String? = nil) {
        self.email = email
        self.plan = plan
    }
}

// MARK: - Credits Snapshot

public nonisolated struct QuotaCreditsSnapshot: Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: Double?

    public init(hasCredits: Bool, unlimited: Bool, balance: Double? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

// MARK: - Errors

public nonisolated enum QuotaError: Equatable, Sendable {
    case noCredentials
    case networkError(String)
    case unauthorized
    case invalidResponse
    case notAvailable
}

// MARK: - Per-Provider Snapshot

public nonisolated struct QuotaProviderSnapshot: Equatable, Sendable {
    public var provider: QuotaProvider
    public var primary: QuotaRateWindow?
    public var secondary: QuotaRateWindow?
    public var credits: QuotaCreditsSnapshot?
    public var identity: QuotaProviderIdentity?
    public var error: QuotaError?
    public var updatedAt: Date

    public init(provider: QuotaProvider, primary: QuotaRateWindow? = nil, secondary: QuotaRateWindow? = nil, credits: QuotaCreditsSnapshot? = nil, identity: QuotaProviderIdentity? = nil, error: QuotaError? = nil, updatedAt: Date) {
        self.provider = provider
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.identity = identity
        self.error = error
        self.updatedAt = updatedAt
    }
}

// MARK: - Aggregate Snapshot

public nonisolated struct QuotaSnapshot: Equatable, Sendable {
    public var providers: [QuotaProvider: QuotaProviderSnapshot]
    public var lastUpdatedAt: Date?

    public static let empty = QuotaSnapshot(
        providers: [:],
        lastUpdatedAt: nil
    )
}

// MARK: - Formatters

public nonisolated enum QuotaFormatters {
    public static func usagePercent(_ window: QuotaRateWindow) -> String {
        String(format: "%.0f%%", window.remainingPercent)
    }

    public static func resetCountdown(from date: Date, now: Date) -> String {
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

    public static func colorForUsage(_ percent: Double) -> Color {
        if percent < 50 {
            return TerminalColors.green
        } else if percent <= 80 {
            return TerminalColors.amber
        } else {
            return TerminalColors.red
        }
    }

    public static func windowLabel(_ window: QuotaRateWindow) -> String {
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
