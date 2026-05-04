//
//  QuotaModelsTests.swift
//  ClaudeIslandTests
//
//  Tests for QuotaModels data types and formatters.
//

import SwiftUI
import XCTest

final class QuotaModelsTests: XCTestCase {

    // MARK: - QuotaRateWindow

    func testRateWindowRemainingPercent() {
        let window = QuotaRateWindow(usedPercent: 72.5, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(window.remainingPercent, 27.5)
    }

    func testRateWindowRemainingPercentClampsToZero() {
        let window = QuotaRateWindow(usedPercent: 105.0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(window.remainingPercent, 0)
    }

    func testRateWindowRemainingPercentAtExactly100() {
        let window = QuotaRateWindow(usedPercent: 100.0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(window.remainingPercent, 0)
    }

    func testRateWindowRemainingPercentAtZero() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(window.remainingPercent, 100)
    }

    func testRateWindowWithLocalUsage() {
        let summary = QuotaLocalUsageSummary(
            totalTokens: 12_345,
            estimatedCostMicros: 678,
            sessionCount: 2
        )
        let window = QuotaRateWindow(usedPercent: 30).withLocalUsage(summary)

        XCTAssertEqual(window.localUsage?.totalTokens, 12_345)
        XCTAssertEqual(window.localUsage?.estimatedCostMicros, 678)
        XCTAssertEqual(window.localUsage?.sessionCount, 2)
    }

    func testLocalUsageSummaryEmpty() {
        XCTAssertEqual(QuotaLocalUsageSummary.empty.totalTokens, 0)
        XCTAssertNil(QuotaLocalUsageSummary.empty.estimatedCostMicros)
        XCTAssertEqual(QuotaLocalUsageSummary.empty.sessionCount, 0)
    }

    // MARK: - QuotaSnapshot

    func testEmptySnapshot() {
        let snapshot = QuotaSnapshot.empty
        XCTAssertTrue(snapshot.providers.isEmpty)
        XCTAssertNil(snapshot.lastUpdatedAt)
    }

    // MARK: - QuotaFormatters.usagePercent

    func testUsagePercentWhole() {
        let window = QuotaRateWindow(usedPercent: 28, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.usagePercent(window), "72%")
    }

    func testUsagePercentDecimal() {
        let window = QuotaRateWindow(usedPercent: 27.5, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.usagePercent(window), "72%")
    }

    func testUsagePercentZero() {
        let window = QuotaRateWindow(usedPercent: 100, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.usagePercent(window), "0%")
    }

    func testUsagePercentFull() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.usagePercent(window), "100%")
    }

    // MARK: - QuotaFormatters.resetCountdown

