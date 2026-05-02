//
//  CodexQuotaProvider.swift
//  ClaudeIsland
//
//  Fetches Codex API usage quotas via JSON-RPC or OAuth fallback.
//

import Foundation

// MARK: - Public Interface

enum CodexQuotaProvider {
    /// Fetch Codex usage quota (tries RPC first, falls back to OAuth).
    static func fetch() async -> QuotaProviderSnapshot {
        do {
            return try await fetchViaRPC()
        } catch {
            // If RPC fails, try OAuth fallback.
            if let oauthSnapshot = await fetchViaOAuth() {
                return oauthSnapshot
            }
            return QuotaProviderSnapshot(
                provider: .codex,
                primary: nil,
                secondary: nil,
                credits: nil,
                identity: nil,
                error: mapError(error),
                updatedAt: Date()
            )
        }
    }
}

// MARK: - RPC Path

extension CodexQuotaProvider {
    private static func fetchViaRPC() async throws -> QuotaProviderSnapshot {
        let client = try CodexRPCClient()
        defer { client.shutdown() }

        try await client.initialize(clientName: "vibe-notch", clientVersion: "1.0")

        let limits = try await client.fetchRateLimits().rateLimits
        let account = try? await client.fetchAccount()

        let primary = Self.mapWindow(limits.primary)
        let secondary = Self.mapWindow(limits.secondary)
        let credits = Self.mapCredits(limits.credits)
        let identity = Self.mapAccount(account?.account)

        return QuotaProviderSnapshot(
            provider: .codex,
            primary: primary,
            secondary: secondary,
            credits: credits,
            identity: identity,
            error: nil,
            updatedAt: Date()
        )
    }

    private static func mapWindow(_ rpc: RPCRateLimitWindow?) -> QuotaRateWindow? {
        guard let rpc else { return nil }
        let resetsAtDate = rpc.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return QuotaRateWindow(
            usedPercent: rpc.usedPercent,
            windowMinutes: rpc.windowDurationMins,
            resetsAt: resetsAtDate,
            resetDescription: resetsAtDate.map { Self.resetDescription(from: $0) }
        )
    }

    private static func mapCredits(_ rpc: RPCCreditsSnapshot?) -> QuotaCreditsSnapshot? {
        guard let rpc else { return nil }
        return QuotaCreditsSnapshot(
            hasCredits: rpc.hasCredits,
            unlimited: rpc.unlimited,
            balance: rpc.balance.flatMap { Double($0) }
        )
    }

    private static func mapAccount(_ details: RPCAccountDetails?) -> QuotaProviderIdentity? {
        guard let details else { return nil }
        switch details {
        case let .chatgpt(email, planType):
            return QuotaProviderIdentity(email: email, plan: planType)
        case .apiKey:
            return QuotaProviderIdentity(email: nil, plan: "apikey")
        }
    }

    private static func resetDescription(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - OAuth Fallback

extension CodexQuotaProvider {
    private static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private static func fetchViaOAuth() async -> QuotaProviderSnapshot? {
        let authFile = CodexPaths.codexDir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authFile),
              let creds = try? JSONDecoder().decode(CodexOAuthCredentials.self, from: data),
              let accessToken = creds.accessToken
        else {
            return nil
        }

        var request = URLRequest(url: Self.codexUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("vibe-notch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            return QuotaProviderSnapshot(
                provider: .codex,
                primary: nil,
                secondary: nil,
                credits: nil,
                identity: nil,
                error: .networkError(error.localizedDescription),
                updatedAt: Date()
            )
        }

        guard let http = response as? HTTPURLResponse else {
            return QuotaProviderSnapshot(
                provider: .codex,
                primary: nil,
                secondary: nil,
                credits: nil,
                identity: nil,
                error: .invalidResponse,
                updatedAt: Date()
            )
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            return QuotaProviderSnapshot(
                provider: .codex,
                primary: nil,
                secondary: nil,
                credits: nil,
                identity: nil,
                error: .unauthorized,
                updatedAt: Date()
            )
        default:
            return nil
        }

        guard let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: responseData) else {
            return QuotaProviderSnapshot(
                provider: .codex,
                primary: nil,
                secondary: nil,
                credits: nil,
                identity: nil,
                error: .invalidResponse,
                updatedAt: Date()
            )
        }

        let primary = usage.rateLimit?.primaryWindow.map {
            Self.mapOAuthWindow($0)
        }
        let secondary = usage.rateLimit?.secondaryWindow.map {
            Self.mapOAuthWindow($0)
        }
        let credits = usage.credits.map {
            QuotaCreditsSnapshot(
                hasCredits: $0.hasCredits,
                unlimited: $0.unlimited,
                balance: $0.balance
            )
        }
        let identity: QuotaProviderIdentity? = usage.planType.map {
            QuotaProviderIdentity(email: nil, plan: $0.rawValue)
        }

        return QuotaProviderSnapshot(
            provider: .codex,
            primary: primary,
            secondary: secondary,
            credits: credits,
            identity: identity,
            error: nil,
            updatedAt: Date()
        )
    }

    private static func mapOAuthWindow(_ window: CodexUsageResponse.WindowSnapshot) -> QuotaRateWindow {
        let resetsAtDate = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        return QuotaRateWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: resetsAtDate,
            resetDescription: Self.resetDescription(from: resetsAtDate)
        )
    }
}

// MARK: - Error Mapping

