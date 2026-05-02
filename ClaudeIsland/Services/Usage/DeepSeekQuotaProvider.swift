//
//  DeepSeekQuotaProvider.swift
//  ClaudeIsland
//
//  Fetches balance from the DeepSeek API for BYOK quota display.
//

import Foundation

enum DeepSeekQuotaProvider {

    // MARK: - Public API

    /// Fetch DeepSeek account balance using the provided API key.
    static func fetch(apiKey: String) async -> QuotaProviderSnapshot {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return Self.makeSnapshot(error: .noCredentials)
        }

        var request = URLRequest(url: Self.balanceURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Self.makeSnapshot(error: .invalidResponse)
            }
            switch http.statusCode {
            case 200:
                return try Self.parseSnapshot(data)
            case 401:
                return Self.makeSnapshot(error: .unauthorized)
            default:
                return Self.makeSnapshot(error: .invalidResponse)
            }
        } catch {
            return Self.makeSnapshot(error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - Constants

    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    // MARK: - Snapshot Helpers

    private static func makeSnapshot(
        primary: QuotaRateWindow? = nil,
        credits: QuotaCreditsSnapshot? = nil,
        identity: QuotaProviderIdentity? = nil,
        error: QuotaError? = nil
    ) -> QuotaProviderSnapshot {
        QuotaProviderSnapshot(
            provider: .claude,
            primary: primary,
            secondary: nil,
            credits: credits,
            identity: identity ?? QuotaProviderIdentity(email: nil, plan: "BYOK: DeepSeek"),
            error: error,
            updatedAt: Date()
        )
    }

    // MARK: - Parsing

    private static func parseSnapshot(_ data: Data) throws -> QuotaProviderSnapshot {
        let decoded: DeepSeekBalanceResponse
        do {
            decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            return Self.makeSnapshot(error: .invalidResponse)
        }

        // Prefer USD entry; fall back to first available.
        let info = decoded.balanceInfos.first { $0.currency == "USD" }
            ?? decoded.balanceInfos.first

        guard let info else {
            return Self.makeSnapshot(
                primary: QuotaRateWindow(usedPercent: 100, resetDescription: "No balance info available"),
                credits: QuotaCreditsSnapshot(hasCredits: false, unlimited: false, balance: 0)
            )
        }

        guard let totalBalance = Double(info.totalBalance),
              let grantedBalance = Double(info.grantedBalance),
              let toppedUpBalance = Double(info.toppedUpBalance)
        else {
            return Self.makeSnapshot(error: .invalidResponse)
        }

        let symbol = info.currency == "CNY" ? "\u{00A5}" : "$"

        let usedPercent: Double
        let balanceDetail: String

        if !decoded.isAvailable || totalBalance <= 0 {
            usedPercent = 100
            balanceDetail = "\(symbol)\(String(format: "%.2f", totalBalance)) — add credits at platform.deepseek.com"
        } else {
            usedPercent = 0
            let total = String(format: "\(symbol)%.2f", totalBalance)
            let paid = String(format: "\(symbol)%.2f", toppedUpBalance)
            let granted = String(format: "\(symbol)%.2f", grantedBalance)
            balanceDetail = "\(total) (Paid: \(paid) / Granted: \(granted))"
        }

        return Self.makeSnapshot(
            primary: QuotaRateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: balanceDetail
            ),
            credits: QuotaCreditsSnapshot(hasCredits: true, unlimited: false, balance: totalBalance),
            identity: QuotaProviderIdentity(email: nil, plan: "BYOK: DeepSeek")
        )
    }
}

// MARK: - API Response Models

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}
