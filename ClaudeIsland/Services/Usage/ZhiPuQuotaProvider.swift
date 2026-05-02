//
//  ZhiPuQuotaProvider.swift
//  ClaudeIsland
//
//  Fetches quota from the ZhiPu/BigModel API (BYOK).
//

import Foundation

enum ZhiPuQuotaProvider {

    // MARK: - Public API

    /// Fetch quota from ZhiPu/BigModel API using the provided API key.
    static func fetch(apiKey: String) async -> QuotaProviderSnapshot {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return Self.makeSnapshot(error: .noCredentials)
        }

        var request = URLRequest(url: Self.quotaURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return Self.makeSnapshot(error: .invalidResponse)
            }

            switch http.statusCode {
            case 200:
                break
            case 401, 403:
                return Self.makeSnapshot(error: .unauthorized)
            default:
                return Self.makeSnapshot(error: .invalidResponse)
            }

            guard !data.isEmpty else {
                return Self.makeSnapshot(error: .invalidResponse)
            }

            return try Self.parseResponse(data)
        } catch {
            return Self.makeSnapshot(error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - Constants

    private static let quotaURL = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!

    // MARK: - Snapshot Helpers

    private static func makeSnapshot(
        primary: QuotaRateWindow? = nil,
        secondary: QuotaRateWindow? = nil,
        error: QuotaError? = nil
    ) -> QuotaProviderSnapshot {
        QuotaProviderSnapshot(
            provider: .claude,
            primary: primary,
            secondary: secondary,
            credits: nil,
            identity: QuotaProviderIdentity(email: nil, plan: "BYOK: ZhiPu/BigModel"),
            error: error,
            updatedAt: Date()
        )
    }

    // MARK: - Parsing

    private static func parseResponse(_ data: Data) throws -> QuotaProviderSnapshot {
        let apiResponse = try JSONDecoder().decode(ZhiPuQuotaResponse.self, from: data)

        guard apiResponse.success, apiResponse.code == 200 else {
            return Self.makeSnapshot(error: .invalidResponse)
        }

        guard let responseData = apiResponse.data else {
            return Self.makeSnapshot(error: .invalidResponse)
        }

        var tokenLimits: [ParsedLimit] = []
        var timeLimit: ParsedLimit?

        for raw in responseData.limits {
            guard let parsed = Self.parseLimit(raw) else { continue }
            switch parsed.type {
            case "TOKENS_LIMIT":
                tokenLimits.append(parsed)
            case "TIME_LIMIT":
                timeLimit = parsed
            default:
                break
            }
        }

        // Multiple TOKENS_LIMIT entries: shortest window -> tertiary (ignored for now),
        // longest -> primary.
        let primaryLimit: ParsedLimit?
        if tokenLimits.count >= 2 {
            let sorted = tokenLimits.sorted { ($0.windowMinutes ?? Int.max) < ($1.windowMinutes ?? Int.max) }
            primaryLimit = sorted.last
        } else {
            primaryLimit = tokenLimits.first
        }

        return Self.makeSnapshot(
            primary: primaryLimit.map { Self.makeWindow($0) },
            secondary: timeLimit.map { Self.makeWindow($0) }
        )
    }

    private static func parseLimit(_ raw: ZhiPuLimitRaw) -> ParsedLimit? {
        let windowMinutes = Self.windowMinutes(unit: raw.unit, number: raw.number)
        let resetsAt = raw.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let usedPercent = Self.computeUsedPercent(
            usage: raw.usage,
            currentValue: raw.currentValue,
            remaining: raw.remaining,
            fallbackPercentage: raw.percentage
        )

        return ParsedLimit(
            type: raw.type,
            isTokenBased: raw.type == "TOKENS_LIMIT",
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    private static func computeUsedPercent(
        usage: Int?,
        currentValue: Int?,
        remaining: Int?,
        fallbackPercentage: Int?
    ) -> Double {
        guard let limit = usage, limit > 0 else {
            return Double(fallbackPercentage ?? 0)
        }

        var usedRaw: Int?
        if let remaining {
            let usedFromRemaining = limit - remaining
            if let currentValue {
                usedRaw = max(usedFromRemaining, currentValue)
            } else {
                usedRaw = usedFromRemaining
            }
        } else if let currentValue {
            usedRaw = currentValue
        }

        guard let usedRaw else {
            return Double(fallbackPercentage ?? 0)
        }

        let used = max(0, min(limit, usedRaw))
        let percent = (Double(used) / Double(limit)) * 100
        return min(100, max(0, percent))
    }

    private static func windowMinutes(unit: Int, number: Int) -> Int? {
        guard number > 0 else { return nil }
        switch unit {
        case 1: return number * 24 * 60       // days
        case 3: return number * 60             // hours
        case 5: return number                  // minutes
        case 6: return number * 7 * 24 * 60   // weeks
        default: return nil
        }
    }

    private static func makeWindow(_ limit: ParsedLimit) -> QuotaRateWindow {
        QuotaRateWindow(
            usedPercent: limit.usedPercent,
            windowMinutes: limit.isTokenBased ? limit.windowMinutes : nil,
            resetsAt: limit.resetsAt,
            resetDescription: nil
        )
    }
}

// MARK: - Internal Helpers

private struct ParsedLimit {
    let type: String
    let isTokenBased: Bool
    let windowMinutes: Int?
    let usedPercent: Double
    let resetsAt: Date?
}

// MARK: - API Response Models

private struct ZhiPuQuotaResponse: Decodable {
    let code: Int
    let msg: String
    let success: Bool
    let data: ZhiPuQuotaData?
}

private struct ZhiPuQuotaData: Decodable {
    let limits: [ZhiPuLimitRaw]
    let planName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.limits = try container.decodeIfPresent([ZhiPuLimitRaw].self, forKey: .limits) ?? []
        let rawPlan = try container.decodeIfPresent(String.self, forKey: .planName)
        let trimmed = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.planName = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case limits
        case planName
    }
}

private struct ZhiPuLimitRaw: Decodable {
    let type: String
    let unit: Int
    let number: Int
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let percentage: Int?
    let nextResetTime: Int?

    enum CodingKeys: String, CodingKey {
        case type, unit, number, usage
        case currentValue
        case remaining, percentage
        case nextResetTime
    }
}