    func testResetCountdownMinutes() {
        let now = Date()
        let resetDate = now.addingTimeInterval(45 * 60) // 45 minutes
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: resetDate, now: now), "45m")
    }

    func testResetCountdownHoursAndMinutes() {
        let now = Date()
        let resetDate = now.addingTimeInterval(2 * 3600 + 30 * 60) // 2h 30m
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: resetDate, now: now), "2h 30m")
    }

    func testResetCountdownDaysAndHours() {
        let now = Date()
        let resetDate = now.addingTimeInterval(3 * 86400 + 12 * 3600) // 3d 12h
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: resetDate, now: now), "3d 12h")
    }

    func testResetCountdownPastDate() {
        let now = Date()
        let resetDate = now.addingTimeInterval(-60) // 1 minute ago
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: resetDate, now: now), "now")
    }

    func testResetCountdownExactlyZero() {
        let now = Date()
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: now, now: now), "now")
    }

    func testResetCountdownSingleMinute() {
        let now = Date()
        let resetDate = now.addingTimeInterval(90) // 1.5 minutes rounds down to 1m
        XCTAssertEqual(QuotaFormatters.resetCountdown(from: resetDate, now: now), "1m")
    }

    // MARK: - QuotaFormatters.colorForUsage

    func testColorForUsageGreen() {
        let color = QuotaFormatters.colorForUsage(30)
        // Verify it returns TerminalColors.green (compare components)
        XCTAssertEqual(color, TerminalColors.green)
    }

    func testColorForUsageAmber() {
        let color = QuotaFormatters.colorForUsage(65)
        XCTAssertEqual(color, TerminalColors.amber)
    }

    func testColorForUsageRed() {
        let color = QuotaFormatters.colorForUsage(90)
        XCTAssertEqual(color, TerminalColors.red)
    }

    func testColorForUsageBoundaryAt50() {
        // 50% is amber (50-80% range)
        let color = QuotaFormatters.colorForUsage(50)
        XCTAssertEqual(color, TerminalColors.amber)
    }

    func testColorForUsageBoundaryAt80() {
        // 80% is still amber (<=80 in the 50-80 range)
        let color = QuotaFormatters.colorForUsage(80)
        XCTAssertEqual(color, TerminalColors.amber)
    }

    func testColorForUsageBoundaryAt81() {
        // 81% is red (>80)
        let color = QuotaFormatters.colorForUsage(81)
        XCTAssertEqual(color, TerminalColors.red)
    }

    func testColorForUsageBoundaryAt49() {
        // 49% is green (<50)
        let color = QuotaFormatters.colorForUsage(49)
        XCTAssertEqual(color, TerminalColors.green)
    }

    // MARK: - QuotaFormatters.windowLabel

    func testWindowLabelSession() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.windowLabel(window), "Session (5h)")
    }

    func testWindowLabelWeekly() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.windowLabel(window), "Weekly (7d)")
    }

    func testWindowLabelNilMinutes() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.windowLabel(window), "Usage")
    }

    func testWindowLabelOtherHours() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 120, resetsAt: nil, resetDescription: nil)
        XCTAssertEqual(QuotaFormatters.windowLabel(window), "Usage (2h)")
    }

    func testWindowLabelOtherDays() {
        let window = QuotaRateWindow(usedPercent: 0, windowMinutes: 4320, resetsAt: nil, resetDescription: nil) // 72 hours = 3 days
        XCTAssertEqual(QuotaFormatters.windowLabel(window), "Usage (3d)")
    }

    // MARK: - QuotaProvider

    func testQuotaProviderDisplayNames() {
        XCTAssertEqual(QuotaProvider.claude.displayName, "Claude Code")
        XCTAssertEqual(QuotaProvider.codex.displayName, "Codex CLI")
    }

    func testQuotaProviderRawValues() {
        XCTAssertEqual(QuotaProvider.claude.rawValue, "claude")
        XCTAssertEqual(QuotaProvider.codex.rawValue, "codex")
    }

    func testQuotaProviderAllCases() {
        XCTAssertEqual(QuotaProvider.allCases.count, 2)
    }

    // MARK: - QuotaProviderSnapshot

    func testProviderSnapshotWithPrimaryOnly() {
        let window = QuotaRateWindow(usedPercent: 50, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: window,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: nil,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.primary?.usedPercent, 50)
        XCTAssertNil(snapshot.secondary)
        XCTAssertNil(snapshot.error)
    }

    func testProviderSnapshotWithError() {
        let snapshot = QuotaProviderSnapshot(
            provider: .codex,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .noCredentials,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .noCredentials)
        XCTAssertNil(snapshot.primary)
    }

    // MARK: - QuotaCreditsSnapshot

    func testCreditsSnapshotWithBalance() {
        let credits = QuotaCreditsSnapshot(hasCredits: true, unlimited: false, balance: 50.0)
        XCTAssertTrue(credits.hasCredits)
        XCTAssertFalse(credits.unlimited)
        XCTAssertEqual(credits.balance, 50.0)
    }

    func testCreditsSnapshotUnlimited() {
        let credits = QuotaCreditsSnapshot(hasCredits: true, unlimited: true, balance: nil)
        XCTAssertTrue(credits.hasCredits)
        XCTAssertTrue(credits.unlimited)
        XCTAssertNil(credits.balance)
    }

    // MARK: - QuotaError

    func testQuotaErrorEquality() {
        XCTAssertEqual(QuotaError.networkError("timeout"), QuotaError.networkError("timeout"))
        XCTAssertNotEqual(QuotaError.networkError("timeout"), QuotaError.networkError("refused"))
        XCTAssertEqual(QuotaError.noCredentials, QuotaError.noCredentials)
        XCTAssertNotEqual(QuotaError.noCredentials, QuotaError.unauthorized)
    }
}
