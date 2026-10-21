import Foundation
import SQLite3
@testable import TokenSnake

enum CursorFixtures {
    enum FixtureError: Error {
        case sqlite(String)
    }

    static func jwt(subject: String = "user_test") -> String {
        let header = base64URL(["alg": "none", "typ": "JWT"])
        let payload = base64URL(["sub": subject, "exp": 4_000_000_000])
        return "\(header).\(payload).signature"
    }

    static func writeToken(_ token: String?, to directory: URL, includeKey: Bool = true) throws {
        let database = CursorUsageImporter.databaseURL(in: directory)
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(database.path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw FixtureError.sqlite("open failed")
        }
        defer { sqlite3_close(handle) }
        try execute(handle, "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value BLOB);")
        guard let token, includeKey else { return }
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', ?)",
                                     -1, &statement, nil), handle)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, token, -1, transient)
        try check(sqlite3_step(statement), handle, expected: SQLITE_DONE)
    }

    static func event(id: String, date: Date, model: String = "cursor-grok-4.6",
                      input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0,
                      cents: Double? = nil) -> [String: Any] {
        var usage: [String: Any] = [
            "inputTokens": input,
            "outputTokens": output,
            "cacheReadTokens": cacheRead
        ]
        if cacheWrite > 0 { usage["cacheWriteTokens"] = cacheWrite }
        if let cents { usage["totalCents"] = cents }
        return [
            "usageEventId": id,
            "timestamp": String(Int64((date.timeIntervalSince1970 * 1_000).rounded())),
            "model": model,
            "tokenUsage": usage
        ]
    }

    static func response(events: [[String: Any]], total: Int, hasNextPage: Bool? = nil) -> Data {
        var object: [String: Any] = ["usageEventsDisplay": events, "totalUsageEventsCount": total]
        if let hasNextPage { object["pagination"] = ["hasNextPage": hasNextPage] }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func page(events: [[String: Any]], total: Int, status: Int = 200,
                     hasNextPage: Bool? = nil) -> (Data, Int) {
        (response(events: events, total: total, hasNextPage: hasNextPage), status)
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func execute(_ handle: OpaquePointer, _ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil), handle)
    }

    private static func check(_ code: Int32, _ handle: OpaquePointer?, expected: Int32 = SQLITE_OK) throws {
        guard code == expected else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error"
            throw FixtureError.sqlite(message)
        }
    }
}

actor CursorTransportStub {
    private var pages: [(Data, Int)]
    private var captured: [URLRequest] = []

    init(pages: [(Data, Int)]) {
        self.pages = pages
    }

    func reset(pages: [(Data, Int)]) {
        self.pages = pages
    }

    var callCount: Int { captured.count }
    var requests: [URLRequest] { captured }

    func send(_ request: URLRequest) async -> (Data, Int)? {
        captured.append(request)
        guard !pages.isEmpty else { return nil }
        return pages.removeFirst()
    }
}
