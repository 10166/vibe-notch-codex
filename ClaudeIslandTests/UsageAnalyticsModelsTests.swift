//
//  UsageAnalyticsModelsTests.swift
//  ClaudeIslandTests
//
//  Tests for local usage analytics attribution and aggregation helpers.
//

import Foundation
import XCTest

final class UsageAnalyticsModelsTests: XCTestCase {
    func testClaudeSidechainWorktreeCwdResolvesToParentProject() {
        let cwd = "/Users/weijie.lai/Projects/workspace/vibe-notch-codex/.claude/worktrees/agent-a71a5ef7a5a5bf70f"
        let resolved = UsageProjectAttribution.resolvedClaudeCwd(cwd: cwd, isSidechain: true, parentCwd: nil)

        XCTAssertEqual(resolved, "/Users/weijie.lai/Projects/workspace/vibe-notch-codex")
        XCTAssertEqual(UsageProjectAttribution.projectName(from: resolved, fallback: "agent-a71a5ef7a5a5bf70f"), "vibe-notch-codex")
    }

    func testClaudeSidechainMissingCwdFallsBackToParentSessionCwd() {
        let resolved = UsageProjectAttribution.resolvedClaudeCwd(
            cwd: nil,
            isSidechain: true,
            parentCwd: "/Users/weijie.lai/Projects/workspace/vibe-notch-codex"
        )

        XCTAssertEqual(resolved, "/Users/weijie.lai/Projects/workspace/vibe-notch-codex")
        XCTAssertEqual(UsageProjectAttribution.projectName(from: resolved, fallback: "agent-a034e1cc421d8c06"), "vibe-notch-codex")
    }

    func testNormalClaudeAndCodexCwdProjectNamesAreUnchanged() {
        XCTAssertEqual(
            UsageProjectAttribution.projectName(from: "/Users/weijie.lai/Projects/workspace/vibe-notch-codex", fallback: "fallback"),
            "vibe-notch-codex"
        )
        XCTAssertEqual(
            UsageProjectAttribution.projectName(from: "/Users/weijie.lai/.codex/sessions/2026/05/03", fallback: "05"),
            "03"
        )
    }

    func testProjectSummariesAggregateTokensCostAndSessions() {
        let sessions = [
            makeSession(
                id: "one",
                projectName: "vibe-notch-codex",
                tokens: UsageTokenBreakdown(inputTokens: 100, outputTokens: 50, cacheReadTokens: 25, cacheCreationTokens: 0),
                estimatedCostMicros: 120,
                isSidechain: false
            ),
            makeSession(
                id: "two",
                projectName: "vibe-notch-codex",
                tokens: UsageTokenBreakdown(inputTokens: 40, outputTokens: 10, cacheReadTokens: 0, cacheCreationTokens: 0),
                estimatedCostMicros: 80,
                isSidechain: true
            ),
            makeSession(
                id: "three",
                projectName: "other",
                tokens: UsageTokenBreakdown(inputTokens: 60, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0),
                estimatedCostMicros: nil,
                isSidechain: false
            )
        ]

        let summaries = UsageAnalyticsAggregation.projectSummaries(from: sessions)

        XCTAssertEqual(summaries.first?.name, "vibe-notch-codex")
        XCTAssertEqual(summaries.first?.totalTokens, 225)
        XCTAssertEqual(summaries.first?.estimatedCostMicros, 200)
        XCTAssertEqual(summaries.first?.sessionCount, 2)
        XCTAssertEqual(summaries.last?.name, "other")
        XCTAssertNil(summaries.last?.estimatedCostMicros)
    }

    private func makeSession(
        id: String,
        projectName: String,
        tokens: UsageTokenBreakdown,
        estimatedCostMicros: Int64?,
        isSidechain: Bool
    ) -> UsageSessionRecord {
        UsageSessionRecord(
            id: id,
            sessionId: id,
            agent: .claude,
            projectName: projectName,
            cwdHash: id,
            startedAt: Date(timeIntervalSince1970: 1_714_000_000),
            endedAt: Date(timeIntervalSince1970: 1_714_000_100),
            localDate: "2026-05-03",
            model: "glm-5.1",
            tokens: tokens,
            estimatedCostMicros: estimatedCostMicros,
            isSidechain: isSidechain
        )
    }
}
