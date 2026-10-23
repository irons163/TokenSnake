import Foundation

nonisolated enum UsageSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case opencode
    case cursor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .opencode: "OpenCode"
        case .cursor: "Cursor"
        }
    }

    var provider: AIProvider {
        switch self {
        case .codex: .openai
        case .claudeCode: .anthropic
        case .opencode: .custom
        case .cursor: .cursor
        }
    }
}

nonisolated struct LocalSyncSettings: Codable, Hashable, Sendable {
    var enabled = true
    var codexEnabled = true
    var claudeEnabled = true
    var opencodeEnabled = true
    // Cursor usage is not stored locally anymore, so this is an explicit
    // opt-in network source and stays disabled until the user accepts it.
    var cursorEnabled = false
    // Empty paths follow the environment, then the standard home directory.
    var codexDirectory = ""
    var claudeDirectory = ""
    var opencodeDirectory = ""
    var cursorDirectory = ""

    static let `default` = LocalSyncSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        codexEnabled = try c.decodeIfPresent(Bool.self, forKey: .codexEnabled) ?? true
        claudeEnabled = try c.decodeIfPresent(Bool.self, forKey: .claudeEnabled) ?? true
        opencodeEnabled = try c.decodeIfPresent(Bool.self, forKey: .opencodeEnabled) ?? true
        cursorEnabled = try c.decodeIfPresent(Bool.self, forKey: .cursorEnabled) ?? false
        codexDirectory = try c.decodeIfPresent(String.self, forKey: .codexDirectory) ?? ""
        claudeDirectory = try c.decodeIfPresent(String.self, forKey: .claudeDirectory) ?? ""
        opencodeDirectory = try c.decodeIfPresent(String.self, forKey: .opencodeDirectory) ?? ""
        cursorDirectory = try c.decodeIfPresent(String.self, forKey: .cursorDirectory) ?? ""
    }

    func isEnabled(_ source: UsageSource) -> Bool {
        switch source {
        case .codex: codexEnabled
        case .claudeCode: claudeEnabled
        case .opencode: opencodeEnabled
        case .cursor: cursorEnabled
        }
    }

    mutating func setEnabled(_ value: Bool, for source: UsageSource) {
        switch source {
        case .codex: codexEnabled = value
        case .claudeCode: claudeEnabled = value
        case .opencode: opencodeEnabled = value
        case .cursor: cursorEnabled = value
        }
    }

    func configuredDirectory(for source: UsageSource) -> String {
        switch source {
        case .codex: codexDirectory
        case .claudeCode: claudeDirectory
        case .opencode: opencodeDirectory
        case .cursor: cursorDirectory
        }
    }

    mutating func setDirectory(_ path: String, for source: UsageSource) {
        switch source {
        case .codex: codexDirectory = path
        case .claudeCode: claudeDirectory = path
        case .opencode: opencodeDirectory = path
        case .cursor: cursorDirectory = path
        }
    }

    func directory(for source: UsageSource, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let configured = configuredDirectory(for: source)
        if !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true).standardizedFileURL
        }
        switch source {
        case .codex, .claudeCode:
            let variable = source == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"
            let fallback = source == .codex ? "~/.codex" : "~/.claude"
            let path = environment[variable].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true).standardizedFileURL
        case .opencode:
            let base = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "~/.local/share"
            let path = URL(fileURLWithPath: NSString(string: base).expandingTildeInPath, isDirectory: true)
                .appending(path: "opencode", directoryHint: .isDirectory)
            return path.standardizedFileURL
        case .cursor:
            return URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Cursor").expandingTildeInPath,
                       isDirectory: true).standardizedFileURL
        }
    }
}

nonisolated struct UsageCounters: Codable, Equatable, Sendable {
    var input = 0
    var cached = 0
    var write = 0
    var output = 0

    var key: String { "\(input):\(cached):\(write):\(output)" }
    var hasUsage: Bool { input > 0 || output > 0 }

    func delta(from previous: UsageCounters) -> UsageCounters {
        UsageCounters(
            input: max(0, input - previous.input),
            cached: max(0, cached - previous.cached),
            write: max(0, write - previous.write),
            output: max(0, output - previous.output)
        )
    }
}

nonisolated struct UsageParserContext: Codable, Sendable {
    var sessionID = ""
    var model = ""
    var provider = AIProvider.openai
    var total: UsageCounters?
    var counterGeneration = 0
    var pendingCodexEntries: [TokenEntry]?
}

nonisolated struct UsageFileCheckpoint: Codable, Sendable {
    var offset: UInt64 = 0
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var fileID = ""
    var context = UsageParserContext()
}

nonisolated struct OpenCodeCheckpoint: Codable, Equatable, Sendable {
    var databaseID = ""
    var size: UInt64 = 0
    var updatedThrough: Int64 = 0
    // Optional so snapshots written before cost import still decode unchanged.
    var costImportVersion: Int?
}

nonisolated struct CursorCheckpoint: Codable, Equatable, Sendable {
    var accountID = ""
    var fetchedAt: Date = .distantPast
    var lastAttemptAt: Date = .distantPast
}

nonisolated struct LocalSyncState: Codable, Sendable {
    var checkpoints: [String: UsageFileCheckpoint] = [:]
    var opencodeCheckpoint: OpenCodeCheckpoint?
    var cursorCheckpoint: CursorCheckpoint?
    var ignoredImportIDs: Set<String> = []
    var lastSyncAt: Date?
}

nonisolated enum UsageSourceState: String, Sendable {
    case ready, missing, failed, disabled
}

nonisolated struct UsageSourceStatus: Identifiable, Sendable {
    var source: UsageSource
    var directory: String
    var state: UsageSourceState
    var files = 0
    var skippedLines = 0
    var unreadableFiles = 0
    var detail: String?

    var id: UsageSource { source }
    var message: String {
        if let detail { return detail }
        switch state {
        case .disabled: return "已停用"
        case .missing: return source == .opencode ? "找不到 opencode.db" : "找不到紀錄目錄"
        case .failed: return "無法讀取，請確認目錄與權限"
        case .ready:
            if unreadableFiles > 0 {
                return source == .opencode ? "opencode.db 無法讀取" : "\(files) 個檔案，\(unreadableFiles) 個無法讀取"
            }
            if skippedLines > 0 { return "已讀取 \(files) 個檔案，略過 \(skippedLines) 筆無效紀錄" }
            if source == .opencode { return "已讀取 opencode.db" }
            return files == 0 ? "尚無 JSONL 用量紀錄" : "已掃描 \(files) 個檔案"
        }
    }
}

nonisolated struct UsageScanResult: Sendable {
    var entries: [TokenEntry] = []
    var checkpoints: [String: UsageFileCheckpoint] = [:]
    var opencodeCheckpoint: OpenCodeCheckpoint?
    var cursorCheckpoint: CursorCheckpoint?
    var statuses: [UsageSourceStatus] = []
    var bytesRead: UInt64 = 0
}
