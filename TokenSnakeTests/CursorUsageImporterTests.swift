import Foundation
import Testing
@testable import TokenSnake

@MainActor
struct CursorUsageImporterTests {
    private let now = Date()

    private func fixture() throws -> (UsageFixtures.Workspace, CursorTransportStub, LocalUsageImporter) {
        let workspace = try UsageFixtures.workspace()
        let stub = CursorTransportStub(pages: [])
        let fixed = now
        let importer = LocalUsageImporter(cursorTransport: { await stub.send($0) }, now: { fixed })
        return (workspace, stub, importer)
    }

    private func cursorSettings(_ workspace: UsageFixtures.Workspace) -> LocalSyncSettings {
        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeEnabled = false
        settings.cursorEnabled = true
        settings.cursorDirectory = workspace.cursorDirectory.path
        return settings
    }

    @Test func scansDashboardPagesAndNormalizesCounters() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        let token = CursorFixtures.jwt(subject: "user_1")
        try CursorFixtures.writeToken(token, to: workspace.cursorDirectory)
        let first = CursorFixtures.event(id: "evt_1", date: now.addingTimeInterval(-3_600),
                                         input: 100, output: 20, cacheRead: 500, cacheWrite: 40, cents: 12.5)
        let second = CursorFixtures.event(id: "evt_2", date: now.addingTimeInterval(-1_800),
                                          model: "gpt-5.6-luna-max", input: 10, output: 5)
        let third = CursorFixtures.event(id: "evt_3", date: now.addingTimeInterval(-60),
                                         input: 1_000, output: 100, cacheRead: 2_000, cents: 3)
        await stub.reset(pages: [
            CursorFixtures.page(events: [first, second], total: 3, hasNextPage: true),
            CursorFixtures.page(events: [third], total: 3, hasNextPage: false)
        ])

        let result = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:])

        #expect(result.entries.count == 3)
        let entry = try #require(result.entries.first { $0.importID == "cursor:evt_1" })
        #expect(entry.inputTokens == 640)
        #expect(entry.cachedTokens == 500)
        #expect(entry.cacheWriteTokens == 40)
        #expect(entry.outputTokens == 20)
        #expect(entry.provider == .cursor)
        #expect(entry.source == .cursor)
        #expect(entry.reportedCost == 0.125)
        #expect(abs(entry.createdAt.timeIntervalSince(now.addingTimeInterval(-3_600))) < 0.001)
        #expect(result.entries.first { $0.importID == "cursor:evt_3" }?.inputTokens == 3_000)
        #expect(result.cursorCheckpoint?.fetchedAt == now)
        #expect(result.cursorCheckpoint?.accountID.isEmpty == false)

        let status = try #require(result.statuses.first { $0.source == .cursor })
        #expect(status.state == .ready)
        #expect(status.files == 3)

        #expect(await stub.callCount == 2)
        let cookie = try #require(await stub.requests.first?.value(forHTTPHeaderField: "Cookie"))
        #expect(cookie == "WorkosCursorSessionToken=user_1::\(token)")
        let body = try #require(try JSONSerialization.jsonObject(with: await stub.requests[0].httpBody ?? Data()) as? [String: Any])
        #expect(body["page"] as? Int == 1)
        #expect(body["startDate"] as? String != nil)
        #expect(body["endDate"] as? String != nil)
    }

    @Test func throttlesAutomaticFetchesAndForceBypassesTheWindow() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        let token = CursorFixtures.jwt()
        try CursorFixtures.writeToken(token, to: workspace.cursorDirectory)
        let account = CursorUsageImporter.accountIdentifier(for: token)
        let checkpoint = CursorCheckpoint(accountID: account, fetchedAt: now, lastAttemptAt: now)
        let event = CursorFixtures.event(id: "evt_1", date: now.addingTimeInterval(-60), input: 10, output: 2)
        await stub.reset(pages: [CursorFixtures.page(events: [event], total: 1)])

        let throttled = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:],
                                                cursorCheckpoint: checkpoint)
        #expect(throttled.entries.isEmpty)
        #expect(throttled.statuses.first { $0.source == .cursor }?.message.contains("5 分鐘") == true)
        #expect(await stub.callCount == 0)

        let forced = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:],
                                             cursorCheckpoint: checkpoint, forceRemote: true)
        #expect(forced.entries.count == 1)
        #expect(await stub.callCount == 1)
    }

    @Test func missingDatabaseAndMissingCredentialAreReported() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        var settings = cursorSettings(workspace)

        settings.cursorDirectory = workspace.root.appending(path: "missing").path
        let missing = try await importer.scan(settings: settings, checkpoints: [:])
        #expect(missing.statuses.first { $0.source == .cursor }?.state == .missing)

        settings.cursorDirectory = workspace.cursorDirectory.path
        try CursorFixtures.writeToken(nil, to: workspace.cursorDirectory)
        let signedOut = try await importer.scan(settings: settings, checkpoints: [:])
        #expect(signedOut.statuses.first { $0.source == .cursor }?.state == .failed)
        #expect(signedOut.statuses.first { $0.source == .cursor }?.message.contains("未登入") == true)
        #expect(await stub.callCount == 0)
    }

    @Test func unauthorizedCookieFallsBackToBearerThenFails() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        let token = CursorFixtures.jwt()
        try CursorFixtures.writeToken(token, to: workspace.cursorDirectory)
        await stub.reset(pages: [(Data(), 401), (Data(), 403)])

        let result = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:])
        #expect(await stub.callCount == 2)
        #expect(await stub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(result.statuses.first { $0.source == .cursor }?.message.contains("登入已過期") == true)
    }

    @Test func malformedCountsAreSkippedWithoutLosingValidEvents() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        try CursorFixtures.writeToken(CursorFixtures.jwt(), to: workspace.cursorDirectory)
        var bad = CursorFixtures.event(id: "evt_bad", date: now.addingTimeInterval(-60), input: 5, output: 1)
        bad["tokenUsage"] = ["inputTokens": -5, "outputTokens": 1]
        let good = CursorFixtures.event(id: "evt_good", date: now.addingTimeInterval(-30), input: 5, output: 1)
        await stub.reset(pages: [CursorFixtures.page(events: [bad, good], total: 2)])

        let result = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:])
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.importID == "cursor:evt_good")
        #expect(result.statuses.first { $0.source == .cursor }?.skippedLines == 1)
    }

    @Test func duplicateEventIDsCollapseToTheLargestCounters() async throws {
        let (workspace, stub, importer) = try fixture()
        defer { workspace.remove() }
        try CursorFixtures.writeToken(CursorFixtures.jwt(), to: workspace.cursorDirectory)
        let date = now.addingTimeInterval(-60)
        let small = CursorFixtures.event(id: "evt_same", date: date, input: 10, output: 1)
        let large = CursorFixtures.event(id: "evt_same", date: date, input: 900, output: 30)
        await stub.reset(pages: [CursorFixtures.page(events: [small], total: 2, hasNextPage: true),
                           CursorFixtures.page(events: [large], total: 2, hasNextPage: false)])

        let result = try await importer.scan(settings: cursorSettings(workspace), checkpoints: [:])
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.inputTokens == 900)
        #expect(result.entries.first?.outputTokens == 30)
    }
}

