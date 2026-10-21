import Foundation
import Testing
@testable import TokenSnake

struct ModelsTests {
    @Test func providersExposeIdentity() {
        for provider in AIProvider.allCases {
            #expect(provider.id == provider.rawValue)
            #expect(!provider.displayName.isEmpty)
            #expect(!provider.symbol.isEmpty)
            _ = provider.tint
        }
        #expect(AIProvider.openai.displayName == "OpenAI")
        #expect(AIProvider.custom.displayName == "自訂")
    }

    @Test func quotaUnits() {
        for unit in QuotaUnit.allCases {
            #expect(unit.id == unit.rawValue)
            #expect(!unit.label.isEmpty)
        }
    }

    @Test func menuBarDisplayLabels() {
        for item in MenuBarDisplay.allCases {
            #expect(item.id == item.rawValue)
            #expect(!item.label.isEmpty)
        }
    }

    @Test func habitCopy() {
        for kind in HabitKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.detail.isEmpty)
            #expect(!kind.symbol.isEmpty)
        }
    }

    @Test func snakeMoodCopy() {
        for mood in [SnakeMood.sleeping, .resting, .growing, .legendary] {
            #expect(!mood.label.isEmpty)
            #expect(!mood.symbol.isEmpty)
        }
    }

    @Test func sessionSizes() {
        for size in SessionSize.allCases {
            #expect(size.id == size.rawValue)
            #expect(size.inputTokens > 0)
            #expect(size.outputTokens > 0)
            #expect(size.tokenLabel == Formatters.compactTokens(size.inputTokens + size.outputTokens))
        }
        #expect(SessionSize.short.title == "短")
        #expect(SessionSize.huge.title == "超長")
    }

    @Test func tokenEntryTotals() {
        let entry = TokenEntry(provider: .xai, model: "Grok 4", inputTokens: 10, outputTokens: 7, cachedTokens: 3, note: "n")
        #expect(entry.totalTokens == 17)
        #expect(entry.note == "n")
    }

    @Test func subscriptionQuotaMath() {
        var account = SubscriptionAccount(name: "Cursor Pro", provider: .cursor, planName: "Pro", monthlyPrice: 20, quotaLimit: 100, quotaUsed: 40)
        #expect(account.remaining == 60)
        #expect(abs(account.quotaProgress - 0.4) < 0.0001)

        account.quotaUsed = 200
        #expect(account.remaining == 0)
        #expect(account.quotaProgress == 1)

        account.unlimited = true
        #expect(account.quotaProgress == 0)
        account.unlimited = false
        account.quotaLimit = 0
        #expect(account.quotaProgress == 0)
    }

    @Test func billingCycleWalksForward() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let now = calendar.date(byAdding: .month, value: 3, to: anchor)!
        let account = SubscriptionAccount(
            name: "Plus",
            provider: .openai,
            planName: "Plus",
            monthlyPrice: 20,
            cycleAnchor: anchor,
            unlimited: true
        )
        let end = account.cycleEnd(now: now, calendar: calendar)
        #expect(end > now)
        let days = account.daysRemaining(now: now, calendar: calendar)
        #expect(days >= 0)
        #expect(days < 32)
    }

    @Test func appSettingsDecodeDefaults() throws {
        let data = Data(#"{"snakeName":"Naga"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.snakeName == "Naga")
        #expect(settings.lastProvider == .cursor)
        #expect(settings.dailyCostBudget == 3)
        #expect(settings.menuBarDisplay == .todayTokens)
        #expect(settings.lastModel == "Cursor 包含額度")
    }

    @Test func localSyncSettingsDecodeLegacyFields() throws {
        let data = Data(#"{"enabled":true,"codexEnabled":false,"claudeEnabled":false,"codexDirectory":"/a","claudeDirectory":"/b"}"#.utf8)
        let settings = try JSONDecoder().decode(LocalSyncSettings.self, from: data)
        #expect(!settings.codexEnabled)
        #expect(!settings.claudeEnabled)
        #expect(settings.opencodeEnabled)
        #expect(settings.opencodeDirectory.isEmpty)
        #expect(!settings.cursorEnabled)
        #expect(settings.cursorDirectory.isEmpty)
    }

    @Test func appSettingsRoundTrip() throws {
        let original = AppSettings.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == original)
    }

    @Test func persistedStoreEmptyHabits() {
        #expect(PersistedStore.empty.habits.count == 3)
        #expect(PersistedStore.empty.entries.isEmpty)
    }

    @Test func modelSpecIdentity() {
        let spec = ModelSpec(name: "GPT-5", inputPerMillion: 1, outputPerMillion: 2, cachedPerMillion: 0.1)
        #expect(spec.id == "GPT-5")
    }

    @Test func appTabTitles() {
        #expect(AppTab.tokens.title == "用量")
        #expect(AppTab.snake.title == "小蛇")
    }
}
