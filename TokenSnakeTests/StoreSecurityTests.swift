import Foundation
import Testing
@testable import TokenSnake

@MainActor
struct StoreSecurityTests {
    @Test func invalidStartupDataIsQuarantinedBeforeTotalsAreComputed() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let url = workspace.root.appending(path: "store.json")
        var snapshot = PersistedStore.empty
        var entry = StoreHarness.cheapEntry()
        entry.inputTokens = Int.max
        snapshot.entries = [entry]
        let original = try JSONEncoder().encode(snapshot)
        try original.write(to: url)
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(store.entries.isEmpty)
        #expect(store.storageWarning != nil)
        #expect(store.insights.todayTokens == 0)
        #expect(try Data(contentsOf: url) == original)
        let backup = try #require(FileManager.default.contentsOfDirectory(at: workspace.root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.contains(".corrupt-") })
        #expect(try Data(contentsOf: backup) == original)
        #expect(try permissions(backup) == 0o600)
    }

    @Test(arguments: ["cache", "cursor", "counter", "quota"])
    func poisonedBackupCannotReplaceExistingData(_ kind: String) throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let url = workspace.root.appending(path: "store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        let original = try Data(contentsOf: url)
        var bad = PersistedStore.empty
        bad.entries = [StoreHarness.cheapEntry()]
        switch kind {
        case "cache": bad.entries[0].cacheWriteTokens = -1
        case "quota":
            var account = Pricing.subscriptionTemplates[0]
            account.quotaUsed = Int.max
            bad.subscriptions = [account]
        default:
            var checkpoint = UsageFileCheckpoint()
            if kind == "cursor" { checkpoint.offset = 100; checkpoint.size = 10 }
            else { checkpoint.context.total = UsageCounters(input: Int.min); checkpoint.context.counterGeneration = Int.max }
            bad.localSyncState = LocalSyncState(checkpoints: ["codex:fixture.jsonl": checkpoint])
        }
        let backup = workspace.root.appending(path: "bad-backup.json")
        try JSONEncoder().encode(bad).write(to: backup)
        #expect(throws: (any Error).self) { try store.restoreData(from: backup) }
        #expect(try Data(contentsOf: url) == original)
        #expect(store.entries.count == 1)
    }

    @Test func oversizedSnapshotIsRejectedWithoutReplacingGoodData() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let url = workspace.root.appending(path: "store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        let original = try Data(contentsOf: url)
        let backup = workspace.root.appending(path: "oversized.json")
        #expect(FileManager.default.createFile(atPath: backup.path, contents: nil))
        let handle = try FileHandle(forWritingTo: backup)
        try handle.truncate(atOffset: 256 * 1_024 * 1_024 + 1)
        try handle.close()
        #expect(throws: (any Error).self) { try store.restoreData(from: backup) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func storeExportsAndPriorBackupsAreOwnerOnly() throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        let url = workspace.root.appending(path: "store.json")
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        #expect(try permissions(url) == 0o600)
        let exported = workspace.root.appending(path: "export.json")
        try store.exportData(to: exported)
        #expect(try permissions(exported) == 0o600)
        try store.restoreData(from: exported)
        #expect(try permissions(url) == 0o600)
        let prior = try #require(FileManager.default.contentsOfDirectory(at: workspace.root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.contains(".backup-") })
        #expect(try permissions(prior) == 0o600)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
