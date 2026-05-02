//
//  CodexQuotaProviderTests.swift
//  ClaudeIslandTests
//
//  Tests for Codex JSON-RPC response parsing used by the quota feature.
//  Since CodexQuotaProvider does not exist yet, these tests validate the
//  JSON-RPC structures that the provider will consume, using local Codable
//  test helpers that mirror the expected JSON-RPC response shape.
//

import Foundation
import XCTest


// MARK: - Test-only Codable types matching the Codex JSON-RPC responses

/// Mirrors the expected JSON-RPC envelope from Codex CLI.
private struct CodexRPCResponse<T: Codable & Equatable>: Codable, Equatable {
    let id: Int
    let result: T?
    let error: CodexRPCError?
}

private struct CodexRPCError: Codable, Equatable {
    let code: Int
    let message: String
}

/// Mirrors the rate limits result from Codex JSON-RPC.
private struct CodexRateLimitsResult: Codable, Equatable {
    let rateLimits: CodexRateLimits
}

private struct CodexRateLimits: Codable, Equatable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Codable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Double
}

/// Mirrors the account info result from Codex JSON-RPC.
private struct CodexAccountResult: Codable, Equatable {
    let email: String?
    let plan: String?
    let credits: CodexCreditsInfo?
}

private struct CodexCreditsInfo: Codable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?
}

// MARK: - Tests

final class CodexQuotaProviderTests: XCTestCase {

    // MARK: - Rate Limits Response Decoding

