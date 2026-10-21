import CryptoKit
import Foundation
import SQLite3

/// Cursor stopped writing token counts to its local SQLite store, so the only
/// authoritative source left is the dashboard the web app itself uses. This
/// importer reads Cursor's own login token from disk and sends it to cursor.com
/// only while the user keeps the Cursor source switched on.
nonisolated enum CursorUsageImporter {
    static let databaseRelativePath = "User/globalStorage/state.vscdb"
    static let lookbackDays = 90
    static let overlapSeconds: TimeInterval = 24 * 60 * 60
    static let minimumFetchInterval: TimeInterval = 5 * 60
    static let pageSize = 100
    static let maximumPages = 200
    static let requestTimeout: TimeInterval = 10
    static let fetchDeadline: TimeInterval = 120

    typealias Transport = @Sendable (URLRequest) async -> (Data, Int)?

    enum Failure: Equatable {
        case missingDatabase
        case notSignedIn
        case unauthorized
        case network
        case invalidResponse
    }

    struct Scan {
        var entries: [TokenEntry] = []
        var checkpoint: CursorCheckpoint
        var bytesRead: UInt64 = 0
        var skippedRecords = 0
        var failure: Failure?
        var didFetch = false
        var throttled = false
    }

    private static let endpoint = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = fetchDeadline
        return URLSession(configuration: configuration)
    }()

    static func databaseURL(in cursorDirectory: URL) -> URL {
        cursorDirectory.appending(path: databaseRelativePath, directoryHint: .notDirectory)
    }

    static func scan(directory: URL, checkpoint previous: CursorCheckpoint?, force: Bool,
                     now: Date = .now, transport: Transport? = nil) async throws -> Scan {
        let database = databaseURL(in: directory)
        guard FileManager.default.fileExists(atPath: database.path) else {
            return Scan(checkpoint: previous ?? CursorCheckpoint(), failure: .missingDatabase)
        }
        guard let token = try? accessToken(database: database), !token.isEmpty else {
            return Scan(checkpoint: previous ?? CursorCheckpoint(), failure: .notSignedIn)
        }

        let accountID = accountIdentifier(for: token)
        var checkpoint = previous ?? CursorCheckpoint()
        if checkpoint.accountID != accountID {
            checkpoint = CursorCheckpoint(accountID: accountID)
        }
        checkpoint.accountID = accountID

        if !force, now.timeIntervalSince(checkpoint.lastAttemptAt) < minimumFetchInterval {
            var scan = Scan(checkpoint: checkpoint)
            scan.throttled = true
            return scan
        }

        let start = startDate(checkpoint: checkpoint, now: now)
        let send = transport ?? defaultTransport
        let result = try await fetch(token: token, modifiedSince: start, now: now, transport: send)
        switch result {
        case .success(let entries, let bytes, let skipped):
            checkpoint.fetchedAt = now
            checkpoint.lastAttemptAt = now
            return Scan(entries: deduplicated(entries), checkpoint: checkpoint,
                        bytesRead: bytes, skippedRecords: skipped, didFetch: true)
        case .failure(let failure):
            checkpoint.lastAttemptAt = now
            return Scan(checkpoint: checkpoint, failure: failure, didFetch: true)
        }
    }

    // MARK: - Fetching

    private enum FetchResult {
        case success([TokenEntry], UInt64, Int)
        case failure(Failure)
    }

    private static func fetch(token: String, modifiedSince: Date, now: Date,
                              transport: @escaping Transport) async throws -> FetchResult {
        let start = String(Int64((modifiedSince.timeIntervalSince1970 * 1_000).rounded()))
        let end = String(Int64((now.timeIntervalSince1970 * 1_000).rounded()))
        let deadline = Date().addingTimeInterval(fetchDeadline)
        var page = 1
        var collected: [TokenEntry] = []
        var bytes: UInt64 = 0
        var skipped = 0
        var authMode = AuthMode.cookie

        while page <= maximumPages {
            try Task.checkCancellation()
            guard Date() < deadline else { return .failure(.network) }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "teamId": 0,
                "startDate": start,
                "endDate": end,
                "page": page,
                "pageSize": pageSize
            ])
            request.timeoutInterval = requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard/usage", forHTTPHeaderField: "Referer")
            authMode.apply(to: &request, token: token)

            guard let (data, status) = await transport(request) else { return .failure(.network) }
            bytes += UInt64(data.count)
            if status == 401 || status == 403 {
                if let next = AuthMode(rawValue: authMode.rawValue + 1) {
                    authMode = next
                    continue
                }
                return .failure(.unauthorized)
            }
            guard (200...299).contains(status) else { return .failure(.network) }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.invalidResponse)
            }
            guard let events = eventList(from: object) else { return .failure(.invalidResponse) }

            for event in events {
                do {
                    if let entry = try entry(from: event, modifiedSince: modifiedSince, now: now) {
                        collected.append(entry)
                    }
                } catch {
                    skipped += 1
                }
            }

            let hasNext = hasNextPage(object: object, page: page, eventCount: events.count)
            if !hasNext {
                return .success(collected, bytes, skipped)
            }
            guard !events.isEmpty else { return .failure(.invalidResponse) }
            page += 1
        }
        return .failure(.network)
    }

    private static func defaultTransport(_ request: URLRequest) async -> (Data, Int)? {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return nil
        }
    }

    // MARK: - Parsing

    static func entry(from event: [String: Any], modifiedSince: Date, now: Date) throws -> TokenEntry? {
        guard let date = date(from: event), date >= modifiedSince,
              date <= now.addingTimeInterval(300) else { return nil }
        guard let raw = event["tokenUsage"] as? [String: Any] else { return nil }
        let read = try UsageLogParser.count(raw, "cacheReadTokens")
        let write = try UsageLogParser.count(raw, "cacheWriteTokens")
        let usage = UsageCounters(
            input: try UsageLogParser.count(raw, "inputTokens") + read + write,
            cached: read,
            write: write,
            output: try UsageLogParser.count(raw, "outputTokens")
        )
        guard usage.hasUsage else { return nil }
        let model = string(event["model"]) ?? ""
        let key = stableKey(event: event, model: model, usage: usage)
        guard var entry = UsageLogParser.entry(key: key, source: .cursor, model: model, date: date,
                                               usage: usage, provider: .cursor) else { return nil }
        if let cents = double(raw["totalCents"]), cents >= 0, cents.isFinite {
            entry.reportedCost = cents / 100
        }
        return entry
    }

    private static func stableKey(event: [String: Any], model: String, usage: UsageCounters) -> String {
        if let identifier = string(event["usageEventId"]) ?? string(event["id"])
            ?? string(event["eventId"]) ?? string(event["requestId"]), !identifier.isEmpty {
            return "cursor:\(identifier)"
        }
        let stamp = string(event["timestamp"]) ?? ""
        let seed = "\(stamp)|\(model)|\(usage.key)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "cursor:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func eventList(from object: [String: Any]) -> [[String: Any]]? {
        (object["usageEventsDisplay"] as? [[String: Any]])
            ?? (object["usageEvents"] as? [[String: Any]])
            ?? (object["events"] as? [[String: Any]])
    }

    private static func hasNextPage(object: [String: Any], page: Int, eventCount: Int) -> Bool {
        if let pagination = object["pagination"] as? [String: Any] {
            if let explicit = pagination["hasNextPage"] as? Bool { return explicit }
            if let pages = integer(pagination["numPages"]) { return page < pages }
        }
        if let total = integer(object["totalUsageEventsCount"]) { return page * pageSize < total }
        return eventCount >= pageSize
    }

    private static func deduplicated(_ entries: [TokenEntry]) -> [TokenEntry] {
        var map: [String: TokenEntry] = [:]
        for entry in entries {
            guard let key = entry.importID, var existing = map[key] else {
                if let key = entry.importID { map[key] = entry }
                continue
            }
            existing.inputTokens = max(existing.inputTokens, entry.inputTokens)
            existing.outputTokens = max(existing.outputTokens, entry.outputTokens)
            existing.cachedTokens = max(existing.cachedTokens, entry.cachedTokens)
            existing.cacheWriteTokens = max(existing.cacheWriteTokens ?? 0, entry.cacheWriteTokens ?? 0)
            if let cost = entry.reportedCost { existing.reportedCost = max(existing.reportedCost ?? 0, cost) }
            map[key] = existing
        }
        return map.values.sorted {
            $0.createdAt == $1.createdAt ? ($0.importID ?? "") < ($1.importID ?? "") : $0.createdAt < $1.createdAt
        }
    }

    // MARK: - Local credential

    private static func accessToken(database: URL) throws -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw CursorCredentialError.unreadable
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 1_000)

        var statement: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CursorCredentialError.unreadable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_text(statement, 0) else { return nil }
        let value = String(cString: bytes).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private enum CursorCredentialError: Error {
        case unreadable
    }

    static func accountIdentifier(for token: String) -> String {
        if let separator = token.range(of: "::") {
            let subject = String(token[..<separator.lowerBound])
            if !subject.isEmpty { return digest("subject:\(subject)") }
        }
        if let separator = token.range(of: "%3A%3A") {
            let subject = String(token[..<separator.lowerBound]).removingPercentEncoding ?? String(token[..<separator.lowerBound])
            if !subject.isEmpty { return digest("subject:\(subject)") }
        }
        if let subject = jwtSubject(token) { return digest("subject:\(subject)") }
        return digest("token:\(token)")
    }

    static func sessionCookie(from token: String) -> String {
        if token.contains("::") || token.contains("%3A%3A") { return token }
        if let subject = jwtSubject(token) { return "\(subject)::\(token)" }
        return token
    }

    static func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String, !subject.isEmpty else { return nil }
        return subject
    }

    // MARK: - Dates

    private static func startDate(checkpoint: CursorCheckpoint, now: Date) -> Date {
        let floor = now.addingTimeInterval(-Double(lookbackDays) * 24 * 60 * 60)
        guard checkpoint.fetchedAt != .distantPast else { return floor }
        return max(floor, checkpoint.fetchedAt.addingTimeInterval(-overlapSeconds))
    }

    static func date(from event: [String: Any]) -> Date? {
        if let raw = string(event["timestamp"]), let epoch = Double(raw), let date = epochDate(epoch) {
            return date
        }
        if let epoch = double(event["timestamp"]), let date = epochDate(epoch) {
            return date
        }
        if let raw = string(event["timestamp"]) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: raw)
        }
        return nil
    }

    private static func epochDate(_ value: Double) -> Date? {
        if value > 1_000_000_000_000 { return Date(timeIntervalSince1970: value / 1_000) }
        if value >= 1_000_000_000 { return Date(timeIntervalSince1970: value) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String where !value.isEmpty: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum AuthMode: Int, CaseIterable {
        case cookie
        case bearer

        func apply(to request: inout URLRequest, token: String) {
            switch self {
            case .cookie:
                request.setValue("WorkosCursorSessionToken=\(sessionCookie(from: token))", forHTTPHeaderField: "Cookie")
            case .bearer:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
    }
}
