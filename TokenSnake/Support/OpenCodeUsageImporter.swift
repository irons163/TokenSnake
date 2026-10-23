import Foundation
import CoreFoundation
import SQLite3

nonisolated enum OpenCodeUsageImporter {
    static let databaseName = "opencode.db"
    // OpenCode updates an assistant message while it streams. Re-reading a short
    // window keeps the final counters even when the cursor already passed them.
    static let overlapMilliseconds: Int64 = 15 * 60 * 1_000
    static let maximumRows = 20_000
    static let maximumMessageBytes = 16 * 1_024 * 1_024
    static let costImportVersion = 1

    struct Scan {
        var entries: [TokenEntry] = []
        var checkpoint: OpenCodeCheckpoint
        var bytesRead: UInt64 = 0
        var skippedRecords = 0
    }

    enum ScanError: Error {
        case unreadableDatabase
    }

    static func databaseURL(in directory: URL) -> URL {
        directory.appending(path: databaseName, directoryHint: .notDirectory)
    }

    static func scan(directory: URL, checkpoint previous: OpenCodeCheckpoint?) throws -> Scan {
        let database = databaseURL(in: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: database.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileID = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        var checkpoint = previous ?? OpenCodeCheckpoint()
        // Earlier versions skipped OpenCode's cost field. Backfill old messages
        // once without clearing hidden entries or changing their import identities.
        if checkpoint.databaseID != fileID || size < checkpoint.size
            || checkpoint.costImportVersion != costImportVersion {
            checkpoint = OpenCodeCheckpoint()
        }
        checkpoint.costImportVersion = costImportVersion
        checkpoint.databaseID = fileID
        checkpoint.size = size
        var scan = Scan(checkpoint: checkpoint)

        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw ScanError.unreadableDatabase
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 500)

        // CASE guards json_extract so one malformed message cannot fail the scan.
        let query = """
            SELECT id, data, time_created, time_updated FROM message
            WHERE time_updated > ?
              AND CASE WHEN json_valid(data) THEN json_extract(data, '$.role') END = 'assistant'
            ORDER BY time_updated ASC LIMIT \(maximumRows)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ScanError.unreadableDatabase
        }
        defer { sqlite3_finalize(statement) }

        let lowerBound = max(0, checkpoint.updatedThrough - overlapMilliseconds)
        sqlite3_bind_int64(statement, 1, lowerBound)
        while true {
            try Task.checkCancellation()
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw ScanError.unreadableDatabase }

            let updatedAt = sqlite3_column_int64(statement, 3)
            if updatedAt > checkpoint.updatedThrough { checkpoint.updatedThrough = updatedAt }
            let byteCount = sqlite3_column_bytes(statement, 1)
            if byteCount > 0 { scan.bytesRead += UInt64(byteCount) }

            guard let identifier = text(statement, 0), !identifier.isEmpty,
                  byteCount <= maximumMessageBytes,
                  let data = data(statement, 1) else {
                scan.skippedRecords += 1
                continue
            }
            do {
                if let entry = try OpenCodeMessageParser.entry(
                    messageID: identifier, data: data, createdAt: sqlite3_column_int64(statement, 2)
                ) {
                    scan.entries.append(entry)
                }
            } catch {
                scan.skippedRecords += 1
            }
        }
        scan.checkpoint = checkpoint
        return scan
    }

    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private static func data(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }
}

nonisolated enum OpenCodeMessageParser {
    static func entry(messageID: String, data: Data, createdAt: Int64) throws -> TokenEntry? {
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["role"] as? String == "assistant",
              let tokens = record["tokens"] as? [String: Any],
              let date = date(fromMilliseconds: createdAt) else { return nil }
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let read = try UsageLogParser.count(cache, "read")
        let write = try UsageLogParser.count(cache, "write")
        let usage = UsageCounters(
            input: try UsageLogParser.count(tokens, "input") + read + write,
            cached: read,
            write: write,
            output: try UsageLogParser.count(tokens, "output") + UsageLogParser.count(tokens, "reasoning")
        )
        let model = record["modelID"] as? String ?? ""
        let provider = provider(for: record["providerID"] as? String ?? "", model: model)
        guard var entry = UsageLogParser.entry(key: "opencode:\(messageID)", source: .opencode, model: model,
                                               date: date, usage: usage, provider: provider) else { return nil }
        // This is OpenCode's USD estimate for the selected gateway/model, not a
        // provider invoice. Preserve explicit zero; missing/invalid costs stay nil.
        if let number = record["cost"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue.isFinite, (0...1_000_000_000_000).contains(number.doubleValue) {
            entry.reportedCost = number.doubleValue
        }
        return entry
    }

    static func provider(for identifier: String, model: String) -> AIProvider {
        switch identifier.lowercased() {
        case "openai": return .openai
        case "anthropic": return .anthropic
        case "google", "google-vertex", "google-vertex-ai": return .google
        case "xai": return .xai
        default: return inferredProvider(for: model)
        }
    }

    private static func inferredProvider(for model: String) -> AIProvider {
        let name = model.lowercased()
        if name.hasPrefix("claude") { return .anthropic }
        if name.hasPrefix("gpt") || name.hasPrefix("chatgpt") || name.hasPrefix("codex")
            || name.hasPrefix("o1") || name.hasPrefix("o3") || name.hasPrefix("o4") {
            return .openai
        }
        if name.hasPrefix("gemini") { return .google }
        if name.hasPrefix("grok") { return .xai }
        return .custom
    }

    private static func date(fromMilliseconds value: Int64) -> Date? {
        guard value >= 0 else { return nil }
        let seconds = Double(value) / 1_000
        guard seconds.isFinite, seconds <= Date.distantFuture.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
