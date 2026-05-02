//
//  BYOKDetector.swift
//  ClaudeIsland
//
//  Detects BYOK (Bring Your Own Key) configuration from Claude settings
//  and identifies the third-party provider based on the base URL.
//

import Foundation

enum BYOKProvider: String, Sendable, Equatable {
    case zhiPu
    case deepSeek
    case openRouter
    case anthropicAPI
    case unknown

    var displayName: String {
        switch self {
        case .zhiPu: return "ZhiPu/BigModel"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .anthropicAPI: return "Anthropic API"
        case .unknown: return "Custom Provider"
        }
    }

    var hasQuotaEndpoint: Bool {
        switch self {
        case .zhiPu, .deepSeek, .openRouter: return true
        default: return false
        }
    }
}

struct BYOKConfiguration: Sendable, Equatable {
    let provider: BYOKProvider
    let apiKey: String
    let baseURL: String?
}

enum BYOKDetector {

    /// Detect BYOK configuration from the default Claude settings file.
    static func detect() -> BYOKConfiguration? {
        detect(from: ClaudePaths.settingsFile)
    }

    /// Detect BYOK configuration from a specific settings file URL.
    static func detect(from url: URL) -> BYOKConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let env = json["env"] as? [String: String] else { return nil }

        let apiKey = (env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else { return nil }

        let baseURL = env["ANTHROPIC_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = identifyProvider(baseURL: baseURL)

        return BYOKConfiguration(
            provider: provider,
            apiKey: apiKey,
            baseURL: baseURL
        )
    }

    /// Map a base URL string to a known BYOK provider.
    static func identifyProvider(baseURL: String?) -> BYOKProvider {
        guard let url = baseURL?.lowercased(), !url.isEmpty else { return .anthropicAPI }
        if url.contains("open.bigmodel.cn") { return .zhiPu }
        if url.contains("api.deepseek.com") { return .deepSeek }
        if url.contains("openrouter.ai") { return .openRouter }
        if url.contains("api.anthropic.com") { return .anthropicAPI }
        return .unknown
    }
}
