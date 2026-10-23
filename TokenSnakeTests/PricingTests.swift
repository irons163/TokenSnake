import Foundation
import Testing
@testable import TokenSnake

struct PricingTests {
    @Test func everyProviderHasModels() {
        for provider in AIProvider.allCases {
            #expect(!Pricing.models(for: provider).isEmpty)
            #expect(Pricing.catalogs.contains(where: { $0.provider == provider }))
        }
    }

    @Test func specLookup() {
        #expect(Pricing.spec(provider: .openai, model: "GPT-5") != nil)
        #expect(Pricing.spec(provider: .openai, model: "missing") == nil)
    }

    @Test func costUsesInputOutputAndCache() {
        let entry = TokenEntry(
            provider: .openai,
            model: "GPT-5",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cachedTokens: 200_000
        )
        // $1.00 uncached input + $0.025 cache reads + $10.00 output.
        let expected: Double = 11.025
        #expect(abs(Pricing.cost(for: entry) - expected) < 0.0001)
    }

    @Test func unknownModelHasNoEstimate() {
        let entry = TokenEntry(provider: .openai, model: "nope", inputTokens: 9_999, outputTokens: 9_999)
        #expect(Pricing.estimatedCost(for: entry) == nil)
        #expect(Pricing.costLabel(for: entry) == "費率未收錄")
        #expect(Pricing.cost(for: entry) == 0)
    }

    @Test(arguments: [
        ("gpt-5.5", 0.85, 2.55),
        ("gpt-5.6-sol", 0.66, 2.02),
        ("gpt-5.6-terra", 0.35, 1.04),
        ("gpt-5.6-luna", 0.035, 0.104)
    ])
    func newlyCoveredModelsUseOfficialRates(model: String, shortCost: Double, longCost: Double) throws {
        var entry = TokenEntry(provider: .openai, model: model, inputTokens: 200_000, outputTokens: 10_000,
                               cachedTokens: 100_000, cacheWriteTokens: 20_000)
        let shortEstimate = try #require(Pricing.estimatedCost(for: entry))
        #expect(abs(shortEstimate - shortCost) < 0.000001)
        entry.inputTokens = 300_000
        let longEstimate = try #require(Pricing.estimatedCost(for: entry))
        #expect(abs(longEstimate - longCost) < 0.000001)
        #expect(Pricing.spec(provider: .openai, model: model + "-20261001") == Pricing.spec(provider: .openai, model: model))
    }

    @Test func solAliasAndContextBoundary() throws {
        #expect(Pricing.spec(provider: .openai, model: "gpt-5.6")?.name == "GPT-5.6 Sol")
        let entry = TokenEntry(provider: .openai, model: "gpt-5.6-sol", inputTokens: 272_000, outputTokens: 10_000, cachedTokens: 100_000)
        let estimate = try #require(Pricing.estimatedCost(for: entry))
        #expect(abs(estimate - 0.928) < 0.000001)
    }

    @Test func opus55PricesOrdinaryInputAndBothCacheWriteDurations() throws {
        let entry = TokenEntry(provider: .anthropic, model: "claude-opus-5-5", inputTokens: 1_000_000,
                               outputTokens: 100_000, cachedTokens: 500_000,
                               cacheWriteTokens: 200_000, cacheWrite1hTokens: 50_000)
        // 300k ordinary + 500k cache reads + 150k 5m writes + 50k 1h writes + 100k output.
        let cost = try #require(Pricing.estimatedCost(for: entry))
        #expect(abs(cost - 4.45) < 0.000001)
        #expect(Pricing.spec(provider: .anthropic, model: "claude-opus-5-5-20260922")?.name == "Claude Opus 5.5")
        #expect(Pricing.spec(provider: .anthropic, model: "Claude Opus 5.5")?.cachedPerMillion == 0.20)
        #expect(Pricing.spec(provider: .anthropic, model: "claude-opus-4-8")?.inputPerMillion == 5.00)
        #expect(Pricing.spec(provider: .openai, model: "claude-opus-5-5") == nil)
    }

    @Test func importedOpus55HistoryHasACompleteGroupEstimate() throws {
        let entries = [
            TokenEntry(provider: .anthropic, model: "claude-opus-5-5", inputTokens: 200_000,
                       outputTokens: 10_000, cachedTokens: 100_000, source: .claudeCode),
            TokenEntry(provider: .anthropic, model: "claude-opus-5-5", inputTokens: 300_000,
                       outputTokens: 10_000, cachedTokens: 100_000, source: .claudeCode)
        ]
        let group = try #require(ModelUsageGroup.groups(from: entries).first)
        #expect(group.totalTokens == 520_000)
        #expect(group.unpricedCount == 0)
        #expect(abs(group.knownCost - 1.64) < 0.000001)
        #expect(group.costLabel == "$1.64 估算")
    }

    @Test func includedPlansAreFree() {
        let cursor = TokenEntry(provider: .cursor, model: "Cursor 包含額度", inputTokens: 80_000, outputTokens: 20_000)
        let copilot = TokenEntry(provider: .copilot, model: "Copilot 包含額度", inputTokens: 80_000, outputTokens: 20_000)
        let custom = TokenEntry(provider: .custom, model: "自訂模型", inputTokens: 80_000, outputTokens: 20_000)
        #expect(Pricing.cost(for: cursor) == 0)
        #expect(Pricing.cost(for: copilot) == 0)
        #expect(Pricing.cost(for: custom) == 0)
    }

    @Test func negativeTokensDoNotGoNegative() {
        var entry = TokenEntry(provider: .google, model: "Gemini 2.5 Flash", inputTokens: 100, outputTokens: 100)
        entry.cachedTokens = 500
        entry.outputTokens = -10
        #expect(Pricing.cost(for: entry) >= 0)
    }

    @Test func templatesHaveUniqueNames() {
        let names = Pricing.subscriptionTemplates.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Pricing.subscriptionTemplates.count == 7)
    }
}