@MainActor
struct CursorStoreTests {
    private let now = Date()

    @Test func storeMergesCursorEventsFeedsSnakeAndSurvivesRestart() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try CursorFixtures.writeToken(CursorFixtures.jwt(), to: workspace.cursorDirectory)
        let first = CursorFixtures.event(id: "evt_1", date: now.addingTimeInterval(-3_600),
                                         input: 100, output: 20, cacheRead: 500, cents: 12.5)
        let second = CursorFixtures.event(id: "evt_2", date: now.addingTimeInterval(-60),
                                          input: 1_000, output: 100, cents: 3)
        let stub = CursorTransportStub(pages: [CursorFixtures.page(events: [first, second], total: 2)])
        let url = workspace.root.appending(path: "app/store.json")
        let fixed = now
        let importer = LocalUsageImporter(cursorTransport: { await stub.send($0) }, now: { fixed })
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin(), usageImporter: importer)
        var settings = LocalSyncSettings()
        settings.codexEnabled = false
        settings.claudeEnabled = false
        settings.opencodeEnabled = false
        settings.cursorEnabled = true
        settings.cursorDirectory = workspace.cursorDirectory.path
        store.updateSyncSettings { $0 = settings }

        await store.syncLocalUsage()
        #expect(store.entries.count == 2)
        #expect(store.snake.growth.totalTokens == 1_720)
        #expect(store.entries.allSatisfy { $0.reportedCost != nil })

        let restartedImporter = LocalUsageImporter(cursorTransport: { await stub.send($0) }, now: { fixed })
        let restarted = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin(),
                                 usageImporter: restartedImporter)
        await restarted.syncLocalUsage()
        #expect(restarted.entries == store.entries)
        #expect(restarted.localSyncState.cursorCheckpoint != nil)

        let imported = try #require(restarted.entries.first { $0.importID == "cursor:evt_2" })
        restarted.deleteEntry(imported)
        restarted.flushPersistence()
        await restarted.syncLocalUsage()
        #expect(restarted.entries.count == 1)

        await stub.reset(pages: [CursorFixtures.page(events: [first, second], total: 2)])
        await restarted.reimportLocalUsage()
        #expect(restarted.entries.count == 2)
    }

    @Test func cursorSourceStaysOffUntilEnabled() async throws {
        let workspace = try UsageFixtures.workspace()
        defer { workspace.remove() }
        try CursorFixtures.writeToken(CursorFixtures.jwt(), to: workspace.cursorDirectory)
        let stub = CursorTransportStub(pages: [])
        let url = workspace.root.appending(path: "app/store.json")
        let fixed = now
        let importer = LocalUsageImporter(cursorTransport: { await stub.send($0) }, now: { fixed })
        let store = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin(), usageImporter: importer)
        store.updateSyncSettings { $0 = workspace.settings }
        await store.syncLocalUsage()
        #expect(store.entries.isEmpty)
        #expect(await stub.callCount == 0)
        #expect(store.syncStatuses.first { $0.source == .cursor }?.state == .disabled)
    }
}
