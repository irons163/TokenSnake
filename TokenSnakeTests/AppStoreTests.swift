import Foundation
import Testing
@testable import TokenSnake

@Suite
@MainActor
struct AppStoreTests {
    @Test func logsAndUndoesSession() {
        let (store, _, _) = StoreHarness.make()
        store.logSession(provider: .openai, model: "GPT-5", size: .medium)
        #expect(store.entries.count == 1)
        #expect(store.settings.lastProvider == .openai)
        #expect(store.settings.lastModel == "GPT-5")
        #expect(store.todayEntries.count == 1)
        #expect(store.insights.todayTokens == SessionSize.medium.inputTokens + SessionSize.medium.outputTokens)
        store.undoLastEntry()
        #expect(store.entries.isEmpty)
        store.undoLastEntry()
        #expect(store.entries.isEmpty)
    }

    @Test func deleteEntryCorrectsGrowth() {
        let (store, _, _) = StoreHarness.make()
        let entry = StoreHarness.cheapEntry()
        store.addEntry(entry)
        #expect(store.snake.todayFedCount == 1)
        #expect(store.snake.growth.totalTokens == entry.totalTokens)
        store.deleteEntry(entry)
        #expect(store.snake.growth.totalTokens == 0)
        #expect(store.snake.mood == .sleeping)
    }

    @Test func insightsCoverMonthAndSparkline() {
        let (store, _, _) = StoreHarness.make()
        let calendar = Calendar.current
        store.addEntry(StoreHarness.cheapEntry())
        store.addEntry(TokenEntry(
            createdAt: calendar.date(byAdding: .day, value: -2, to: .now)!,
            provider: .anthropic,
            model: "Claude Sonnet 4",
            inputTokens: 4_000,
            outputTokens: 1_000
        ))
        store.addEntry(TokenEntry(
            createdAt: calendar.date(byAdding: .day, value: -40, to: .now)!,
            provider: .google,
            model: "Gemini 2.5 Flash",
            inputTokens: 8_000,
            outputTokens: 2_000
        ))
        #expect(store.insights.last14Days.count == 14)
        #expect(store.insights.todayTokens > 0)
        #expect(store.monthEntries.count == 2)
        #expect(store.providerBreakdown.first?.0 != nil)
        #expect(store.insights.outputRatio > 0)
        #expect(store.insights.topProvider != nil)
        #expect(store.insights.topProviderShare > 0)
    }

    @Test func emptyInsights() {
        let (store, _, _) = StoreHarness.make()
        #expect(store.insights.todayTokens == 0)
        #expect(store.insights.outputRatio == 0)
        #expect(store.insights.topProvider == nil)
        #expect(store.providerBreakdown.isEmpty)
        #expect(store.snake.mood == .sleeping)
    }

    @Test func budgetDoesNotLimitFeeding() {
        let (store, _, _) = StoreHarness.make()
        store.addEntry(StoreHarness.expensiveEntry())
        let snapshot = store.snake
        #expect(store.insights.todayCost > store.settings.dailyCostBudget)
        #expect(snapshot.mood == .growing)
        #expect(store.budgetProgress > 1)
        store.updateSettings { $0.dailyCostBudget = 0.01; $0.dailyTokenBudget = 1 }
        #expect(store.snake == snapshot)
    }

    @Test func budgetProgressZeroWhenBudgetCleared() {
        let (store, _, _) = StoreHarness.make()
        store.updateSettings { $0.dailyCostBudget = 0 }
        store.addEntry(StoreHarness.cheapEntry())
        #expect(store.budgetProgress == 0)
    }

