//
//  ClaudeQuotaProviderTests.swift
//  ClaudeIslandTests
//
//  Tests for Claude OAuth API response parsing used by the quota feature.
//  Since ClaudeQuotaProvider does not exist yet, these tests validate the
//  JSON structures that the provider will consume, using local Codable
//  test helpers that mirror the expected API response shape.
//

import Foundation
import XCTest


// MARK: - Test-only Codable types matching the Claude OAuth API response

/// Mirrors the expected shape of the Claude OAuth `/api/usage` response.
private struct ClaudeUsageResponse: Codable, Equatable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Mirrors the expected shape of the Claude credentials.json file.
private struct ClaudeCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?
}

// MARK: - Tests

final class ClaudeQuotaProviderTests: XCTestCase {

    // MARK: - Usage Response Decoding

    func testDecodeUsageResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 72.5, "resets_at": "2026-05-03T10:00:00Z" },
          "seven_day": { "utilization": 58.2, "resets_at": "2026-05-07T00:00:00Z" }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        XCTAssertEqual(response.fiveHour?.utilization, 72.5)
        XCTAssertEqual(response.fiveHour?.resetsAt, "2026-05-03T10:00:00Z")
        XCTAssertEqual(response.sevenDay?.utilization, 58.2)
        XCTAssertEqual(response.sevenDay?.resetsAt, "2026-05-07T00:00:00Z")
    }

    func testDecodeUsageResponseWithExtraFields() throws {
        // Ensure extra fields are ignored gracefully
        let json = """
        {
          "five_hour": { "utilization": 30.0, "resets_at": "2026-05-03T10:00:00Z", "extra": true },
          "seven_day": { "utilization": 10.0, "resets_at": "2026-05-07T00:00:00Z" }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        XCTAssertEqual(response.fiveHour?.utilization, 30.0)
        XCTAssertEqual(response.sevenDay?.utilization, 10.0)
    }

    func testDecodeUsageResponseMissingWindows() throws {
        // Both windows absent should still decode successfully
        let json = """
        {
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        XCTAssertNil(response.fiveHour)
        XCTAssertNil(response.sevenDay)
    }

    func testDecodeUsageResponseOnlyFiveHour() throws {
        let json = """
        {
          "five_hour": { "utilization": 90.0, "resets_at": "2026-05-03T15:00:00Z" }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        XCTAssertEqual(response.fiveHour?.utilization, 90.0)
        XCTAssertNil(response.sevenDay)
    }

    // MARK: - Mapping to QuotaProviderSnapshot

    func testMapUsageResponseToProviderSnapshot() throws {
        let json = """
        {
          "five_hour": { "utilization": 72.5, "resets_at": "2026-05-03T10:00:00Z" },
          "seven_day": { "utilization": 58.2, "resets_at": "2026-05-07T00:00:00Z" }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        let primary = response.fiveHour.map { window -> QuotaRateWindow in
            let resetsAt = Self.parseISO8601(window.resetsAt)
            return QuotaRateWindow(
                usedPercent: window.utilization,
                windowMinutes: 300,
                resetsAt: resetsAt,
                resetDescription: nil
            )
        }

        let secondary = response.sevenDay.map { window -> QuotaRateWindow in
            let resetsAt = Self.parseISO8601(window.resetsAt)
            return QuotaRateWindow(
                usedPercent: window.utilization,
                windowMinutes: 10080,
                resetsAt: resetsAt,
                resetDescription: nil
            )
        }

        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: primary,
            secondary: secondary,
            credits: nil,
            identity: nil,
            error: nil,
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.primary?.usedPercent, 72.5)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 27.5)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 58.2)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10080)
        XCTAssertNotNil(snapshot.primary?.resetsAt)
        XCTAssertNotNil(snapshot.secondary?.resetsAt)
    }

    // MARK: - Credential Parsing

    func testCredentialParsing() throws {
        let json = """
        {
          "accessToken": "sk-ant-test-token-12345",
          "refreshToken": "rt-abcdef",
          "expiresAt": 1715000000.0
        }
        """
        let data = json.data(using: .utf8)!
        let creds = try JSONDecoder().decode(ClaudeCredentials.self, from: data)

        XCTAssertEqual(creds.accessToken, "sk-ant-test-token-12345")
        XCTAssertEqual(creds.refreshToken, "rt-abcdef")
        XCTAssertEqual(creds.expiresAt, 1715000000.0)
    }

    func testCredentialParsingMinimal() throws {
        let json = """
        {
          "accessToken": "sk-ant-minimal"
        }
        """
        let data = json.data(using: .utf8)!
        let creds = try JSONDecoder().decode(ClaudeCredentials.self, from: data)

        XCTAssertEqual(creds.accessToken, "sk-ant-minimal")
        XCTAssertNil(creds.refreshToken)
        XCTAssertNil(creds.expiresAt)
    }

    func testExpiredCredentials() {
        let creds = ClaudeCredentials(
            accessToken: "sk-ant-test",
            refreshToken: nil,
            expiresAt: Date().timeIntervalSince1970 - 3600 // expired 1 hour ago
        )
        let now = Date().timeIntervalSince1970
        let isExpired = creds.expiresAt.map { $0 < now } ?? true
        XCTAssertTrue(isExpired)
    }

    func testValidCredentials() {
        let creds = ClaudeCredentials(
            accessToken: "sk-ant-test",
            refreshToken: nil,
            expiresAt: Date().timeIntervalSince1970 + 3600 // expires in 1 hour
        )
        let now = Date().timeIntervalSince1970
        let isExpired = creds.expiresAt.map { $0 < now } ?? true
        XCTAssertFalse(isExpired)
    }

    // MARK: - Missing Credentials

    func testMissingCredentialsFile() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Don't create the directory — file doesn't exist
        let credPath = tempDir.appendingPathComponent("credentials.json")
        let exists = FileManager.default.fileExists(atPath: credPath.path)
        XCTAssertFalse(exists)
    }

    // MARK: - ISO 8601 Date Parsing

    func testISO8601DateParsing() {
        let dateString = "2026-05-03T10:00:00Z"
        let date = Self.parseISO8601(dateString)
        XCTAssertNotNil(date)

        // Round-trip
        if let parsed = date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let rendered = formatter.string(from: parsed)
            XCTAssertTrue(rendered.hasPrefix("2026-05-03T10:00:00"))
        }
    }

    func testISO8601DateParsingWithTimezone() {
        // Parse a date with non-UTC timezone offset
        let dateString = "2026-05-03T15:00:00+05:00"
        let date = Self.parseISO8601(dateString)
        XCTAssertNotNil(date)

        // Should be equivalent to 10:00 UTC
        let utcString = "2026-05-03T10:00:00Z"
        let utcDate = Self.parseISO8601(utcString)
        if let date, let utcDate {
            XCTAssertEqual(date.timeIntervalSince1970, utcDate.timeIntervalSince1970, accuracy: 1.0)
        }
    }

    // MARK: - Error Mapping

    func testMapMissingCredentialsToError() {
        // When credentials file is missing, provider should produce noCredentials error
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .noCredentials,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .noCredentials)
    }

    func testMapUnauthorizedToError() {
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .unauthorized,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .unauthorized)
    }

    func testMapInvalidResponseToError() {
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .invalidResponse,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .invalidResponse)
    }

    func testMapNetworkErrorToError() {
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .networkError("connection timeout"),
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .networkError("connection timeout"))
    }

    // MARK: - Identity Mapping

    func testMapIdentityFromResponse() {
        let identity = QuotaProviderIdentity(email: "user@example.com", plan: "pro")
        let snapshot = QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: identity,
            error: nil,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.identity?.email, "user@example.com")
        XCTAssertEqual(snapshot.identity?.plan, "pro")
    }

    // MARK: - Helpers

    private static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }
}
