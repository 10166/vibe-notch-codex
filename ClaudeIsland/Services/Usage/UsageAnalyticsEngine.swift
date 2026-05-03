//
//  UsageAnalyticsEngine.swift
//  ClaudeIsland
//
//  Scans local Claude Code and Codex CLI JSONL logs into a small SQLite cache.
//

import Foundation
import CryptoKit
import SQLite3

nonisolated private let usageParserVersion = 5
nonisolated private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor UsageAnalyticsEngine {
    static let shared = UsageAnalyticsEngine()

    private let calendar = Calendar.current

    private struct ScanResult {
        var scannedCount: Int
        var seenPathHashes: Set<String>
    }

    func refresh(range: UsageAnalyticsRange, claudeProjectsDir: URL, codexSessionsDir: URL) async -> UsageAnalyticsSnapshot {
        guard let db = openDatabase() else {
            return .empty
        }
        defer { sqlite3_close(db) }

        ensureSchema(db)

        let claudeResult = scanFiles(in: claudeProjectsDir, agent: .claude, db: db)
        let codexResult = scanFiles(in: codexSessionsDir, agent: .codex, db: db)
        pruneMissingSessions(agent: .claude, seenPathHashes: claudeResult.seenPathHashes, db: db)
        pruneMissingSessions(agent: .codex, seenPathHashes: codexResult.seenPathHashes, db: db)
        rebuildDailyTable(db)

        let days = loadDays(range: range, db: db)
        let sessions = loadSessions(range: range, db: db)
        return UsageAnalyticsSnapshot(
            generatedAt: Date(),
            days: days,
            sessions: sessions,
            scannedFileCount: claudeResult.scannedCount + codexResult.scannedCount
        )
    }

    private func openDatabase() -> OpaquePointer? {
        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Vibe Notch", isDirectory: true)
        guard let supportDir else { return nil }

        do {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let dbURL = supportDir.appendingPathComponent("usage.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            return nil
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        return db
    }

    private func ensureSchema(_ db: OpaquePointer?) {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS usage_file_index (
                path_hash TEXT PRIMARY KEY,
                source_path TEXT NOT NULL,
                mtime REAL NOT NULL,
                size INTEGER NOT NULL,
                parser_version INTEGER NOT NULL,
                last_scanned_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS usage_sessions (
                session_id TEXT NOT NULL,
                file_path_hash TEXT NOT NULL,
                agent TEXT NOT NULL,
                project_name TEXT NOT NULL,
                cwd_hash TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                local_date TEXT NOT NULL,
                model TEXT,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL,
                session_count INTEGER NOT NULL,
                estimated_cost_micros INTEGER,
                is_sidechain INTEGER NOT NULL,
                PRIMARY KEY (session_id, file_path_hash)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS usage_daily (
                local_date TEXT NOT NULL,
                agent TEXT NOT NULL,
                project_name TEXT NOT NULL,
                model TEXT,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL,
                session_count INTEGER NOT NULL,
                estimated_cost_micros INTEGER,
                PRIMARY KEY (local_date, agent, project_name, model)
            )
            """
        ]

        for statement in statements {
            sqlite3_exec(db, statement, nil, nil, nil)
        }
        sqlite3_exec(db, "UPDATE usage_file_index SET source_path = path_hash WHERE source_path LIKE '/%'", nil, nil, nil)
    }

    private func scanFiles(in root: URL, agent: UsageAnalyticsAgent, db: OpaquePointer?) -> ScanResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return ScanResult(scannedCount: 0, seenPathHashes: [])
        }

        var scannedCount = 0
        var seenPathHashes: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = values.contentModificationDate else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let pathHash = UsageHash.hash(url.path)
            seenPathHashes.insert(pathHash)
            let mtime = modDate.timeIntervalSince1970
            guard shouldScan(pathHash: pathHash, mtime: mtime, size: size, db: db) else {
                continue
            }

            deleteSessions(filePathHash: pathHash, db: db)
            let record: UsageSessionRecord?
            switch agent {
            case .claude:
                record = UsageLogParser.parseClaudeFile(url: url, pathHash: pathHash)
            case .codex:
                record = UsageLogParser.parseCodexFile(url: url, pathHash: pathHash)
            }

            if let record {
                upsertSession(record, filePathHash: pathHash, db: db)
            }
            upsertFileIndex(pathHash: pathHash, mtime: mtime, size: size, db: db)
            scannedCount += 1
        }
        return ScanResult(scannedCount: scannedCount, seenPathHashes: seenPathHashes)
    }

    private func shouldScan(pathHash: String, mtime: TimeInterval, size: Int64, db: OpaquePointer?) -> Bool {
        let sql = "SELECT mtime, size, parser_version FROM usage_file_index WHERE path_hash = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, pathHash)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return true
        }

        let storedMtime = sqlite3_column_double(statement, 0)
        let storedSize = sqlite3_column_int64(statement, 1)
        let storedVersion = sqlite3_column_int(statement, 2)
        return storedMtime != mtime || storedSize != size || storedVersion != usageParserVersion
    }

    private func upsertFileIndex(pathHash: String, mtime: TimeInterval, size: Int64, db: OpaquePointer?) {
        let sql = """
        INSERT OR REPLACE INTO usage_file_index
        (path_hash, source_path, mtime, size, parser_version, last_scanned_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        withStatement(db, sql) { statement in
            bindText(statement, 1, pathHash)
            bindText(statement, 2, pathHash)
            sqlite3_bind_double(statement, 3, mtime)
            sqlite3_bind_int64(statement, 4, size)
            sqlite3_bind_int(statement, 5, Int32(usageParserVersion))
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
            sqlite3_step(statement)
        }
    }

    private func deleteSessions(filePathHash: String, db: OpaquePointer?) {
        withStatement(db, "DELETE FROM usage_sessions WHERE file_path_hash = ?") { statement in
            bindText(statement, 1, filePathHash)
            sqlite3_step(statement)
        }
    }

    private func pruneMissingSessions(agent: UsageAnalyticsAgent, seenPathHashes: Set<String>, db: OpaquePointer?) {
        guard !seenPathHashes.isEmpty else { return }
        let sql = "SELECT DISTINCT file_path_hash FROM usage_sessions WHERE agent = ?"
        var storedHashes: [String] = []
        withStatement(db, sql) { statement in
            bindText(statement, 1, agent.rawValue)
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathHash = columnText(statement, 0) {
                    storedHashes.append(pathHash)
                }
            }
        }

        for pathHash in storedHashes where !seenPathHashes.contains(pathHash) {
            deleteSessions(filePathHash: pathHash, db: db)
        }
    }

    private func upsertSession(_ record: UsageSessionRecord, filePathHash: String, db: OpaquePointer?) {
        let sql = """
        INSERT OR REPLACE INTO usage_sessions
        (session_id, file_path_hash, agent, project_name, cwd_hash, started_at, ended_at, local_date,
         model, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, session_count,
         estimated_cost_micros, is_sidechain)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        withStatement(db, sql) { statement in
            bindText(statement, 1, record.sessionId)
            bindText(statement, 2, filePathHash)
            bindText(statement, 3, record.agent.rawValue)
            bindText(statement, 4, record.projectName)
            bindText(statement, 5, record.cwdHash)
            sqlite3_bind_double(statement, 6, record.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, record.endedAt.timeIntervalSince1970)
            bindText(statement, 8, record.localDate)
            bindOptionalText(statement, 9, record.model)
            sqlite3_bind_int64(statement, 10, record.tokens.inputTokens)
            sqlite3_bind_int64(statement, 11, record.tokens.outputTokens)
            sqlite3_bind_int64(statement, 12, record.tokens.cacheReadTokens)
            sqlite3_bind_int64(statement, 13, record.tokens.cacheCreationTokens)
            sqlite3_bind_int(statement, 14, 1)
            bindOptionalInt64(statement, 15, record.estimatedCostMicros)
            sqlite3_bind_int(statement, 16, record.isSidechain ? 1 : 0)
            sqlite3_step(statement)
        }
    }

    private func rebuildDailyTable(_ db: OpaquePointer?) {
        sqlite3_exec(db, "DELETE FROM usage_daily", nil, nil, nil)
        let sql = """
        INSERT INTO usage_daily
        (local_date, agent, project_name, model, input_tokens, output_tokens, cache_read_tokens,
         cache_creation_tokens, session_count, estimated_cost_micros)
        SELECT local_date, agent, project_name, model,
               SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
               SUM(cache_creation_tokens), SUM(session_count), SUM(estimated_cost_micros)
        FROM usage_sessions
        GROUP BY local_date, agent, project_name, model
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func loadDays(range: UsageAnalyticsRange, db: OpaquePointer?) -> [UsageDayBucket] {
        let startDate = calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(-(range.dayCount - 1) * 24 * 60 * 60))
        let startKey = UsageLogParser.localDateString(for: startDate)
        var bucketsByDate: [String: UsageDayBucket] = [:]

        let sql = """
        SELECT local_date, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
               SUM(cache_creation_tokens), SUM(estimated_cost_micros), SUM(session_count)
        FROM usage_daily
        WHERE local_date >= ?
        GROUP BY local_date
        """
        withStatement(db, sql) { statement in
            bindText(statement, 1, startKey)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let localDate = columnText(statement, 0),
                      let date = UsageLogParser.date(fromLocalDate: localDate) else {
                    continue
                }
                bucketsByDate[localDate] = UsageDayBucket(
                    localDate: localDate,
                    date: date,
                    inputTokens: sqlite3_column_int64(statement, 1),
                    outputTokens: sqlite3_column_int64(statement, 2),
                    cacheReadTokens: sqlite3_column_int64(statement, 3),
                    cacheCreationTokens: sqlite3_column_int64(statement, 4),
                    estimatedCostMicros: optionalColumnInt64(statement, 5),
                    sessionCount: Int(sqlite3_column_int(statement, 6))
                )
            }
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            let key = UsageLogParser.localDateString(for: date)
            return bucketsByDate[key] ?? UsageDayBucket(
                localDate: key,
                date: date,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                estimatedCostMicros: nil,
                sessionCount: 0
            )
        }
    }

    private func loadSessions(range: UsageAnalyticsRange, db: OpaquePointer?) -> [UsageSessionRecord] {
        let startDate = calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(-(range.dayCount - 1) * 24 * 60 * 60))
        let startKey = UsageLogParser.localDateString(for: startDate)
        var sessions: [UsageSessionRecord] = []

        let sql = """
        SELECT session_id, file_path_hash, agent, project_name, cwd_hash, started_at, ended_at, local_date,
               model, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
               estimated_cost_micros, is_sidechain
        FROM usage_sessions
        WHERE local_date >= ?
        ORDER BY ended_at DESC
        """
        withStatement(db, sql) { statement in
            bindText(statement, 1, startKey)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let sessionId = columnText(statement, 0),
                      let filePathHash = columnText(statement, 1),
                      let agentRaw = columnText(statement, 2),
                      let agent = UsageAnalyticsAgent(rawValue: agentRaw),
                      let projectName = columnText(statement, 3),
                      let cwdHash = columnText(statement, 4),
                      let localDate = columnText(statement, 7) else {
                    continue
                }

                sessions.append(UsageSessionRecord(
                    id: "\(sessionId)-\(filePathHash)",
                    sessionId: sessionId,
                    agent: agent,
                    projectName: projectName,
                    cwdHash: cwdHash,
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    localDate: localDate,
                    model: columnText(statement, 8),
                    tokens: UsageTokenBreakdown(
                        inputTokens: sqlite3_column_int64(statement, 9),
                        outputTokens: sqlite3_column_int64(statement, 10),
                        cacheReadTokens: sqlite3_column_int64(statement, 11),
                        cacheCreationTokens: sqlite3_column_int64(statement, 12)
                    ),
                    estimatedCostMicros: optionalColumnInt64(statement, 13),
                    isSidechain: sqlite3_column_int(statement, 14) == 1
                ))
            }
        }
        return sessions
    }
}

nonisolated private enum UsageLogParser {
    static func parseClaudeFile(url: URL, pathHash: String) -> UsageSessionRecord? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var model: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var tokens = UsageTokenBreakdown()
        var isSidechain = false

        for line in content.split(separator: "\n") {
            guard let json = parseJSON(String(line)) else { continue }

            if let timestamp = parseTimestamp(json["timestamp"] as? String) {
                if firstTimestamp == nil { firstTimestamp = timestamp }
                lastTimestamp = timestamp
            }
            if let value = json["sessionId"] as? String { sessionId = value }
            if let value = json["cwd"] as? String { cwd = value }
            if json["isSidechain"] as? Bool == true { isSidechain = true }

            guard json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }

            model = (message["model"] as? String) ?? model
            tokens.inputTokens += Int64(usage["input_tokens"] as? Int ?? 0)
            tokens.outputTokens += Int64(usage["output_tokens"] as? Int ?? 0)
            tokens.cacheReadTokens += Int64(usage["cache_read_input_tokens"] as? Int ?? 0)
            tokens.cacheCreationTokens += Int64(usage["cache_creation_input_tokens"] as? Int ?? 0)
        }

        guard let startedAt = firstTimestamp ?? fileDate(url),
              let endedAt = lastTimestamp ?? firstTimestamp ?? fileDate(url) else {
            return nil
        }

        let resolvedCwd = resolvedClaudeCwd(cwd: cwd, isSidechain: isSidechain, sessionId: sessionId, url: url)
        let projectName = UsageProjectAttribution.projectName(
            from: resolvedCwd,
            fallback: url.deletingLastPathComponent().lastPathComponent
        )
        return UsageSessionRecord(
            id: "\(sessionId)-\(pathHash)",
            sessionId: sessionId,
            agent: .claude,
            projectName: projectName,
            cwdHash: UsageHash.hash(resolvedCwd ?? projectName),
            startedAt: startedAt,
            endedAt: endedAt,
            localDate: localDateString(for: endedAt),
            model: model,
            tokens: tokens,
            estimatedCostMicros: PricingCatalog.estimateMicros(model: model, tokens: tokens),
            isSidechain: isSidechain
        )
    }

    static func parseCodexFile(url: URL, pathHash: String) -> UsageSessionRecord? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var model: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var tokens = UsageTokenBreakdown()
        var sawSessionMeta = false

        for line in content.split(separator: "\n") {
            guard let json = parseJSON(String(line)) else { continue }
            if let timestamp = parseTimestamp(json["timestamp"] as? String) {
                if firstTimestamp == nil { firstTimestamp = timestamp }
                lastTimestamp = timestamp
            }

            if json["type"] as? String == "session_meta",
               let payload = json["payload"] as? [String: Any] {
                sawSessionMeta = true
                sessionId = payload["id"] as? String ?? sessionId
                cwd = payload["cwd"] as? String ?? cwd
            }

            if json["type"] as? String == "turn_context",
               let payload = json["payload"] as? [String: Any] {
                model = payload["model"] as? String ?? model
                cwd = payload["cwd"] as? String ?? cwd
            }

            if json["type"] as? String == "event_msg",
               let payload = json["payload"] as? [String: Any],
               payload["type"] as? String == "token_count",
               let info = payload["info"] as? [String: Any],
               let total = info["total_token_usage"] as? [String: Any] {
                let totalInputTokens = Int64(total["input_tokens"] as? Int ?? 0)
                let cachedInputTokens = Int64(total["cached_input_tokens"] as? Int ?? 0)
                tokens = UsageTokenBreakdown(
                    inputTokens: max(0, totalInputTokens - cachedInputTokens),
                    outputTokens: Int64(total["output_tokens"] as? Int ?? 0),
                    cacheReadTokens: cachedInputTokens,
                    cacheCreationTokens: 0
                )
            }
        }

        guard sawSessionMeta,
              let startedAt = firstTimestamp ?? fileDate(url),
              let endedAt = lastTimestamp ?? firstTimestamp ?? fileDate(url) else {
            return nil
        }

        let projectName = UsageProjectAttribution.projectName(from: cwd, fallback: url.deletingLastPathComponent().lastPathComponent)
        return UsageSessionRecord(
            id: "\(sessionId)-\(pathHash)",
            sessionId: sessionId,
            agent: .codex,
            projectName: projectName,
            cwdHash: UsageHash.hash(cwd ?? projectName),
            startedAt: startedAt,
            endedAt: endedAt,
            localDate: localDateString(for: endedAt),
            model: model,
            tokens: tokens,
            estimatedCostMicros: PricingCatalog.estimateMicros(model: model, tokens: tokens),
            isSidechain: false
        )
    }

    private static func resolvedClaudeCwd(cwd: String?, isSidechain: Bool, sessionId: String, url: URL) -> String? {
        let canonical = UsageProjectAttribution.canonicalCwd(cwd)
        let parentCwd = isSidechain && canonical == nil
            ? parentSessionCwd(forSubagentURL: url, sessionId: sessionId)
            : nil
        return UsageProjectAttribution.resolvedClaudeCwd(cwd: cwd, isSidechain: isSidechain, parentCwd: parentCwd)
    }

    private static func parentSessionCwd(forSubagentURL url: URL, sessionId: String) -> String? {
        guard url.deletingLastPathComponent().lastPathComponent == "subagents" else {
            return nil
        }

        let sessionDir = url.deletingLastPathComponent().deletingLastPathComponent()
        let projectDir = sessionDir.deletingLastPathComponent()
        let parentURL = projectDir.appendingPathComponent(sessionId).appendingPathExtension("jsonl")
        guard let content = try? String(contentsOf: parentURL, encoding: .utf8) else {
            return nil
        }

        for line in content.split(separator: "\n") {
            guard let json = parseJSON(String(line)),
                  let cwd = json["cwd"] as? String,
                  !cwd.isEmpty else {
                continue
            }
            return UsageProjectAttribution.canonicalCwd(cwd)
        }
        return nil
    }

    static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(fromLocalDate value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func parseJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func fileDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

nonisolated private enum PricingCatalog {
    private struct Rate {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double
        let cacheWritePerMillion: Double
    }

    static func estimateMicros(model: String?, tokens: UsageTokenBreakdown) -> Int64? {
        guard let rate = rate(for: model, tokens: tokens) else { return nil }
        let dollars =
            Double(tokens.inputTokens) / 1_000_000 * rate.inputPerMillion +
            Double(tokens.outputTokens) / 1_000_000 * rate.outputPerMillion +
            Double(tokens.cacheReadTokens) / 1_000_000 * rate.cacheReadPerMillion +
            Double(tokens.cacheCreationTokens) / 1_000_000 * rate.cacheWritePerMillion
        return Int64((dollars * 1_000_000).rounded())
    }

    private static func rate(for model: String?, tokens: UsageTokenBreakdown) -> Rate? {
        guard let model = model?.lowercased() else { return nil }
        // USD per 1M tokens, aligned to public provider pricing pages.
        // CNY rates are converted with a source-checked USD/CNY rate from 2026-05-03.
        if let domesticRate = domesticRate(for: model, tokens: tokens) {
            return domesticRate
        }
        if model.contains("gpt-5.5-pro") {
            return Rate(inputPerMillion: 30.0, outputPerMillion: 180.0, cacheReadPerMillion: 0.0, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.5") {
            return Rate(inputPerMillion: 5.0, outputPerMillion: 30.0, cacheReadPerMillion: 0.5, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.4-pro") {
            return Rate(inputPerMillion: 30.0, outputPerMillion: 180.0, cacheReadPerMillion: 0.0, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.4-mini") {
            return Rate(inputPerMillion: 0.75, outputPerMillion: 4.5, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.4-nano") {
            return Rate(inputPerMillion: 0.2, outputPerMillion: 1.25, cacheReadPerMillion: 0.02, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.4") {
            return Rate(inputPerMillion: 2.5, outputPerMillion: 15.0, cacheReadPerMillion: 0.25, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.3-codex") || model.contains("gpt-5.3-chat") {
            return Rate(inputPerMillion: 1.75, outputPerMillion: 14.0, cacheReadPerMillion: 0.175, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.2") {
            return Rate(inputPerMillion: 1.75, outputPerMillion: 14.0, cacheReadPerMillion: 0.175, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5.1") {
            return Rate(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: 0.125, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5-mini") {
            return Rate(inputPerMillion: 0.25, outputPerMillion: 2.0, cacheReadPerMillion: 0.025, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5-nano") {
            return Rate(inputPerMillion: 0.05, outputPerMillion: 0.4, cacheReadPerMillion: 0.005, cacheWritePerMillion: 0.0)
        }
        if model.contains("gpt-5") {
            return Rate(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: 0.125, cacheWritePerMillion: 0.0)
        }
        if model.contains("opus") {
            if model.contains("4.7") || model.contains("4-7") ||
                model.contains("4.6") || model.contains("4-6") ||
                model.contains("4.5") || model.contains("4-5") {
                return Rate(inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.5, cacheWritePerMillion: 6.25)
            }
            return Rate(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5, cacheWritePerMillion: 18.75)
        }
        if model.contains("sonnet") {
            return Rate(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3, cacheWritePerMillion: 3.75)
        }
        if model.contains("haiku") {
            if model.contains("4.5") || model.contains("4-5") {
                return Rate(inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.1, cacheWritePerMillion: 1.25)
            }
            if model.contains("3.5") || model.contains("3-5") {
                return Rate(inputPerMillion: 0.8, outputPerMillion: 4.0, cacheReadPerMillion: 0.08, cacheWritePerMillion: 1.0)
            }
            return Rate(inputPerMillion: 0.25, outputPerMillion: 1.25, cacheReadPerMillion: 0.03, cacheWritePerMillion: 0.3)
        }
        return nil
    }

    private static func domesticRate(for model: String, tokens: UsageTokenBreakdown) -> Rate? {
        if model.contains("deepseek-reasoner") {
            return Rate(inputPerMillion: 0.55, outputPerMillion: 2.19, cacheReadPerMillion: 0.14, cacheWritePerMillion: 0.0)
        }
        if model.contains("deepseek-chat") || model.contains("deepseek-v3") {
            return Rate(inputPerMillion: 0.27, outputPerMillion: 1.10, cacheReadPerMillion: 0.07, cacheWritePerMillion: 0.0)
        }

        if model.contains("glm-5.1") {
            return Rate(inputPerMillion: 1.40, outputPerMillion: 4.40, cacheReadPerMillion: 0.26, cacheWritePerMillion: 0.0)
        }
        if model.contains("glm-5-turbo") {
            return Rate(inputPerMillion: 1.20, outputPerMillion: 4.00, cacheReadPerMillion: 0.24, cacheWritePerMillion: 0.0)
        }
        if model.contains("glm-5") {
            return Rate(inputPerMillion: 1.00, outputPerMillion: 3.20, cacheReadPerMillion: 0.20, cacheWritePerMillion: 0.0)
        }
        if model.contains("glm-4.7-flashx") || model.contains("glm-4-7-flashx") {
            return Rate(inputPerMillion: 0.07, outputPerMillion: 0.40, cacheReadPerMillion: 0.01, cacheWritePerMillion: 0.0)
        }
        if model.contains("glm-4.7") || model.contains("glm-4-7") ||
            model.contains("glm-4.6") || model.contains("glm-4-6") ||
            model.contains("glm-4.5") || model.contains("glm-4-5") {
            return Rate(inputPerMillion: 0.60, outputPerMillion: 2.20, cacheReadPerMillion: 0.11, cacheWritePerMillion: 0.0)
        }

        if model.contains("kimi-k2.6") || model.contains("kimi-k2-6") {
            return cnyRate(input: 6.50, output: 27.00, cacheRead: 1.10)
        }
        if model.contains("kimi-k2.5") || model.contains("kimi-k2-5") {
            return cnyRate(input: 4.00, output: 21.00, cacheRead: 0.70)
        }
        if model.contains("kimi-k2") {
            return cnyRate(input: 4.00, output: 16.00, cacheRead: 1.00)
        }

        if model.contains("minimax-m2.7-highspeed") || model.contains("minimax-m2-7-highspeed") ||
            model.contains("minimax-m2.5-highspeed") || model.contains("minimax-m2-5-highspeed") {
            return Rate(inputPerMillion: 0.60, outputPerMillion: 2.40, cacheReadPerMillion: 0.06, cacheWritePerMillion: 0.375)
        }
        if model.contains("minimax-m2.7") || model.contains("minimax-m2-7") {
            return Rate(inputPerMillion: 0.30, outputPerMillion: 1.20, cacheReadPerMillion: 0.06, cacheWritePerMillion: 0.375)
        }
        if model.contains("minimax-m2.5") || model.contains("minimax-m2-5") ||
            model.contains("minimax-m2.1") || model.contains("minimax-m2-1") ||
            model.contains("minimax-m2") {
            return Rate(inputPerMillion: 0.30, outputPerMillion: 1.20, cacheReadPerMillion: 0.03, cacheWritePerMillion: 0.375)
        }

        if model.contains("qwen3-max-2025") || model.contains("qwen3-max-preview") {
            return qwenTieredRate(tokens: tokens, tiers: [
                (32_000, 6.00, 24.00),
                (128_000, 10.00, 40.00),
                (252_000, 15.00, 60.00)
            ])
        }
        if model.contains("qwen3-max") {
            return qwenTieredRate(tokens: tokens, tiers: [
                (32_000, 2.50, 10.00),
                (128_000, 4.00, 16.00),
                (252_000, 7.00, 28.00)
            ])
        }
        if model.contains("qwen3.6-plus") || model.contains("qwen3-6-plus") {
            return qwenTieredRate(tokens: tokens, tiers: [
                (256_000, 2.00, 12.00),
                (1_000_000, 8.00, 48.00)
            ])
        }
        if model.contains("qwen3.5-plus") || model.contains("qwen3-5-plus") {
            return qwenTieredRate(tokens: tokens, tiers: [
                (128_000, 0.80, 4.80),
                (256_000, 2.00, 12.00),
                (1_000_000, 4.00, 24.00)
            ])
        }
        if model.contains("qwen-plus") {
            let thinking = model.contains("thinking")
            return qwenTieredRate(tokens: tokens, tiers: [
                (128_000, 0.80, thinking ? 8.00 : 2.00),
                (256_000, 2.40, thinking ? 24.00 : 20.00),
                (1_000_000, 4.80, thinking ? 64.00 : 48.00)
            ])
        }

        return nil
    }

    private static func qwenTieredRate(tokens: UsageTokenBreakdown, tiers: [(limit: Int64, input: Double, output: Double)]) -> Rate? {
        let billableInput = max(1, tokens.inputTokens + tokens.cacheReadTokens + tokens.cacheCreationTokens)
        let tier = tiers.first { billableInput <= $0.limit } ?? tiers.last
        guard let tier else { return nil }
        return cnyRate(input: tier.input, output: tier.output)
    }

    private static func cnyRate(input: Double, output: Double, cacheRead: Double? = nil, cacheWrite: Double = 0.0) -> Rate {
        let usdPerCny = 1.0 / 6.8265
        return Rate(
            inputPerMillion: input * usdPerCny,
            outputPerMillion: output * usdPerCny,
            cacheReadPerMillion: (cacheRead ?? input) * usdPerCny,
            cacheWritePerMillion: cacheWrite * usdPerCny
        )
    }
}

nonisolated private enum UsageHash {
    static func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.prefix(8).joined()
    }
}

nonisolated private func withStatement(_ db: OpaquePointer?, _ sql: String, _ body: (OpaquePointer?) -> Void) {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        return
    }
    defer { sqlite3_finalize(statement) }
    body(statement)
}

nonisolated private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
}

nonisolated private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    if let value {
        bindText(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

nonisolated private func bindOptionalInt64(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64?) {
    if let value {
        sqlite3_bind_int64(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

nonisolated private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: text)
}

nonisolated private func optionalColumnInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
}
