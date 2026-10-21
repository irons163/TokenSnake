import Foundation
@testable import TokenSnake

enum UsageFixtures {
    static func line(_ object: [String: Any], newline: Bool = true) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if newline { data.append(0x0a) }
        return data
    }

    static func metadata(_ session: String = "session-1") -> [String: Any] {
        ["type": "session_meta", "payload": ["id": session, "model_provider": "openai"]]
    }

    static func model(_ name: String = "gpt-5") -> [String: Any] {
        ["type": "turn_context", "payload": ["model": name]]
    }

    static func modern(input: Int = 1_000, cached: Int = 600, output: Int = 100,
                       totalInput: Int = 1_000, totalCached: Int = 600, totalOutput: Int = 100,
                       timestamp: String = "2026-10-14T08:00:00.000Z") -> [String: Any] {
        ["type": "token_usage_record", "timestamp": timestamp,
         "payload": ["thread_id": "session-1", "response_id": "response-\(totalInput)",
                     "usage": ["input_tokens": input, "cached_input_tokens": cached,
                               "output_tokens": output, "reasoning_output_tokens": 40],
                     "thread_token_usage": ["input_tokens": totalInput, "cached_input_tokens": totalCached,
                                            "output_tokens": totalOutput]]]
    }

    static func legacy(input: Int, cached: Int, output: Int, timestamp: String = "2026-10-14T08:00:00.100Z") -> [String: Any] {
        ["type": "event_msg", "timestamp": timestamp,
         "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": input,
                     "cached_input_tokens": cached, "output_tokens": output]]]]
    }

    static func claude(id: String = "msg-1", output: Int = 60, timestamp: String = "2026-10-14T08:00:00Z") -> [String: Any] {
        ["type": "assistant", "timestamp": timestamp, "sessionId": "claude-session", "requestId": "req-\(id)",
         "message": ["id": id, "model": "claude-sonnet-4-20250514", "content": [["type": "text", "text": "PRIVATE FIXTURE"]],
                     "usage": ["input_tokens": 100, "cache_read_input_tokens": 500,
                               "cache_creation_input_tokens": 40, "output_tokens": output,
                               "cache_creation": ["ephemeral_1h_input_tokens": 25]]]]
    }

    static func codexData() throws -> Data {
        try [metadata(), model(), modern(), legacy(input: 1_000, cached: 600, output: 100)]
            .reduce(into: Data()) { $0.append(try line($1)) }
    }

    struct Workspace {
        let root: URL
        let codexFile: URL
        let claudeFile: URL
        var settings: LocalSyncSettings {
            var settings = LocalSyncSettings()
            settings.codexDirectory = root.appending(path: "codex").path
            settings.claudeDirectory = root.appending(path: "claude").path
            return settings
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    static func workspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory.appending(path: "tokensnake-fixture-\(UUID().uuidString)")
        let codex = root.appending(path: "codex/sessions/2026/10/14/session.jsonl")
        let claude = root.appending(path: "claude/projects/project/subagents/agent.jsonl")
        for file in [codex, claude] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return Workspace(root: root, codexFile: codex, claudeFile: claude)
    }

    static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
