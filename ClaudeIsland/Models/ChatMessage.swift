//
//  ChatMessage.swift
//  ClaudeIsland
//
//  Models for conversation messages parsed from JSONL
//

import Foundation
import CryptoKit

/// Produces a stable hex hash string that is consistent across app launches.
/// Swift's hashValue is randomized per process, making it unsuitable for identifiers.
enum StableHash {
    static func hash(_ string: Substring) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.prefix(8).joined()
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole
    let timestamp: Date
    let content: [MessageBlock]

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// Plain text content combined
    var textContent: String {
        content.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}

enum ChatRole: String, Equatable {
    case user
    case assistant
    case system
}

enum MessageBlock: Equatable, Identifiable {
    case text(String)
    case toolUse(ToolUseBlock)
    case thinking(String)
    case image(ImageBlock)
    case meta(MetaMessageBlock)
    case interrupted

    var id: String {
        switch self {
        case .text(let text):
            return "text-\(StableHash.hash(text.prefix(100)))"
        case .toolUse(let block):
            return "tool-\(block.id)"
        case .thinking(let text):
            return "thinking-\(StableHash.hash(text.prefix(100)))"
        case .image(let block):
            return "image-\(block.id)"
        case .meta(let block):
            return "meta-\(block.id)"
        case .interrupted:
            return "interrupted"
        }
    }

    /// Type prefix for generating stable IDs
    nonisolated var typePrefix: String {
        switch self {
        case .text: return "text"
        case .toolUse: return "tool"
        case .thinking: return "thinking"
        case .image: return "image"
        case .meta: return "meta"
        case .interrupted: return "interrupted"
        }
    }
}

/// Represents an inline image attached to a message — base64-encoded with a
/// media type (e.g. "image/png"). Claude Code stores these both as top-level
/// user message blocks and nested inside tool_result content arrays.
struct ImageBlock: Equatable {
    let mediaType: String
    let base64Data: String

    /// Stable identifier based on the data contents so SwiftUI doesn't
    /// re-render images unnecessarily across parses.
    var id: String {
        StableHash.hash(base64Data.prefix(200))
    }
}

struct ToolUseBlock: Equatable {
    let id: String
    let name: String
    let input: [String: String]

    /// Short preview of the tool input
    var preview: String {
        if let filePath = input["file_path"] ?? input["path"] {
            return filePath
        }
        if let command = input["command"] {
            let firstLine = command.components(separatedBy: "\n").first ?? command
            return String(firstLine.prefix(50))
        }
        if let pattern = input["pattern"] {
            return pattern
        }
        return input.values.first.map { String($0.prefix(50)) } ?? ""
    }
}

enum MetaMessageKind: String, Equatable, Sendable {
    case command
    case image
    case skill
    case taskNotification
    case teammate
    case localCommand
    case systemNotice
    case toolError
}

struct MetaMessageBlock: Equatable, Sendable {
    let kind: MetaMessageKind
    let title: String
    let subtitle: String?
    let detail: String?

    var id: String {
        StableHash.hash("\(kind.rawValue)|\(title)|\(subtitle ?? "")|\(detail ?? "")".prefix(240))
    }
}

enum MetaMessageParser {
    static func parse(_ rawText: String) -> MetaMessageBlock? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("<") else { return nil }

        if text.hasPrefix("<local-command-caveat") {
            return nil
        }

        if text.hasPrefix("<command-message") || text.hasPrefix("<command-name") {
            return parseCommand(text)
        }

        if text.hasPrefix("<image") || text == "</image>" {
            return parseImage(text)
        }

        if text.hasPrefix("<skill") {
            return parseSkill(text)
        }

        if text.hasPrefix("<task-notification") {
            return parseTaskNotification(text)
        }

        if text.hasPrefix("<teammate-message") {
            return parseTeammateMessage(text)
        }

        if text.hasPrefix("<local-command-stdout") {
            let output = extractTag("local-command-stdout", from: text) ?? stripXMLTags(text)
            return MetaMessageBlock(kind: .localCommand, title: "Local command", subtitle: truncate(output, limit: 90), detail: output)
        }

        if text.hasPrefix("<system-reminder") {
            let message = extractTag("system-reminder", from: text) ?? stripXMLTags(text)
            return MetaMessageBlock(kind: .systemNotice, title: "System notice", subtitle: truncate(message, limit: 90), detail: message)
        }

