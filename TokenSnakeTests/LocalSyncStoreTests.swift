import Foundation
import AppKit
import Testing
@testable import TokenSnake

@MainActor
struct LocalSyncStoreTests {
    private func store(_ workspace: UsageFixtures.Workspace) -> (AppStore, URL) {
        let url = workspace.root.appending(path: "app/store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.updateSyncSettings { $0 = workspace.settings }
        return (store, url)
    }

    @Test func syncMergesStreamingUsageAndSurvivesRestart() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        var claude = try UsageFixtures.line(UsageFixtures.claude(output: 1))
        claude.append(try UsageFixtures.line(UsageFixtures.claude(output: 60)))
        claude.append(try UsageFixtures.line(UsageFixtures.claude(output: 60)))
        try claude.write(to: workspace.claudeFile)
        let (store, url) = store(workspace)
        await store.syncLocalUsage()
        #expect(store.entries.count == 2)
        #expect(store.entries.first { $0.source == .claudeCode }?.totalTokens == 700)
        #expect(store.entries.reduce(0) { $0 + $1.totalTokens } == 1_800)
        #expect(store.lastSyncInserted == 2)
        #expect(store.localSyncState.checkpoints.count == 2)
        #expect(store.snake.growth.totalTokens == 1_800)
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        await restarted.syncLocalUsage()
        #expect(restarted.entries == store.entries)
        #expect(restarted.lastSyncInserted == 0)
        #expect(restarted.localSyncState.lastSyncAt != nil)
        #expect(restarted.snake.growth == store.snake.growth)
    }