extension CodexQuotaProvider {
    private static func mapError(_ error: Error) -> QuotaError {
        if let rpcError = error as? RPCWireError {
            switch rpcError {
            case .startFailed:
                return .notAvailable
            case .requestFailed, .malformed:
                return .invalidResponse
            }
        }
        return .notAvailable
    }
}

// MARK: - RPC Wire Types

private enum RPCWireError: Error {
    case startFailed(String)
    case requestFailed(String)
    case malformed(String)
}

private struct RPCRateLimitsResponse: Decodable {
    let rateLimits: RPCRateLimitSnapshot
}

private struct RPCRateLimitSnapshot: Decodable {
    let primary: RPCRateLimitWindow?
    let secondary: RPCRateLimitWindow?
    let credits: RPCCreditsSnapshot?
}

private struct RPCRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private struct RPCCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

private struct RPCAccountResponse: Decodable {
    let account: RPCAccountDetails?
}

private enum RPCAccountDetails: Decodable {
    case apiKey
    case chatgpt(email: String, planType: String)

    enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "apikey":
            self = .apiKey
        case "chatgpt":
            let email = try container.decodeIfPresent(String.self, forKey: .email) ?? "unknown"
            let plan = try container.decodeIfPresent(String.self, forKey: .planType) ?? "unknown"
            self = .chatgpt(email: email, planType: plan)
        default:
            self = .chatgpt(email: "unknown", planType: type)
        }
    }
}

// MARK: - OAuth Response Types

private struct CodexUsageResponse: Decodable {
    let planType: PlanType?
    let rateLimit: RateLimitDetails?
    let credits: CreditDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    enum PlanType: String, Decodable, Sendable {
        case guest
        case free
        case go
        case plus
        case pro
        case team
        case business
        case enterprise
    }

    struct RateLimitDetails: Decodable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable {
        let usedPercent: Int
        let resetAt: Int
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    struct CreditDetails: Decodable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Double?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
            unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
            if let value = try? container.decode(Double.self, forKey: .balance) {
                balance = value
            } else if let str = try? container.decode(String.self, forKey: .balance),
                      let parsed = Double(str)
            {
                balance = parsed
            } else {
                balance = nil
            }
        }
    }
}

private struct CodexOAuthCredentials: Decodable {
    let accessToken: String?
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountId = "account_id"
    }
}

// MARK: - RPC Client

private final class CodexRPCClient: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutLineStream: AsyncStream<Data>
    private let stdoutLineContinuation: AsyncStream<Data>.Continuation
    private var nextID = 1

    // MARK: - Line Buffer

    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrainLines(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if !lineData.isEmpty {
                    lines.append(lineData)
                }
            }
            return lines
        }
    }

    // MARK: - Init

    init() throws {
        var stdoutContinuation: AsyncStream<Data>.Continuation!
        stdoutLineStream = AsyncStream<Data> { continuation in
            stdoutContinuation = continuation
        }
        stdoutLineContinuation = stdoutContinuation

        guard let resolvedExec = Self.which("codex") else {
            throw RPCWireError.startFailed("Codex CLI not found")
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [resolvedExec, "-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RPCWireError.startFailed(error.localizedDescription)
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let continuation = stdoutLineContinuation
        let lineBuffer = LineBuffer()
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
                return
            }
            let lines = lineBuffer.appendAndDrainLines(data)
            for line in lines {
                continuation.yield(line)
            }
        }

        // Drain stderr to avoid blocking the child process.
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }

    // MARK: - Public API

    func initialize(clientName: String, clientVersion: String) async throws {
        _ = try await request(
            method: "initialize",
            params: ["clientInfo": ["name": clientName, "version": clientVersion]]
        )
        try sendNotification(method: "initialized")
    }

    func fetchRateLimits() async throws -> RPCRateLimitsResponse {
        let message = try await request(method: "account/rateLimits/read")
        return try decodeResult(from: message)
    }

    func fetchAccount() async throws -> RPCAccountResponse {
        let message = try await request(method: "account/read")
        return try decodeResult(from: message)
    }

    func shutdown() {
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - JSON-RPC Helpers

    private func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try sendRequest(id: id, method: method, params: params)

        while true {
            let message = try await readNextMessage()

            // Skip notifications (no id field).
            if message["id"] == nil, message["method"] != nil {
                continue
            }

            guard let messageID = jsonID(message["id"]), messageID == id else { continue }

            if let error = message["error"] as? [String: Any],
               let messageText = error["message"] as? String
            {
                throw RPCWireError.requestFailed(messageText)
            }

            return message
        }
    }

    private func sendNotification(method: String) throws {
        try sendPayload(["method": method, "params": [:]])
    }

    private func sendRequest(id: Int, method: String, params: [String: Any]?) throws {
        let paramsValue: Any = params ?? [:]
        try sendPayload(["id": id, "method": method, "params": paramsValue])
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await lineData in stdoutLineStream {
            if lineData.isEmpty { continue }
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                return json
            }
        }
        throw RPCWireError.malformed("codex app-server closed stdout")
    }

    private func decodeResult<T: Decodable>(from message: [String: Any]) throws -> T {
        guard let result = message["result"] else {
            throw RPCWireError.malformed("missing result field")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonID(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: int
        case let number as NSNumber: number.intValue
        default: nil
        }
    }

    // MARK: - Binary Lookup

    private static func which(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty ?? true) ? nil : path
        } catch {
            return nil
        }
    }
}