        if text.hasPrefix("<tool_use_error") {
            let message = extractTag("tool_use_error", from: text) ?? stripXMLTags(text)
            return MetaMessageBlock(kind: .toolError, title: "Tool error", subtitle: truncate(message, limit: 90), detail: message)
        }

        return nil
    }

    static func readableText(_ rawText: String) -> String {
        if let meta = parse(rawText) {
            return meta.detail ?? meta.subtitle ?? meta.title
        }
        return rawText
    }

    private static func parseCommand(_ text: String) -> MetaMessageBlock? {
        let message = extractTag("command-message", from: text)
        let name = extractTag("command-name", from: text)
        let args = extractTag("command-args", from: text)
        let title = message?.isEmpty == false ? message! : (name ?? "Command")
        let subtitle = [name, truncate(args, limit: 120)]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        return MetaMessageBlock(
            kind: .command,
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            detail: args
        )
    }

    private static func parseImage(_ text: String) -> MetaMessageBlock {
        let marker = extractBracketValue(named: "name", from: text)
        return MetaMessageBlock(
            kind: .image,
            title: "Image",
            subtitle: marker ?? "Attached image",
            detail: nil
        )
    }

    private static func parseSkill(_ text: String) -> MetaMessageBlock {
        let name = extractTag("name", from: text)
        let path = extractTag("path", from: text)
        let title = name?.isEmpty == false ? name! : "Skill"
        let subtitle = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? path
        return MetaMessageBlock(kind: .skill, title: title, subtitle: subtitle, detail: path)
    }

    private static func parseTaskNotification(_ text: String) -> MetaMessageBlock {
        let status = extractTag("status", from: text)
        let summary = extractTag("summary", from: text)
        let taskId = extractTag("task-id", from: text)
        let outputFile = extractTag("output-file", from: text)
        let subtitle = summary ?? status ?? taskId.map { "Task \($0.prefix(8))" }
        return MetaMessageBlock(
            kind: .taskNotification,
            title: "Task notification",
            subtitle: subtitle,
            detail: outputFile
        )
    }

    private static func parseTeammateMessage(_ text: String) -> MetaMessageBlock {
        let teammate = extractAttribute("teammate_id", from: text) ?? "Teammate"
        let summary = extractAttribute("summary", from: text)
        let body = stripOuterTag("teammate-message", from: text).map(stripXMLTags)
        let subtitle = summary ?? body.flatMap { firstUsefulLine($0) }
        return MetaMessageBlock(
            kind: .teammate,
            title: teammate,
            subtitle: truncate(subtitle, limit: 110),
            detail: body
        )
    }

    private static func extractTag(_ tag: String, from text: String) -> String? {
        guard let openRange = text.range(of: "<\(tag)") else { return nil }
        guard let openEnd = text[openRange.upperBound...].firstIndex(of: ">") else { return nil }
        guard let closeRange = text.range(of: "</\(tag)>", range: openEnd..<text.endIndex) else { return nil }
        return String(text[text.index(after: openEnd)..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripOuterTag(_ tag: String, from text: String) -> String? {
        guard let openRange = text.range(of: "<\(tag)") else { return nil }
        guard let openEnd = text[openRange.upperBound...].firstIndex(of: ">") else { return nil }
        guard let closeRange = text.range(of: "</\(tag)>", range: openEnd..<text.endIndex) else { return nil }
        return String(text[text.index(after: openEnd)..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAttribute(_ name: String, from text: String) -> String? {
        guard let tagEnd = text.firstIndex(of: ">") else { return nil }
        let openingTag = String(text[..<tagEnd])
        let pattern = #"\#(name)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(openingTag.startIndex..<openingTag.endIndex, in: openingTag)
        guard let match = regex.firstMatch(in: openingTag, range: nsRange),
              let range = Range(match.range(at: 1), in: openingTag) else {
            return nil
        }
        return String(openingTag[range])
    }

    private static func extractBracketValue(named name: String, from text: String) -> String? {
        guard let prefixRange = text.range(of: "\(name)=[" ) else { return nil }
        let start = prefixRange.upperBound
        guard let end = text[start...].firstIndex(of: "]") else { return nil }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripXMLTags(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstUsefulLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func truncate(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(max(0, limit - 1))) + "…"
    }
}
