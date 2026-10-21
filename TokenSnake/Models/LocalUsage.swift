import Foundation

nonisolated enum UsageSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode

    var id: String { rawValue }
    var label: String { self == .codex ? "Codex" : "Claude Code" }
    var provider: AIProvider { self == .codex ? .openai : .anthropic }
}

nonisolated struct LocalSyncSettings: Codable, Hashable, Sendable {
    var enabled = true
    var codexEnabled = true
    var claudeEnabled = true
    // Empty paths follow the environment, then the standard home directory.
    var codexDirectory = ""
    var claudeDirectory = ""

    static let `default` = LocalSyncSettings()

    func isEnabled(_ source: UsageSource) -> Bool {
        source == .codex ? codexEnabled : claudeEnabled
    }

    func directory(for source: UsageSource, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let configured = source == .codex ? codexDirectory : claudeDirectory
        let variable = source == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"
        let fallback = source == .codex ? "~/.codex" : "~/.claude"
        let path = configured.isEmpty ? (environment[variable].flatMap { $0.isEmpty ? nil : $0 } ?? fallback) : configured
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true).standardizedFileURL
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

nonisolated struct LocalSyncState: Codable, Sendable {
    var checkpoints: [String: UsageFileCheckpoint] = [:]
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

    var id: UsageSource { source }
    var message: String {
        switch state {
        case .disabled: return "已停用"
        case .missing: return "找不到紀錄目錄"
        case .failed: return "無法讀取，請確認目錄與權限"
        case .ready:
            if unreadableFiles > 0 { return "\(files) 個檔案，\(unreadableFiles) 個無法讀取"
            }
            if skippedLines > 0 { return "\(files) 個檔案，略過 \(skippedLines) 筆無效紀錄" }
            return files == 0 ? "尚無 JSONL 用量紀錄" : "已掃描 \(files) 個檔案"
        }
    }
}

nonisolated struct UsageScanResult: Sendable {
    var entries: [TokenEntry] = []
    var checkpoints: [String: UsageFileCheckpoint] = [:]
    var statuses: [UsageSourceStatus] = []
    var bytesRead: UInt64 = 0
}
