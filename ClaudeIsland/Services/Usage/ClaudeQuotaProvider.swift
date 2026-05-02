//
//  ClaudeQuotaProvider.swift
//  ClaudeIsland
//
//  Fetches Claude OAuth usage quotas from api.anthropic.com/api/oauth/usage.
//

import Foundation

enum ClaudeQuotaProvider {

    // MARK: - Public API

    /// Fetch Claude usage quota from the OAuth API.
    static func fetch() async -> QuotaProviderSnapshot {
        guard let creds = readCredentials() else {
            return Self.makeSnapshot(error: .noCredentials)
        }

        if creds.isExpired {
            return Self.makeSnapshot(error: .unauthorized)
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Self.makeSnapshot(error: .invalidResponse)
            }
            switch http.statusCode {
            case 200:
                let usage = try Self.decodeResponse(data)
                return Self.makeSnapshot(
                    primary: Self.makeWindow(usage.fiveHour, windowMinutes: 300),
                    secondary: Self.makeWindow(usage.sevenDay, windowMinutes: 7 * 24 * 60),
                    credits: Self.makeCredits(usage.extraUsage)
                )
            case 401:
                return Self.makeSnapshot(error: .unauthorized)
            default:
                return Self.makeSnapshot(error: .invalidResponse)
            }
        } catch {
            return Self.makeSnapshot(error: .networkError(error.localizedDescription))
        }
    }

    /// Read OAuth credentials from ~/.claude/.credentials.json (or resolved path).
    static func readCredentials() -> ClaudeCredentials? {
        let url = ClaudePaths.claudeDir.appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? ClaudeCredentials.from(data)
    }

    // MARK: - Constants

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.0"

    // MARK: - Snapshot Helpers

    private static func makeSnapshot(
        primary: QuotaRateWindow? = nil,
        secondary: QuotaRateWindow? = nil,
        credits: QuotaCreditsSnapshot? = nil,
        error: QuotaError? = nil) -> QuotaProviderSnapshot
    {
        QuotaProviderSnapshot(
            provider: .claude,
            primary: primary,
            secondary: secondary,
            credits: credits,
            identity: nil,
            error: error,
            updatedAt: Date()
        )
    }

    private static func makeWindow(_ window: OAuthUsageWindow?, windowMinutes: Int) -> QuotaRateWindow? {
        guard let window else { return nil }
        let usedPercent = window.utilization ?? 0
        return QuotaRateWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: parseISO8601(window.resetsAt),
            resetDescription: nil
        )
    }

    private static func makeCredits(_ extra: OAuthExtraUsage?) -> QuotaCreditsSnapshot? {
        guard let extra, extra.isEnabled == true else { return nil }
        let balance = (extra.monthlyLimit ?? 0) - (extra.usedCredits ?? 0)
        return QuotaCreditsSnapshot(
            hasCredits: true,
            unlimited: false,
            balance: balance
        )
    }

    // MARK: - Decoding

    private static func decodeResponse(_ data: Data) throws -> OAuthUsageResponse {
        try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
    }

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Credential Model

struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let isExpired: Bool

    static func from(_ data: Data) throws -> ClaudeCredentials {
        struct Root: Decodable {
            let claudeAiOauth: OAuth?
        }
        struct OAuth: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let expiresAt: Double?
        }
        let root = try JSONDecoder().decode(Root.self, from: data)
        guard let oauth = root.claudeAiOauth else {
            throw CredentialError.missingOAuth
        }
        let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw CredentialError.missingAccessToken
        }
        let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        return ClaudeCredentials(
            accessToken: token,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt,
            isExpired: expiresAt.map { Date() >= $0 } ?? false
        )
    }

    private enum CredentialError: Error {
        case missingOAuth
        case missingAccessToken
    }
}

// MARK: - API Response Models

private struct OAuthUsageResponse: Decodable {
    let fiveHour: OAuthUsageWindow?
    let sevenDay: OAuthUsageWindow?
    let extraUsage: OAuthExtraUsage?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.fiveHour = Self.decodeIfPresent(OAuthUsageWindow.self, in: container, keys: ["five_hour"])
        self.sevenDay = Self.decodeIfPresent(OAuthUsageWindow.self, in: container, keys: ["seven_day"])
        self.extraUsage = Self.decodeIfPresent(OAuthExtraUsage.self, in: container, keys: ["extra_usage"])
    }

    private static func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        in container: KeyedDecodingContainer<DynamicCodingKey>,
        keys: [String]) -> T?
    {
        for keyName in keys {
            guard let key = DynamicCodingKey(stringValue: keyName) else { continue }
            if let value = try? container.decodeIfPresent(T.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

private struct OAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct OAuthExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case currency
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) { nil }
}