    func testDecodeRateLimitsResponse() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 42.0, "windowDurationMins": 300, "resetsAt": 1715000000 },
              "secondary": { "usedPercent": 18.0, "windowDurationMins": 10080, "resetsAt": 1715400000 }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        XCTAssertEqual(response.id, 2)
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)

        let limits = response.result?.rateLimits
        XCTAssertEqual(limits?.primary?.usedPercent, 42.0)
        XCTAssertEqual(limits?.primary?.windowDurationMins, 300)
        XCTAssertEqual(limits?.primary?.resetsAt, 1715000000)
        XCTAssertEqual(limits?.secondary?.usedPercent, 18.0)
        XCTAssertEqual(limits?.secondary?.windowDurationMins, 10080)
        XCTAssertEqual(limits?.secondary?.resetsAt, 1715400000)
    }

    func testDecodeRateLimitsWithOnlyPrimary() throws {
        let json = """
        {
          "id": 3,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 75.0, "windowDurationMins": 300, "resetsAt": 1715100000 }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        XCTAssertEqual(response.result?.rateLimits.primary?.usedPercent, 75.0)
        XCTAssertNil(response.result?.rateLimits.secondary)
    }

    func testDecodeRateLimitsWithCredits() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 42.0, "windowDurationMins": 300, "resetsAt": 1715000000 },
              "secondary": { "usedPercent": 18.0, "windowDurationMins": 10080, "resetsAt": 1715400000 }
            },
            "rateCredits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": 25.0
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        // Verify rate limits still decode properly even with extra fields
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )
        XCTAssertEqual(response.result?.rateLimits.primary?.usedPercent, 42.0)
    }

    // MARK: - Account Response Decoding

    func testDecodeAccountResponse() throws {
        let json = """
        {
          "id": 1,
          "result": {
            "email": "user@example.com",
            "plan": "pro",
            "credits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": 50.0
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexAccountResult>.self, from: data
        )

        XCTAssertEqual(response.id, 1)
        XCTAssertEqual(response.result?.email, "user@example.com")
        XCTAssertEqual(response.result?.plan, "pro")
        XCTAssertEqual(response.result?.credits?.hasCredits, true)
        XCTAssertEqual(response.result?.credits?.unlimited, false)
        XCTAssertEqual(response.result?.credits?.balance, 50.0)
    }

    func testDecodeAccountResponseMinimal() throws {
        let json = """
        {
          "id": 1,
          "result": {
            "email": "user@example.com"
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexAccountResult>.self, from: data
        )

        XCTAssertEqual(response.result?.email, "user@example.com")
        XCTAssertNil(response.result?.plan)
        XCTAssertNil(response.result?.credits)
    }

    // MARK: - RPC Error Response

    func testRPCErrorResponse() throws {
        let json = """
        {
          "id": 2,
          "error": {
            "code": -32600,
            "message": "Invalid request"
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        XCTAssertEqual(response.id, 2)
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid request")
    }

    func testRPCErrorResponseUnauthorized() throws {
        let json = """
        {
          "id": 2,
          "error": {
            "code": 401,
            "message": "Unauthorized: Invalid or expired token"
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        XCTAssertEqual(response.error?.code, 401)
        XCTAssertTrue(response.error?.message.contains("Unauthorized") ?? false)
    }

    // MARK: - Mapping to QuotaProviderSnapshot

    func testMapRateLimitsToProviderSnapshot() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 42.0, "windowDurationMins": 300, "resetsAt": 1715000000 },
              "secondary": { "usedPercent": 18.0, "windowDurationMins": 10080, "resetsAt": 1715400000 }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        let limits = try XCTUnwrap(response.result?.rateLimits)

        let primary = limits.primary.map { window -> QuotaRateWindow in
            QuotaRateWindow(
                usedPercent: window.usedPercent,
                windowMinutes: window.windowDurationMins,
                resetsAt: Date(timeIntervalSince1970: window.resetsAt),
                resetDescription: nil
            )
        }

        let secondary = limits.secondary.map { window -> QuotaRateWindow in
            QuotaRateWindow(
                usedPercent: window.usedPercent,
                windowMinutes: window.windowDurationMins,
                resetsAt: Date(timeIntervalSince1970: window.resetsAt),
                resetDescription: nil
            )
        }

        let snapshot = QuotaProviderSnapshot(
            provider: .codex,
            primary: primary,
            secondary: secondary,
            credits: nil,
            identity: nil,
            error: nil,
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.primary?.usedPercent, 42.0)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 58.0)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 18.0)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10080)
        XCTAssertNotNil(snapshot.primary?.resetsAt)
        XCTAssertNotNil(snapshot.secondary?.resetsAt)
    }

    func testMapRateLimitsWithCreditsToSnapshot() throws {
        let accountJson = """
        {
          "id": 1,
          "result": {
            "email": "dev@test.com",
            "plan": "max",
            "credits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": 100.0
            }
          }
        }
        """
        let data = accountJson.data(using: .utf8)!
        let accountResponse = try JSONDecoder().decode(
            CodexRPCResponse<CodexAccountResult>.self, from: data
        )
        let account = try XCTUnwrap(accountResponse.result)

        let credits = QuotaCreditsSnapshot(
            hasCredits: account.credits?.hasCredits ?? false,
            unlimited: account.credits?.unlimited ?? false,
            balance: account.credits?.balance
        )

        let identity = QuotaProviderIdentity(
            email: account.email,
            plan: account.plan
        )

        let snapshot = QuotaProviderSnapshot(
            provider: .codex,
            primary: nil,
            secondary: nil,
            credits: credits,
            identity: identity,
            error: nil,
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.credits?.hasCredits, true)
        XCTAssertEqual(snapshot.credits?.unlimited, false)
        XCTAssertEqual(snapshot.credits?.balance, 100.0)
        XCTAssertEqual(snapshot.identity?.email, "dev@test.com")
        XCTAssertEqual(snapshot.identity?.plan, "max")
    }

    // MARK: - Codex Binary Not Found

    func testCodexBinaryNotFound() {
        // Simulate the binary not being found on the system
        let snapshot = QuotaProviderSnapshot(
            provider: .codex,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: nil,
            error: .notAvailable,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.error, .notAvailable)
    }

    func testCodexBinaryNotFoundProcessFailure() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex_nonexistent_binary_test"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertNil(output == "" ? nil : output)
        } catch {
            // Process failed to launch — also acceptable
        }
    }

    // MARK: - Timestamp Date Parsing

    func testResetsAtTimestampToDate() {
        let timestamp: Double = 1715000000
        let date = Date(timeIntervalSince1970: timestamp)
        // Verify the date is reasonable (sometime in 2024)
        let year = Calendar.current.component(.year, from: date)
        XCTAssertEqual(year, 2024)
    }

    // MARK: - Edge Cases

    func testDecodeEmptyRateLimits() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {}
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            CodexRPCResponse<CodexRateLimitsResult>.self, from: data
        )

        XCTAssertNil(response.result?.rateLimits.primary)
        XCTAssertNil(response.result?.rateLimits.secondary)
    }

    func testMapErrorRPCResponseToQuotaError() {
        let rpcError = CodexRPCError(code: 401, message: "Unauthorized")
        let error: QuotaError = rpcError.code == 401 ? .unauthorized : .invalidResponse
        XCTAssertEqual(error, .unauthorized)
    }
}
