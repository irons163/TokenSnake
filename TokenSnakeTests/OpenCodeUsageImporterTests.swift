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
            OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 1, cacheRead: 50, cost: 0.01,
                                     createdAt: now - 60_000, updatedAt: now - 60_000)
        ], to: directory)

        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeDirectory = directory.path
        let first = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:])
        #expect(first.entries.first?.outputTokens == 1)
        #expect(first.entries.first?.reportedCost == 0.01)

        let final = OpenCodeFixtures.Message(id: "msg_1", input: 100, output: 40, cacheRead: 50, cost: 0.04,
                                            createdAt: now - 60_000, updatedAt: now)
        try OpenCodeFixtures.update(final, in: directory)
        try OpenCodeFixtures.insert(OpenCodeFixtures.Message(id: "msg_2", provider: "openai", model: "gpt-5",
                                                             input: 10, output: 5,
                                                             createdAt: now - 1_000), into: directory)
        let second = try await LocalUsageImporter().scan(settings: settings, checkpoints: [:],
                                                         opencodeCheckpoint: first.opencodeCheckpoint)
        #expect(second.entries.count == 2)
        #expect(second.entries.first { $0.importID == "opencode:msg_1" }?.outputTokens == 40)
        #expect(second.entries.first { $0.importID == "opencode:msg_1" }?.reportedCost == 0.04)
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

    @Test(arguments: [
        ("deepseek-v4.1-flash", 0.12),
        ("glm-5.3-flash", 0.24),
        ("new-model-without-catalog-entry", 0.36),
        ("deepseek-v4.1-flash-free", 0.0),
        ("gpt-5.6-luna", 0.05)
    ])
    func sourceCostPricesModelsWithoutGuessingRates(model: String, cost: Double) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "role": "assistant", "providerID": "opencode-go", "modelID": model,
            "cost": cost, "tokens": ["input": 1_000_000, "output": 100]
        ])
        let parsed = try OpenCodeMessageParser.entry(messageID: "source-cost", data: data,
                                                     createdAt: 1_700_000_000_000)
        let entry = try #require(parsed)
        #expect(entry.reportedCost == cost)
        #expect(Pricing.estimatedCost(for: entry) == cost)
        let group = try #require(ModelUsageGroup.groups(from: [entry]).first)
        #expect(group.unpricedCount == 0)
        #expect(group.costLabel == "\(Formatters.currency(cost)) OpenCode 估算")
    }

    @Test(arguments: ["null", "true", "false", "\"0.2\"", "-0.5", "1000000000001"])
    func invalidSourceCostKeepsUsageUnpriced(cost: String) throws {
        let data = Data("""
            {"role":"assistant","providerID":"opencode","modelID":"unknown-model",
             "cost":\(cost),"tokens":{"input":10,"output":3}}
            """.utf8)
        let parsed = try OpenCodeMessageParser.entry(messageID: "invalid-cost", data: data,
                                                     createdAt: 1_700_000_000_000)
        let entry = try #require(parsed)
        #expect(entry.totalTokens == 13)
        #expect(entry.reportedCost == nil)
        #expect(Pricing.estimatedCost(for: entry) == nil)
    }

    @Test func legacyCheckpointBackfillsOldCostsOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tokensnake-cost-backfill-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let earlier: Int64 = 1_700_000_000_000
        let later = earlier + 3_600_000
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "old", input: 10, cost: 0.12, createdAt: earlier),
            OpenCodeFixtures.Message(id: "latest", input: 20, cost: 0.24, createdAt: later)
        ], to: directory)
        let first = try OpenCodeUsageImporter.scan(directory: directory, checkpoint: nil)
        var legacy = first.checkpoint
        legacy.costImportVersion = nil
        let oldSnapshot = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(OpenCodeCheckpoint.self, from: oldSnapshot)
        #expect(decoded.costImportVersion == nil)
        let backfill = try OpenCodeUsageImporter.scan(directory: directory, checkpoint: decoded)
        #expect(backfill.entries.count == 2)
        #expect(backfill.entries.first { $0.importID == "opencode:old" }?.reportedCost == 0.12)
        #expect(backfill.checkpoint.costImportVersion == OpenCodeUsageImporter.costImportVersion)
        let incremental = try OpenCodeUsageImporter.scan(directory: directory, checkpoint: backfill.checkpoint)
        #expect(incremental.entries.count == 1)
        #expect(incremental.entries.first?.importID == "opencode:latest")
    }
}

@MainActor
struct OpenCodeStoreTests {
    @Test func upgradingBackfillsCostsWithoutRestoringHiddenEntriesOrFeedingAgain() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try OpenCodeFixtures.write([
            OpenCodeFixtures.Message(id: "visible", provider: "opencode-go", model: "deepseek-v4.1-flash",
                                     input: 100, output: 20, cost: 0.12, createdAt: now - 3_600_000),
            OpenCodeFixtures.Message(id: "hidden", input: 200, cost: 0.24, createdAt: now)
        ], to: workspace.opencodeDirectory)
        let url = workspace.root.appending(path: "app/store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.updateSyncSettings {
            $0.codexEnabled = false
            $0.claudeEnabled = false
            $0.opencodeDirectory = workspace.opencodeDirectory.path
        }
        await store.syncLocalUsage()
        let hidden = try #require(store.entries.first { $0.importID == "opencode:hidden" })
        store.deleteEntry(hidden)
        store.flushPersistence()

        // Reconstruct a pre-fix snapshot with a recent cursor but no source costs.
        var legacy = try JSONDecoder().decode(PersistedStore.self, from: Data(contentsOf: url))
        legacy.entries = legacy.entries.map { entry in
            var entry = entry
            entry.reportedCost = nil
            return entry
        }
        legacy.localSyncState?.opencodeCheckpoint?.costImportVersion = nil
        try JSONEncoder().encode(legacy).write(to: url)
        let upgraded = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        let ids = upgraded.entries.map(\.id)
        let food = upgraded.snake.growth.totalTokens
        #expect(upgraded.entries.first?.reportedCost == nil)
        await upgraded.syncLocalUsage()
        #expect(upgraded.entries.map(\.id) == ids)
        #expect(upgraded.entries.count == 1)
        #expect(upgraded.entries.first?.reportedCost == 0.12)
        #expect(upgraded.snake.growth.totalTokens == food)
        #expect(upgraded.lastSyncInserted == 0)
        #expect(upgraded.localSyncState.ignoredImportIDs.contains("opencode:hidden"))
        let group = try #require(ModelUsageGroup.groups(from: upgraded.entries).first)
        #expect(group.unpricedCount == 0)
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(restarted.entries.first?.reportedCost == 0.12)
        #expect(restarted.localSyncState.opencodeCheckpoint?.costImportVersion == OpenCodeUsageImporter.costImportVersion)
    }

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