    @Test func newUsageFeedsAutomaticallyAndReplaysDoNotFeedTwice() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let first = try UsageFixtures.line(UsageFixtures.modern(input: 900_000, cached: 500_000, output: 100_000))
        try first.write(to: workspace.codexFile)
        let (store, url) = store(workspace)
        await store.syncLocalUsage()
        #expect(store.snake.growth.level == 2)
        #expect(store.snake.growth.totalTokens == 1_000_000)
        try UsageFixtures.append(first, to: workspace.codexFile)
        await store.syncLocalUsage()
        #expect(store.snake.growth.totalTokens == 1_000_000)
        let second = try UsageFixtures.line(UsageFixtures.modern(input: 2_900_000, cached: 1_000_000,
            output: 100_000, totalInput: 3_800_000, totalCached: 1_500_000, totalOutput: 200_000))
        try UsageFixtures.append(second, to: workspace.codexFile)
        await store.syncLocalUsage()
        #expect(store.snake.growth.totalTokens == 4_000_000)
        #expect(store.snake.growth.level == 3)
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        await restarted.reimportLocalUsage()
        #expect(restarted.snake.growth == store.snake.growth)
        #expect(restarted.entries.count == 2)
    }

    @Test func archivedCopiesDoNotDoubleCountAndDeletedImportsStayDeleted() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let (store, url) = store(workspace)
        await store.syncLocalUsage()
        let archive = workspace.root.appending(path: "codex/archived_sessions/copy.jsonl")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: workspace.codexFile, to: archive)
        await store.syncLocalUsage()
        #expect(store.entries.count == 1)
        let imported = try #require(store.entries.first)
        store.deleteEntry(imported)
        store.flushPersistence()
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        await restarted.syncLocalUsage()
        #expect(restarted.entries.isEmpty)
        #expect(restarted.localSyncState.ignoredImportIDs.contains(imported.importID!))
        await restarted.reimportLocalUsage()
        #expect(restarted.entries.count == 1)
        #expect(restarted.localSyncState.ignoredImportIDs.isEmpty)
    }

    @Test func undoOnlyRemovesManualEntryAndSourcesCanBePaused() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let (store, _) = store(workspace)
        let manual = TokenEntry(createdAt: .distantPast, provider: .cursor, model: "Cursor 包含額度", inputTokens: 20, outputTokens: 10)
        store.addEntry(manual)
        await store.syncLocalUsage()
        #expect(store.entries.first?.source == .codex)
        store.undoLastEntry()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.source == .codex)
        store.updateSyncSettings { $0.enabled = false }
        try UsageFixtures.append(UsageFixtures.line(UsageFixtures.modern(totalInput: 2_000, totalCached: 1_200, totalOutput: 200)), to: workspace.codexFile)
        await store.syncLocalUsage()
        #expect(store.entries.count == 1)
        await store.syncLocalUsage(force: true)
        #expect(store.entries.count == 2)
        store.resetAll()
        await store.syncLocalUsage()
        #expect(store.entries.isEmpty)
        #expect(!store.settings.localSync.enabled)
    }

    @Test func exportedBackupAndLegacyDataRemainReadable() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.codexData().write(to: workspace.codexFile)
        let (store, _) = store(workspace)
        await store.syncLocalUsage()
        let export = workspace.root.appending(path: "backup.json")
        try store.exportData(to: export)
        let data = try Data(contentsOf: export)
        let decoded = try JSONDecoder().decode(PersistedStore.self, from: data)
        #expect(decoded.entries == store.entries)
        #expect(decoded.localSyncState?.checkpoints.count == 1)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "localSyncState")
        var settings = try #require(legacy["settings"] as? [String: Any])
        settings.removeValue(forKey: "localSync")
        legacy["settings"] = settings
        var entries = try #require(legacy["entries"] as? [[String: Any]])
        for index in entries.indices {
            for key in ["source", "importID", "importAliases", "cacheWriteTokens", "cacheWrite1hTokens"] { entries[index].removeValue(forKey: key) }
        }
        legacy["entries"] = entries
        let oldStore = try JSONDecoder().decode(PersistedStore.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(oldStore.entries.count == 1)
        #expect(oldStore.entries.first?.source == nil)
        #expect(oldStore.settings.localSync == .default)
    }

    @Test func storageFailuresAreVisibleAndCorruptDataIsPreserved() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let failing = AppStore(fileURL: workspace.root, launchAtLogin: MockLaunchAtLogin())
        failing.addEntry(StoreHarness.cheapEntry())
        failing.flushPersistence()
        #expect(failing.persistenceError != nil)
        let corruptURL = workspace.root.appending(path: "corrupt-store.json")
        let original = Data("broken-data".utf8)
        try original.write(to: corruptURL)
        let restored = AppStore(fileURL: corruptURL, launchAtLogin: MockLaunchAtLogin())
        #expect(restored.storageWarning != nil)
        let backup = try #require(FileManager.default.contentsOfDirectory(at: workspace.root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("corrupt-store.json.corrupt-") })
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test func restorePreservesPriorStoreAndPausesAutomaticSync() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let (store, url) = store(workspace)
        let original = StoreHarness.cheapEntry()
        store.addEntry(original)
        store.flushPersistence()
        let backup = workspace.root.appending(path: "export.json")
        try store.exportData(to: backup)
        store.addEntry(StoreHarness.expensiveEntry())
        store.flushPersistence()
        try store.restoreData(from: backup)
        #expect(store.entries == [original])
        #expect(!store.settings.localSync.enabled)
        let prior = try #require(FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.contains(".backup-") })
        let priorStore = try JSONDecoder().decode(PersistedStore.self, from: Data(contentsOf: prior))
        #expect(priorStore.entries.count == 2)
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(restarted.entries == [original])
    }

    @Test func invalidBackupCannotReplaceGoodData() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let (store, url) = store(workspace)
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        let before = try Data(contentsOf: url)
        let backup = workspace.root.appending(path: "invalid.json")
        try Data("{}".utf8).write(to: backup)
        #expect(throws: (any Error).self) { try store.restoreData(from: backup) }
        #expect(try Data(contentsOf: url) == before)
        #expect(store.entries.count == 1)
    }

    @Test func unreadableStoreCannotBeOverwritten() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let url = workspace.root.appending(path: "locked.json")
        let original = Data("locked-original-data".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(store.storageWarning != nil)
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        #expect(store.persistenceError != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func terminationFlushesQueuedChangesImmediately() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let (store, url) = store(workspace)
        let delegate = TokenSnakeDelegate()
        delegate.store = store
        store.addEntry(StoreHarness.cheapEntry())
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let restored = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(restored.entries.count == 1)
    }

    @Test func unknownPricesStillFeedTheSnake() {
        let (store, _, _) = StoreHarness.make()
        store.addEntry(TokenEntry(provider: .openai, model: "unknown", inputTokens: 10, outputTokens: 20))
        #expect(store.unpricedTodayCount == 1)
        #expect(store.snake.growth.totalTokens == store.entries[0].totalTokens)
        #expect(store.snake.todayFedCount == 1)
        #expect(store.snake.mood == .growing)
        store.updateSettings { $0.menuBarDisplay = .todayCost }
        #expect(store.menuBarText.hasSuffix("+"))
    }

    @Test func inheritedLegacyHistoryAndCompactionAreDeduplicated() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        var original = try UsageFixtures.line(UsageFixtures.metadata())
        original.append(try UsageFixtures.line(UsageFixtures.model()))
        original.append(try UsageFixtures.line(UsageFixtures.modern(totalInput: 100_000, totalCached: 60_000, totalOutput: 10_000)))
        let mirror = try UsageFixtures.line(UsageFixtures.legacy(input: 1_000, cached: 600, output: 100))
        original.append(mirror)
        try original.write(to: workspace.codexFile)
        let fork = workspace.codexFile.deletingLastPathComponent().appending(path: "fork.jsonl")
        var inherited = try UsageFixtures.line(UsageFixtures.metadata("fork-session"))
        inherited.append(mirror)
        try inherited.write(to: fork)
        let (store, _) = store(workspace)
        await store.syncLocalUsage()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.totalTokens == 1_100)
        #expect(store.entries.first?.importID?.hasPrefix("codex:response:") == true)
        await store.reimportLocalUsage()
        #expect(store.entries.count == 1)
    }

    @Test func mirrorArrivingAfterRestartLinksToEarlierResponse() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try UsageFixtures.line(UsageFixtures.modern()).write(to: workspace.codexFile)
        let (store, url) = store(workspace)
        await store.syncLocalUsage()
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        try UsageFixtures.append(UsageFixtures.line(UsageFixtures.legacy(input: 1_000, cached: 600, output: 100)), to: workspace.codexFile)
        await restarted.syncLocalUsage()
        #expect(restarted.entries.count == 1)
        #expect(restarted.entries.first?.importAliases?.count == 1)
    }

    @Test func dailyTokenBudgetAndFutureDateBoundaries() {
        let (store, _, _) = StoreHarness.make()
        store.updateSettings { $0.dailyTokenBudget = 100 }
        store.addEntry(StoreHarness.cheapEntry())
        #expect(store.snake.mood == .growing)
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        store.addEntry(StoreHarness.cheapEntry(createdAt: nextMonth))
        #expect(store.todayEntries.count == 1)
        #expect(store.monthEntries.count == 1)
        #expect(store.snake.growth.totalTokens == 1_200)
    }

    @Test func menuBarAndTodayTotalsAdvanceWithoutNewUsage() throws {
        let (store, _, _) = StoreHarness.make()
        store.addEntry(StoreHarness.cheapEntry())
        store.updateSettings { $0.menuBarDisplay = .todayTokens }
        #expect(store.menuBarText != "0")
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        store.refreshClock(now: tomorrow)
        #expect(store.todayEntries.isEmpty)
        #expect(store.insights.todayTokens == 0)
        #expect(store.menuBarText == "0")
    }

    @Test func billingAnchorDoesNotDriftAfterFebruary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let account = SubscriptionAccount(name: "Monthly", provider: .custom, planName: "", monthlyPrice: 10, cycleAnchor: anchor)
        #expect(calendar.component(.day, from: account.cycleEnd(now: now, calendar: calendar)) == 31)
        #expect(calendar.component(.month, from: account.cycleEnd(now: now, calendar: calendar)) == 3)
    }

    @Test func monthlyQuotaResetsOnceAndLegacyCountsArePreserved() throws {
        let (store, _, _) = StoreHarness.make()
        let now = Date.now
        let next = try #require(Calendar.current.date(byAdding: .month, value: 1, to: now))
        store.subscriptions = [SubscriptionAccount(name: "Monthly", provider: .custom, planName: "", monthlyPrice: 10,
                                                     cycleAnchor: now, quotaLimit: 100, quotaUsed: 75)]
        store.refreshSubscriptionCycles(now: now)
        #expect(store.subscriptions[0].quotaUsed == 75)
        store.refreshSubscriptionCycles(now: next)
        #expect(store.subscriptions[0].quotaUsed == 0)
        store.subscriptions[0].quotaUsed = 12
        store.refreshSubscriptionCycles(now: next.addingTimeInterval(60))
        #expect(store.subscriptions[0].quotaUsed == 12)
    }
}