    @Test func historicalMealsRemainOnRestDays() {
        let (store, _, _) = StoreHarness.make()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: store.currentDay)!
        store.addEntry(StoreHarness.cheapEntry(createdAt: yesterday))
        #expect(store.snake.mood == .resting)
        #expect(store.snake.growth.totalTokens == 1_200)
        #expect(store.snake.todayFedCount == 0)
        store.addEntry(StoreHarness.cheapEntry())
        #expect(store.snake.mood == .growing)
        #expect(store.snake.growth.totalTokens == 2_400)
        #expect(store.snake.todayFedCount == 1)
    }

    @Test func largeUsageEvolvesWithoutCheckIn() {
        let (store, _, _) = StoreHarness.make()
        store.addEntry(TokenEntry(provider: .openai, model: "unpriced", inputTokens: 2_500_000_000, outputTokens: 0))
        #expect(store.snake.growth.level == 51)
        #expect(store.snake.mood == .legendary)
        #expect(store.snake.growth.bodySegments > SnakeGrowth(totalTokens: 0).bodySegments)
        #expect(store.days.isEmpty)
    }

    @Test func legacyCheckInsCannotFeedSnake() {
        let (store, url, _) = StoreHarness.make()
        store.days = [HabitDay(day: store.currentDay, completedKinds: HabitKind.allCases, checkedIn: true)]
        #expect(store.snake.mood == .sleeping)
        #expect(store.snake.growth.totalTokens == 0)
        store.flushPersistence()
        let reloaded = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(reloaded.days == store.days)
        #expect(reloaded.snake.growth.totalTokens == 0)
    }

    @Test func subscriptionsCRUD() {
        let (store, _, _) = StoreHarness.make()
        #expect(store.addTemplate(Pricing.subscriptionTemplates[2]))
        #expect(!store.addTemplate(Pricing.subscriptionTemplates[2]))
        #expect(store.subscriptions.count == 1)
        var account = store.subscriptions[0]
        account.planName = "Pro Plus"
        store.upsertSubscription(account)
        #expect(store.subscriptions[0].planName == "Pro Plus")
        store.adjustQuota(for: account, delta: 10)
        #expect(store.subscriptions[0].quotaUsed == 10)
        store.adjustQuota(for: account, delta: -50)
        #expect(store.subscriptions[0].quotaUsed == 0)
        store.adjustQuota(for: SubscriptionAccount(name: "missing", provider: .custom, planName: "x", monthlyPrice: 0), delta: 1)
        store.deleteSubscription(store.subscriptions[0])
        #expect(store.subscriptions.isEmpty)
    }

    @Test func insertNewSubscriptionWhenUnknownID() {
        let (store, _, _) = StoreHarness.make()
        let account = SubscriptionAccount(name: "自訂", provider: .custom, planName: "自訂", monthlyPrice: 5)
        store.upsertSubscription(account)
        #expect(store.subscriptions.count == 1)
    }

    @Test func menuBarTextModes() {
        let (store, _, _) = StoreHarness.make()
        store.updateSettings { $0.menuBarDisplay = .todayTokens }
        #expect(store.menuBarText == "0")
        store.addEntry(StoreHarness.cheapEntry())
        store.updateSettings { $0.menuBarDisplay = .todayCost }
        #expect(store.menuBarText == Formatters.currency(store.insights.todayCost))
        store.updateSettings { $0.menuBarDisplay = .monthCost }
        #expect(store.menuBarText == Formatters.currency(store.insights.monthCost))
        store.updateSettings { $0.menuBarDisplay = .nextRenewal }
        #expect(store.menuBarText == "—")
        #expect(store.addTemplate(Pricing.subscriptionTemplates[2]))
        store.updateSettings { $0.menuBarDisplay = .nextRenewal }
        #expect(store.menuBarText.hasSuffix("天"))
        store.updateSettings { $0.menuBarDisplay = .snake }
        store.addEntry(StoreHarness.expensiveEntry())
        #expect(store.menuBarText == "Lv.1")
        store.resetAll()
        store.updateSettings { $0.menuBarDisplay = .snake }
        #expect(store.menuBarText == "蛋")
        store.days = [
            HabitDay(
                day: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!,
                completedKinds: HabitKind.allCases,
                checkedIn: true
            )
        ]
        #expect(store.menuBarText == "蛋")
    }

    @Test func heatmapUsesActualTokens() {
        let (store, _, _) = StoreHarness.make()
        let today = store.currentDay
        #expect(store.heatmapValue(for: today) == 0)
        store.addEntry(StoreHarness.cheapEntry())
        #expect(store.heatmapValue(for: today) == 0.25)
        store.habits = []
        store.days = [HabitDay(day: today, completedKinds: HabitKind.allCases, checkedIn: true)]
        #expect(store.heatmapValue(for: today) == 0.25)
        store.addEntry(TokenEntry(provider: .openai, model: "GPT-5", inputTokens: 10_000_000, outputTokens: 0))
        #expect(store.heatmapValue(for: today) == 0.75)
    }

    @Test func launchAtLoginSuccessAndFailure() {
        let mock = MockLaunchAtLogin()
        let (store, _, service) = StoreHarness.make(launch: mock)
        store.setLaunchAtLogin(true)
        #expect(service.isEnabled)
        #expect(store.settings.launchAtLogin)
        store.setLaunchAtLogin(false)
        #expect(!service.isEnabled)

        let throwing = MockLaunchAtLogin(isEnabled: false, shouldThrow: true)
        let (failing, _, _) = StoreHarness.make(launch: throwing)
        failing.setLaunchAtLogin(true)
        #expect(failing.settings.launchAtLogin == false)
    }

    @Test func persistReloadAndCorruptFile() throws {
        let (store, url, _) = StoreHarness.make()
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        let reloaded = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin(isEnabled: true))
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.settings.launchAtLogin)

        try Data("not-json".utf8).write(to: url)
        let corrupt = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(corrupt.entries.isEmpty)

        let emptyHabits = PersistedStore(entries: [], subscriptions: [], habits: [], days: [], settings: .default)
        try JSONEncoder().encode(emptyHabits).write(to: url)
        let restoredHabits = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(restoredHabits.habits.count == 3)
    }

    @Test func persistSoonWritesAfterDelay() async throws {
        let (store, url, _) = StoreHarness.make()
        store.addEntry(StoreHarness.cheapEntry())
        try await Task.sleep(for: .milliseconds(350))
        let reloaded = AppStore(fileURL: url, launchAtLogin: MockLaunchAtLogin())
        #expect(reloaded.entries.count == 1)
    }

    @Test func persistErrorDoesNotCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ts-dir-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppStore(fileURL: dir, launchAtLogin: MockLaunchAtLogin())
        store.addEntry(StoreHarness.cheapEntry())
        store.flushPersistence()
        #expect(store.entries.count == 1)
    }

    @Test func demoAndReset() {
        let (store, _, _) = StoreHarness.make()
        store.loadDemoData()
        #expect(!store.entries.isEmpty)
        #expect(store.subscriptions.count == 3)
        #expect(store.days.isEmpty)
        store.resetAll()
        #expect(store.entries.isEmpty)
        #expect(store.subscriptions.isEmpty)
        #expect(store.habits.count == 3)
        #expect(store.settings.snakeName == "小蛇")
    }

    @Test func todayEntriesNewestFirst() {
        let (store, _, _) = StoreHarness.make()
        let older = TokenEntry(createdAt: Date().addingTimeInterval(-60), provider: .cursor, model: "Cursor 包含額度", inputTokens: 1, outputTokens: 1)
        let newer = TokenEntry(createdAt: Date(), provider: .openai, model: "GPT-5", inputTokens: 1, outputTokens: 1)
        store.addEntry(older)
        store.addEntry(newer)
        #expect(store.todayEntries.first?.id == newer.id)
    }

    @Test func crossingMidnightPreservesGrowth() {
        let (store, _, _) = StoreHarness.make()
        store.addEntry(StoreHarness.cheapEntry())
        let grown = store.snake.growth
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.currentDay)!
        store.refreshClock(now: tomorrow)
        #expect(store.snake.todayTokens == 0)
        #expect(store.snake.todayFedCount == 0)
        #expect(store.snake.growth == grown)
        #expect(store.snake.mood == .resting)
    }

}
