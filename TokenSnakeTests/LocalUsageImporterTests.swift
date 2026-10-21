import Foundation
import Testing
@testable import TokenSnake

@MainActor
struct LocalUsageImporterTests {
    @Test func recursiveSourcesAndUnchangedFiles() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        try UsageFixtures.line(UsageFixtures.claude()).write(to: workspace.claudeFile)
        let importer = LocalUsageImporter()
        let first = try await importer.scan(settings: workspace.settings, checkpoints: [:])
        #expect(Set(first.entries.map(\.id)).count == 2)
        #expect(Set(first.entries.compactMap(\.source)) == [.codex, .claudeCode])
        #expect(first.statuses.allSatisfy { $0.state == .ready && $0.files == 1 })
        let second = try await importer.scan(settings: workspace.settings, checkpoints: first.checkpoints)
        #expect(second.entries.isEmpty)
        #expect(second.bytesRead == 0)
    }

    @Test func appendedAndPartiallyWrittenRecords() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let importer = LocalUsageImporter()
        let initial = try await importer.scan(settings: workspace.settings, checkpoints: [:])
        let next = try UsageFixtures.line(UsageFixtures.modern(totalInput: 2_000, totalCached: 1_200, totalOutput: 200))
        let midpoint = next.count / 2
        try UsageFixtures.append(Data(next.prefix(midpoint)), to: workspace.codexFile)
        let partial = try await importer.scan(settings: workspace.settings, checkpoints: initial.checkpoints)
        #expect(partial.entries.isEmpty)
        #expect(partial.statuses.first?.skippedLines == 0)
        try UsageFixtures.append(Data(next.suffix(next.count - midpoint)), to: workspace.codexFile)
        let complete = try await importer.scan(settings: workspace.settings, checkpoints: partial.checkpoints)
        #expect(complete.entries.count == 1)
        #expect(complete.entries.first?.inputTokens == 1_000)
    }

    @Test func validFinalLineWithoutNewline() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.line(UsageFixtures.claude(), newline: false).write(to: workspace.claudeFile)
        let importer = LocalUsageImporter()
        let first = try await importer.scan(settings: workspace.settings, checkpoints: [:])
        #expect(first.entries.count == 1)
        try UsageFixtures.append(Data([0x0a]), to: workspace.claudeFile)
        let second = try await importer.scan(settings: workspace.settings, checkpoints: first.checkpoints)
        #expect(second.entries.isEmpty)
    }

    @Test func truncatedAndReplacedFilesAreReparsed() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let importer = LocalUsageImporter()
        let initial = try await importer.scan(settings: workspace.settings, checkpoints: [:])
        try UsageFixtures.line(UsageFixtures.modern()).write(to: workspace.codexFile)
        let truncated = try await importer.scan(settings: workspace.settings, checkpoints: initial.checkpoints)
        #expect(truncated.entries.first?.importID == initial.entries.first?.importID)
        try UsageFixtures.line(UsageFixtures.modern(totalInput: 2_000)).write(to: workspace.codexFile, options: .atomic)
        let replaced = try await importer.scan(settings: workspace.settings, checkpoints: truncated.checkpoints)
        #expect(replaced.entries.count == 1)
        #expect(replaced.entries.first?.importID != initial.entries.first?.importID)
    }

    @Test func malformedLineDoesNotBlockLaterUsage() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        var data = Data("{broken}\n".utf8)
        data.append(try UsageFixtures.line(UsageFixtures.claude()))
        try data.write(to: workspace.claudeFile)
        let result = try await LocalUsageImporter().scan(settings: workspace.settings, checkpoints: [:])
        #expect(result.entries.count == 1)
        #expect(result.statuses.first { $0.source == .claudeCode }?.skippedLines == 1)
    }

    @Test func absentAndDisabledSourcesAreVisible() async throws {
        var settings = LocalSyncSettings()
        settings.codexDirectory = "/tmp/missing-tokensnake-\(UUID().uuidString)"
        settings.claudeEnabled = false
        let result = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])
        #expect(result.entries.isEmpty)
        #expect(result.statuses.map(\.state) == [.missing, .disabled])
    }

    @Test func unreadableRootDoesNotBlockTheOtherSource() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let sessions = workspace.root.appending(path: "codex/sessions")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sessions.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessions.path) }
        try UsageFixtures.line(UsageFixtures.claude()).write(to: workspace.claudeFile)
        let result = try await LocalUsageImporter().scan(settings: workspace.settings, checkpoints: [:])
        #expect(result.statuses.first { $0.source == .codex }?.state == .failed)
        #expect(result.statuses.first { $0.source == .codex }?.unreadableFiles ?? 0 > 0)
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.source == .claudeCode)
    }

    @Test func symlinksOutsideTheChosenDirectoryAreSkipped() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let outside = workspace.root.appending(path: "outside.jsonl")
        try UsageFixtures.line(UsageFixtures.claude()).write(to: outside)
        try FileManager.default.createSymbolicLink(at: workspace.claudeFile, withDestinationURL: outside)
        let result = try await LocalUsageImporter().scan(settings: workspace.settings, checkpoints: [:])
        #expect(result.entries.isEmpty)
    }

    @Test func standardSessionDirectoryCanBeMovedToAnotherDisk() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let sessions = workspace.root.appending(path: "codex/sessions")
        let relocated = workspace.root.appending(path: "relocated-sessions")
        try FileManager.default.moveItem(at: sessions, to: relocated)
        try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: relocated)
        let result = try await LocalUsageImporter().scan(settings: workspace.settings, checkpoints: [:])
        #expect(Set(result.entries.map(\.id)).count == 1)
        #expect(result.entries.first?.source == .codex)
        #expect(result.statuses.first?.state == .ready)
    }

    @Test func oversizedLinesDoNotBlockFollowingUsage() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        var data = Data(repeating: 0x78, count: 17 * 1_024 * 1_024)
        data.append(0x0a)
        data.append(try UsageFixtures.line(UsageFixtures.claude()))
        try data.write(to: workspace.claudeFile)
        let result = try await LocalUsageImporter().scan(settings: workspace.settings, checkpoints: [:])
        #expect(result.entries.count == 1)
        #expect(result.statuses.first { $0.source == .claudeCode }?.skippedLines == 1)
    }

    @Test func environmentAndExplicitDirectories() {
        var settings = LocalSyncSettings()
        #expect(settings.directory(for: .codex, environment: ["CODEX_HOME": "/tmp/codex-home"]).path == "/tmp/codex-home")
        #expect(settings.directory(for: .claudeCode, environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-home"]).path == "/tmp/claude-home")
        settings.codexDirectory = "/tmp/explicit"
        #expect(settings.directory(for: .codex, environment: ["CODEX_HOME": "/tmp/ignored"]).path == "/tmp/explicit")
    }
}
