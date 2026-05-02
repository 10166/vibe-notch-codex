//
//  CodexConversationParser.swift
//  ClaudeIsland
//
//  Parses Codex CLI JSONL session files into the existing chat models.
//

import Foundation
import os.log

actor CodexConversationParser {
    static let shared = CodexConversationParser()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "CodexParser")

    enum TurnStatus: Sendable {
        case unknown
        case running
        case complete
    }

    private var incrementalState: [String: IncrementalParseState] = [:]

    private struct IncrementalParseState {
        var lastFileOffset: UInt64 = 0
        var messages: [ChatMessage] = []
        var seenToolIds: Set<String> = []
        var toolIdToName: [String: String] = [:]
        var completedToolIds: Set<String> = []
        var toolResults: [String: ConversationParser.ToolResult] = [:]
        var structuredResults: [String: ToolResultData] = [:]
    }

    func parse(sessionFile: String) -> ConversationInfo {
        guard let content = try? String(contentsOfFile: sessionFile, encoding: .utf8) else {
            return Self.emptyInfo()
        }

        var firstUserMessage: String?
        var lastMessage: String?
        var lastMessageRole: String?
        var lastToolName: String?
        var lastUserMessageDate: Date?
        var usage = UsageInfo()

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            guard let json = Self.parseJSON(line) else { continue }

            if let tokenUsage = Self.parseTokenUsage(json) {
                usage = tokenUsage
            }

            guard let codexMessage = Self.parseCodexMessage(json) else { continue }

            if firstUserMessage == nil,
               codexMessage.role == .user,
               let text = codexMessage.text {
                firstUserMessage = Self.truncateMessage(text, maxLength: 50)
            }

            if codexMessage.role == .user {
                lastUserMessageDate = codexMessage.timestamp
            }

            if let text = codexMessage.text {
                lastMessage = text
                lastMessageRole = codexMessage.role.rawValue
                lastToolName = nil
            } else if let tool = codexMessage.tool {
                lastMessage = tool.preview
                lastMessageRole = "tool"
                lastToolName = tool.name
            }
        }

        return ConversationInfo(
            summary: nil,
            lastMessage: Self.truncateMessage(lastMessage, maxLength: 80),
            lastMessageRole: lastMessageRole,
            lastToolName: lastToolName,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate,
            usage: usage
        )
    }

    func latestTurnStatus(sessionFile: String) -> TurnStatus {
        guard let content = try? String(contentsOfFile: sessionFile, encoding: .utf8) else {
            return .unknown
        }

        var status: TurnStatus = .unknown
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard let json = Self.parseJSON(line),
                  json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String else {
                continue
            }

            switch payloadType {
            case "task_started":
                status = .running
            case "task_complete":
                status = .complete
            default:
                continue
            }
        }
        return status
    }

    func parseFullConversation(sessionId: String, sessionFile: String) -> [ChatMessage] {
        var state = IncrementalParseState()
        _ = parseNewLines(filePath: sessionFile, state: &state)
        incrementalState[sessionId] = state
        return state.messages
    }

    func parseIncremental(sessionId: String, sessionFile: String) -> ConversationParser.IncrementalParseResult {
        guard FileManager.default.fileExists(atPath: sessionFile) else {
            return ConversationParser.IncrementalParseResult(
                newMessages: [],
                allMessages: [],
                completedToolIds: [],
                toolResults: [:],
                structuredResults: [:],
                clearDetected: false
            )
        }

        var state = incrementalState[sessionId] ?? IncrementalParseState()
        let newMessages = parseNewLines(filePath: sessionFile, state: &state)
        incrementalState[sessionId] = state

        return ConversationParser.IncrementalParseResult(
            newMessages: newMessages,
            allMessages: state.messages,
            completedToolIds: state.completedToolIds,
            toolResults: state.toolResults,
            structuredResults: state.structuredResults,
            clearDetected: false
        )
    }

    func completedToolIds(for sessionId: String) -> Set<String> {
        incrementalState[sessionId]?.completedToolIds ?? []
    }

    func toolResults(for sessionId: String) -> [String: ConversationParser.ToolResult] {
        incrementalState[sessionId]?.toolResults ?? [:]
    }

    func structuredResults(for sessionId: String) -> [String: ToolResultData] {
        incrementalState[sessionId]?.structuredResults ?? [:]
    }

    private func parseNewLines(filePath: String, state: inout IncrementalParseState) -> [ChatMessage] {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return []
        }
        defer { try? fileHandle.close() }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        if fileSize < state.lastFileOffset {
            state = IncrementalParseState()
        }
        if fileSize == state.lastFileOffset {
            return []
        }

        try? fileHandle.seek(toOffset: state.lastFileOffset)
        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return []
        }

        var newMessages: [ChatMessage] = []
        for line in newContent.components(separatedBy: "\n") where !line.isEmpty {
            guard let json = Self.parseJSON(line) else { continue }

            if let output = Self.parseExecCommandEnd(json) {
                state.completedToolIds.insert(output.id)
                state.toolResults[output.id] = ConversationParser.ToolResult(
                    content: output.content,
                    stdout: nil,
                    stderr: nil,
                    isError: output.isError
                )
                state.structuredResults[output.id] = .generic(GenericResult(
                    rawContent: output.content,
                    rawData: ["content": output.content, "isError": output.isError]
                ))
                continue
            }

            if let output = Self.parseFunctionOutput(json) {
                if state.toolIdToName[output.id] == "exec_command" {
                    continue
                }
                state.completedToolIds.insert(output.id)
                state.toolResults[output.id] = ConversationParser.ToolResult(
                    content: output.content,
                    stdout: nil,
                    stderr: nil,
                    isError: output.isError
                )
                state.structuredResults[output.id] = .generic(GenericResult(
                    rawContent: output.content,
                    rawData: ["content": output.content, "isError": output.isError]
                ))
                continue
            }

            guard let codexMessage = Self.parseCodexMessage(json) else { continue }

            if let tool = codexMessage.tool {
                state.toolIdToName[tool.id] = tool.name
                if state.seenToolIds.contains(tool.id) {
                    continue
                }
                state.seenToolIds.insert(tool.id)
            }

            let message = ChatMessage(
                id: codexMessage.id,
                role: codexMessage.role,
                timestamp: codexMessage.timestamp,
                content: codexMessage.blocks
            )
            newMessages.append(message)
            state.messages.append(message)
        }

        state.lastFileOffset = fileSize
        return newMessages
    }

    private struct ParsedCodexMessage {
        let id: String
        let role: ChatRole
        let timestamp: Date
        let blocks: [MessageBlock]
        let text: String?
        let tool: ToolUseBlock?
    }

    private struct ParsedFunctionOutput {
        let id: String
        let content: String
        let isError: Bool
    }

    private static func parseExecCommandEnd(_ json: [String: Any]) -> ParsedFunctionOutput? {
        guard json["type"] as? String == "event_msg",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "exec_command_end",
              let callId = payload["call_id"] as? String else {
            return nil
        }

        let content = payload["aggregated_output"] as? String ??
            payload["stdout"] as? String ??
            payload["stderr"] as? String ??
            ""
        let status = payload["status"] as? String
        let exitCode = payload["exit_code"] as? Int
        return ParsedFunctionOutput(
            id: callId,
            content: content,
            isError: status == "failed" || (exitCode != nil && exitCode != 0)
        )
    }

    private static func parseCodexMessage(_ json: [String: Any]) -> ParsedCodexMessage? {
        guard json["type"] as? String == "response_item",
              let payload = json["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String else {
            return nil
        }

        let timestamp = parseTimestamp(json["timestamp"] as? String)

        if payloadType == "message" {
            guard let roleString = payload["role"] as? String,
                  let role = chatRole(from: roleString),
                  let text = textContent(from: payload),
                  !shouldSkipText(text) else {
                return nil
            }

            return ParsedCodexMessage(
                id: stableId(prefix: "codex-message", json: json),
                role: role,
                timestamp: timestamp,
                blocks: [.text(text)],
                text: text,
                tool: nil
            )
        }

        if payloadType == "function_call" {
            guard let callId = payload["call_id"] as? String else { return nil }
            let name = payload["name"] as? String ?? "tool"
            let arguments = payload["arguments"] as? String ?? ""
            let input = parseArguments(arguments)
            let tool = ToolUseBlock(
                id: callId,
                name: name,
                input: input
            )

            return ParsedCodexMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                blocks: [.toolUse(tool)],
                text: nil,
                tool: tool
            )
        }

        return nil
    }

    private static func parseArguments(_ arguments: String) -> [String: String] {
        guard !arguments.isEmpty,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments.isEmpty ? [:] : ["arguments": arguments]
        }

        var input: [String: String] = [:]
        for (key, value) in object {
            input[key] = stringifyArgumentValue(value)
        }
        return input
    }

    private static func stringifyArgumentValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func parseFunctionOutput(_ json: [String: Any]) -> ParsedFunctionOutput? {
        guard json["type"] as? String == "response_item",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "function_call_output",
              let callId = payload["call_id"] as? String else {
            return nil
        }

        let output = payload["output"] as? String ?? payload["content"] as? String ?? ""
        let status = payload["status"] as? String
        return ParsedFunctionOutput(
            id: callId,
            content: output,
            isError: status == "failed" || output.localizedCaseInsensitiveContains("error")
        )
    }

    private static func parseTokenUsage(_ json: [String: Any]) -> UsageInfo? {
        guard json["type"] as? String == "event_msg",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else {
            return nil
        }

        return UsageInfo(
            inputTokens: total["input_tokens"] as? Int ?? 0,
            outputTokens: total["output_tokens"] as? Int ?? 0,
            cacheReadTokens: total["cached_input_tokens"] as? Int ?? 0,
            cacheCreationTokens: 0
        )
    }

    private static func parseJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func textContent(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else { return nil }

        let parts = content.compactMap { block -> String? in
            guard let type = block["type"] as? String,
                  type == "input_text" || type == "output_text" else {
                return nil
            }
            return block["text"] as? String
        }

        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func shouldSkipText(_ text: String) -> Bool {
        text.hasPrefix("<environment_context>") ||
        text.hasPrefix("<permissions instructions>") ||
        text.hasPrefix("Continue working toward the active thread goal.")
    }

    private static func chatRole(from role: String) -> ChatRole? {
        switch role {
        case "user": return .user
        case "assistant": return .assistant
        default: return nil
        }
    }

    private static func parseTimestamp(_ timestamp: String?) -> Date {
        guard let timestamp else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? Date()
    }

    private static func stableId(prefix: String, json: [String: Any]) -> String {
        let timestamp = json["timestamp"] as? String ?? ""
        let raw = "\(timestamp)-\(json)"
        return "\(prefix)-\(StableHash.hash(raw.prefix(200)))"
    }

    private static func truncateMessage(_ message: String?, maxLength: Int = 80) -> String? {
        guard let msg = message else { return nil }
        let cleaned = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength - 3)) + "..."
        }
        return cleaned
    }

    private static func emptyInfo() -> ConversationInfo {
        ConversationInfo(
            summary: nil,
            lastMessage: nil,
            lastMessageRole: nil,
            lastToolName: nil,
            firstUserMessage: nil,
            lastUserMessageDate: nil
        )
    }
}
