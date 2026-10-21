import Foundation
import Testing
@testable import TokenSnake

struct OpenCodeUsageImporterTests {
    @Test func scansAssistantMessagesAndNormalizesCounters() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tokensnake-opencode-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let createdAt: Int64 = 1_700_000_000_000
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 20, reasoning: 5,
                                     cacheRead: 500, cacheWrite: 40,
                                     createdAt: createdAt, updatedAt: createdAt + 10),
            OpenCodeFixtures.Message(id: "msg_user", role: "user", input: 900, output: 0, createdAt: createdAt),
            OpenCodeFixtures.Message(id: "msg_empty", createdAt: createdAt)
        ], to: directory)

        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeEnabled = true
        settings.opencodeDirectory = directory.path
        let result = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])

        let entry = try #require(result.entries.first)
        #expect(result.entries.count == 1)
        #expect(entry.inputTokens == 640)
        #expect(entry.cachedTokens == 500)
        #expect(entry.cacheWriteTokens == 40)
        #expect(entry.outputTokens == 25)
        #expect(entry.model == "claude-sonnet-4-20250514")
        #expect(entry.provider == .anthropic)
        #expect(entry.source == .opencode)
        #expect(entry.createdAt == Date(timeIntervalSince1970: Double(createdAt) / 1_000))
        #expect(result.opencodeCheckpoint?.updatedThrough == createdAt + 10)
        let status = try #require(result.statuses.first { $0.source == .opencode })
        #expect(status.state == .ready)
        #expect(status.files == 1)
        #expect(status.skippedLines == 0)
    }

    @Test func streamingUpdatesAndNewMessagesAreReadIncrementally() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tokensnake-opencode-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 1, cacheRead: 50,
                                     createdAt: now - 60_000, updatedAt: now - 60_000)
        ], to: directory)

        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeDirectory = directory.path
        let first = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])
        #expect(first.entries.first?.outputTokens == 1)

        let final = OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 40, cacheRead: 50,
                                            createdAt: now - 60_000, updatedAt: now)
        try OpenCodeFixtures.update(final, in: directory)
        try OpenCodeFixtures.insert(OpenCodeFixtures.Message(id: "msg_2", provider: "openai", model: "gpt-5",
                                                             input: 10, output: 5,
                                                             createdAt: now - 1_000), into: directory)
        let second = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:],
                                                         opencodeCheckpoint: first.opencodeCheckpoint)
        #expect(second.entries.count == 2)
        #expect(second.entries.first { $0.importID == "opencode:msg_1" }?.outputTokens == 40)
        #expect(second.entries.first { $0.importID == "opencode:msg_2" }?.provider == .openai)
        #expect(second.opencodeCheckpoint?.updatedThrough == now)

        let third = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:],
                                                        opencodeCheckpoint: second.opencodeCheckpoint)
        #expect(third.entries.count == 2)
    }

    @Test func malformedRowsDoNotBlockValidUsage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tokensnake-opencode-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "msg_1", input: 10, output: 2, createdAt: 1_700_000_000_000)
        ], to: directory)
        try OpenCodeFixtures.insertRaw("{broken", id: "msg_bad", createdAt: 1_700_000_001_000,
                                       updatedAt: 1_700_000_001_000, into: directory)

        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeDirectory = directory.path
        let result = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.importID == "opencode:msg_1")
    }

    @Test func missingDatabaseIsReported() async throws {
        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "missing-tokensnake-\(UUID().uuidString)").path
        let result = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])
        #expect(result.entries.isEmpty)
        #expect(result.statuses.first { $0.source == .opencode }?.state == .missing)
    }

    @Test func providerIsInferredFromGatewayAndModelName() {
        #expect(OpenCodeMessageParser.provider(for: "anthropic", model: "anything") == .anthropic)
        #expect(OpenCodeMessageParser.provider(for: "openai", model: "anything") == .openai)
        #expect(OpenCodeMessageParser.provider(for: "opencode", model: "claude-sonnet-4") == .anthropic)
        #expect(OpenCodeMessageParser.provider(for: "opencode-go", model: "gpt-5.6-luna") == .openai)
        #expect(OpenCodeMessageParser.provider(for: "openrouter", model: "gemini-2.5-pro") == .google)
        #expect(OpenCodeMessageParser.provider(for: "openrouter", model: "grok-4") == .xai)
        #expect(OpenCodeMessageParser.provider(for: "opencode", model: "big-pickle") == .custom)
    }
}

@MainActor
struct OpenCodeStoreTests {
    @Test func messagesMergeStreamingUpdatesAndFeedTheSnake() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 1, cacheRead: 50,
                                     createdAt: now - 60_000, updatedAt: now - 60_000)
        ], to: workspace.opencodeDirectory)
        let url = workspace.root.appending(path: "app/store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.updateSyncSettings {
            $0.codexEnabled = false
            $0.claudeEnabled = false
            $0.opencodeEnabled = true
            $0.opencodeDirectory = workspace.opencodeDirectory.path
        }
        await store.syncLocalUsage()
        #expect(store.entries.count == 1)
        #expect(store.entries[0].totalTokens == 151)
        #expect(store.snake.growth.totalTokens == 151)

        try OpenCodeFixtures.update(OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 40, cacheRead: 50,
                                                            createdAt: now - 60_000, updatedAt: now),
                                    in: workspace.opencodeDirectory)
        try OpenCodeFixtures.insert(OpenCodeFixtures.Message(id: "msg_2", provider: "openai", model: "gpt-5",
                                                             input: 10, output: 5,
                                                             createdAt: now - 1_000), into: workspace.opencodeDirectory)
        await store.syncLocalUsage()
        #expect(store.entries.count == 2)
        #expect(store.entries.first { $0.importID == "opencode:msg_1" }?.totalTokens == 190)
        #expect(store.snake.growth.totalTokens == 205)

        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        await restarted.syncLocalUsage()
        #expect(restarted.entries == store.entries)
        #expect(restarted.localSyncState.opencodeCheckpoint != nil)

        let second = try #require(restarted.entries.first { $0.importID == "opencode:msg_2" })
        restarted.deleteEntry(second)
        restarted.flushPersistence()
        await restarted.syncLocalUsage()
        #expect(restarted.entries.count == 1)
        await restarted.reimportLocalUsage()
        #expect(restarted.entries.count == 2)
    }
}
