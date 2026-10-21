import Foundation
import SQLite3
@testable import TokenSnake

enum OpenCodeFixtures {
    struct Message {
        var id: String
        var role: String
        var provider: String
        var model: String
        var input: Int
        var output: Int
        var reasoning: Int
        var cacheRead: Int
        var cacheWrite: Int
        var createdAt: Int64
        var updatedAt: Int64

        init(id: String, role: String = "assistant", provider: String = "anthropic",
             model: String = "claude-sonnet-4-20250514", input: Int = 0, output: Int = 0,
             reasoning: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0,
             createdAt: Int64, updatedAt: Int64? = nil) {
            self.id = id
            self.role = role
            self.provider = provider
            self.model = model
            self.input = input
            self.output = output
            self.reasoning = reasoning
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
        }
    }

    enum FixtureError: Error {
        case sqlite(String)
    }

    static func write(_ messages: [Message], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handle = try open(directory)
        defer { sqlite3_close(handle) }
        try execute(handle, """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            );
            """)
        for message in messages { try insert(message, handle: handle) }
    }

    static func insert(_ message: Message, into directory: URL) throws {
        let handle = try open(directory)
        defer { sqlite3_close(handle) }
        try insert(message, handle: handle)
    }

    static func insertRaw(_ text: String, id: String, createdAt: Int64, updatedAt: Int64,
                          into directory: URL) throws {
        let handle = try open(directory)
        defer { sqlite3_close(handle) }
        try insert(id: id, data: text, createdAt: createdAt, updatedAt: updatedAt, handle: handle)
    }

    static func update(_ message: Message, in directory: URL) throws {
        let handle = try open(directory)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, "UPDATE message SET data = ?, time_updated = ? WHERE id = ?",
                                     -1, &statement, nil), handle)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, try encoded(message), -1, transient)
        sqlite3_bind_int64(statement, 2, message.updatedAt)
        sqlite3_bind_text(statement, 3, message.id, -1, transient)
        try check(sqlite3_step(statement), handle, expected: SQLITE_DONE)
    }

    private static func open(_ directory: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let database = OpenCodeUsageImporter.databaseURL(in: directory)
        guard sqlite3_open(database.path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw FixtureError.sqlite("open failed")
        }
        return handle
    }

    private static func insert(_ message: Message, handle: OpaquePointer) throws {
        try insert(id: message.id, data: try encoded(message), createdAt: message.createdAt,
                   updatedAt: message.updatedAt, handle: handle)
    }

    private static func insert(id: String, data: String, createdAt: Int64, updatedAt: Int64,
                               handle: OpaquePointer) throws {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)",
                                     -1, &statement, nil), handle)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        sqlite3_bind_text(statement, 2, "session", -1, transient)
        sqlite3_bind_int64(statement, 3, createdAt)
        sqlite3_bind_int64(statement, 4, updatedAt)
        sqlite3_bind_text(statement, 5, data, -1, transient)
        try check(sqlite3_step(statement), handle, expected: SQLITE_DONE)
    }

    private static func encoded(_ message: Message) throws -> String {
        let object: [String: Any] = [
            "id": message.id,
            "role": message.role,
            "providerID": message.provider,
            "modelID": message.model,
            "tokens": [
                "input": message.input,
                "output": message.output,
                "reasoning": message.reasoning,
                "cache": ["read": message.cacheRead, "write": message.cacheWrite]
            ]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
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
