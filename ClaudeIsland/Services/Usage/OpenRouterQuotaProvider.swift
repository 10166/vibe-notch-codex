//
//  OpenRouterQuotaProvider.swift
//  ClaudeIsland
//
//  Fetches credit usage from the OpenRouter API for BYOK quota tracking.
//

import Foundation

enum OpenRouterQuotaProvider {

    // MARK: - Public API

    /// Fetch OpenRouter credit usage using the provided API key.
    static func fetch(apiKey: String) async -> QuotaProviderSnapshot {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return Self.makeSnapshot(error: .noCredentials)
        }

        var request = URLRequest(url: Self.creditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VibeNotch", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = Self.creditsTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Self.makeSnapshot(error: .invalidResponse)
            }
            guard http.statusCode == 200 else {
                return Self.makeSnapshot(error: http.statusCode == 401 ? .unauthorized : .invalidResponse)
            }

            let credits = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
            let balance = max(0, credits.data.totalCredits - credits.data.totalUsage)
            let creditsUsedPercent = credits.data.totalCredits > 0
                ? min(100, (credits.data.totalUsage / credits.data.totalCredits) * 100)
                : 0

            // Optionally enrich with key endpoint data (non-blocking, short timeout).
            var usedPercent = creditsUsedPercent
            if let keyData = await Self.fetchKeyData(apiKey: trimmedKey),
               let limit = keyData.limit, limit > 0,
               let usage = keyData.usage
            {
                usedPercent = min(100, max(0, (usage / limit) * 100))
            }

            return QuotaProviderSnapshot(
                provider: .claude,
                primary: QuotaRateWindow(
                    usedPercent: usedPercent,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil
                ),
                secondary: nil,
                credits: QuotaCreditsSnapshot(hasCredits: true, unlimited: false, balance: balance),
                identity: QuotaProviderIdentity(
                    email: nil,
                    plan: "BYOK: OpenRouter"
                ),
                error: nil,
                updatedAt: Date()
            )
        } catch {
            return Self.makeSnapshot(error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - Constants

    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!
    private static let creditsTimeout: TimeInterval = 15
    private static let keyTimeout: TimeInterval = 1

    // MARK: - Key Enrichment

    /// Fetch optional key data with a short timeout. Returns nil on any failure.
    private static func fetchKeyData(apiKey: String) async -> OpenRouterKeyData? {
        await withTaskGroup(of: OpenRouterKeyData?.self) { group in
            group.addTask {
                var request = URLRequest(url: Self.keyURL)
                request.httpMethod = "GET"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = Self.keyTimeout

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        return nil
                    }
                    let keyResponse = try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)
                    return keyResponse.data
                } catch {
                    return nil
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.keyTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return nil }
                return nil
            }

            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    // MARK: - Snapshot Helper

    private static func makeSnapshot(error: QuotaError) -> QuotaProviderSnapshot {
        QuotaProviderSnapshot(
            provider: .claude,
            primary: nil,
            secondary: nil,
            credits: nil,
            identity: QuotaProviderIdentity(email: nil, plan: "BYOK: OpenRouter"),
            error: error,
            updatedAt: Date()
        )
    }
}

// MARK: - Private Response Models

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: Double
    let totalUsage: Double

    private enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

private struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

private struct OpenRouterKeyData: Decodable {
    let limit: Double?
    let usage: Double?
}
