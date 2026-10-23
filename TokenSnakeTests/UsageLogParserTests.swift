import Foundation
import Testing
@testable import TokenSnake

struct UsageLogParserTests {
    @Test func codexModernAndLegacyMirrorCountOnce() throws {
        var context = UsageParserContext()
        var entries: [TokenEntry] = []
        for record in [UsageFixtures.metadata(), UsageFixtures.model(), UsageFixtures.modern(),
                       UsageFixtures.legacy(input: 1_000, cached: 600, output: 100)] {
            if let entry = try UsageLogParser.parse(UsageFixtures.line(record), source: .codex, context: &context) { entries.append(entry) }
        }
        let entry = try #require(entries.first)
        #expect(Set(entries.map(\.id)).count == 1)
        #expect(entries.last?.importAliases?.isEmpty == false)
        #expect(entry.inputTokens == 1_000)
        #expect(entry.cachedTokens == 600)
        #expect(entry.outputTokens == 100) // Reasoning is already included in output.
        #expect(entry.model == "gpt-5")
        #expect(entry.source == .codex)
        #expect(entry.note.isEmpty)
        var secondContext = UsageParserContext()
        let same = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.modern()), source: .codex, context: &secondContext)
        #expect(same?.id == entry.id)
    }

    @Test func codexLegacyUsesDeltasAndIgnoresRateLimitRepeats() throws {
        var context = UsageParserContext(sessionID: "legacy", model: "gpt-5")
        let first = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 100, cached: 10, output: 20)), source: .codex, context: &context)
        let duplicate = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 100, cached: 10, output: 20)), source: .codex, context: &context)
        let second = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 250, cached: 80, output: 50)), source: .codex, context: &context)
        #expect(duplicate == nil)
        #expect(first?.totalTokens == 120)
        #expect(second?.inputTokens == 150)
        #expect(second?.cachedTokens == 70)
        #expect(second?.outputTokens == 30)
        #expect(first?.importID != second?.importID)
    }

    @Test func compactionResetDoesNotDuplicateModernUsage() throws {
        var context = UsageParserContext(sessionID: "session-1", model: "gpt-5")
        let modern = try #require(UsageLogParser.parse(UsageFixtures.line(UsageFixtures.modern(totalInput: 100_000, totalCached: 60_000, totalOutput: 10_000)), source: .codex, context: &context))
        let mirror = try #require(UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 1_000, cached: 600, output: 100)), source: .codex, context: &context))
        #expect(modern.importID == mirror.importID)
        #expect(mirror.inputTokens == 1_000)
        #expect(mirror.importAliases?.count == 1)
    }

    @Test func counterResetHasSeparateIdentity() throws {
        var context = UsageParserContext(sessionID: "reset")
        let first = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 100, cached: 0, output: 20)), source: .codex, context: &context)
        _ = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 20, cached: 0, output: 5)), source: .codex, context: &context)
        let later = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.legacy(input: 100, cached: 0, output: 20)), source: .codex, context: &context)
        #expect(first?.importID != later?.importID)
        #expect(later?.inputTokens == 80)
    }

    @Test func claudeNormalizesAllInputAndCacheDurations() throws {
        var context = UsageParserContext()
        let entry = try #require(UsageLogParser.parse(UsageFixtures.line(UsageFixtures.claude()), source: .claudeCode, context: &context))
        #expect(entry.inputTokens == 640)
        #expect(entry.cachedTokens == 500)
        #expect(entry.cacheWriteTokens == 40)
        #expect(entry.cacheWrite1hTokens == 25)
        #expect(entry.outputTokens == 60)
        #expect(entry.provider == .anthropic)
        #expect(entry.source == .claudeCode)
        #expect(!String(decoding: try JSONEncoder().encode(entry), as: UTF8.self).contains("PRIVATE FIXTURE"))
    }

    @Test func claudeRepeatedBlocksShareIdentity() throws {
        var context = UsageParserContext()
        let initial = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.claude(output: 1)), source: .claudeCode, context: &context)
        let final = try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.claude(output: 100)), source: .claudeCode, context: &context)
        #expect(initial?.importID == final?.importID)
        #expect(initial?.id == final?.id)
    }

    @Test func irrelevantSyntheticAndMissingUsageAreIgnored() throws {
        var context = UsageParserContext()
        for record: [String: Any] in [
            ["type": "response_item", "payload": ["type": "message", "usage": ["input_tokens": 100]]],
            ["type": "event_msg", "payload": ["type": "token_count", "info": NSNull()]],
            ["type": "assistant", "message": ["id": "synthetic", "model": "<synthetic>", "usage": ["input_tokens": 100]]]
        ] {
            #expect(try UsageLogParser.parse(UsageFixtures.line(record), source: .codex, context: &context) == nil)
            #expect(try UsageLogParser.parse(UsageFixtures.line(record), source: .claudeCode, context: &context) == nil)
        }
    }

    @Test(arguments: [-1, 1_000_000_000_001])
    func invalidTokenCountsAreRejected(_ count: Int) throws {
        var context = UsageParserContext()
        #expect(throws: UsageLogParser.ParseError.self) {
            try UsageLogParser.parse(UsageFixtures.line(UsageFixtures.modern(input: count)), source: .codex, context: &context)
        }
    }

    @Test func knownAliasesAndUnknownPrices() throws {
        #expect(Pricing.spec(provider: .openai, model: "gpt-5-codex")?.name == "GPT-5")
        #expect(Pricing.spec(provider: .openai, model: "gpt-5-20250807")?.name == "GPT-5")
        #expect(Pricing.spec(provider: .openai, model: "gpt-5.1") == nil)
        #expect(Pricing.spec(provider: .anthropic, model: "claude-sonnet-4-20250514")?.name == "Claude Sonnet 4")
        let unknown = TokenEntry(provider: .openai, model: "future-model", inputTokens: 100, outputTokens: 100)
        #expect(Pricing.estimatedCost(for: unknown) == nil)
        #expect(Pricing.costLabel(for: unknown) == "費率未收錄")
    }

    @Test func cacheWritesUseTheirOwnRates() {
        let entry = TokenEntry(provider: .anthropic, model: "Claude Sonnet 4", inputTokens: 1_000_000,
                               outputTokens: 100_000, cachedTokens: 500_000, cacheWriteTokens: 200_000, cacheWrite1hTokens: 50_000)
        // $0.90 input + $0.15 reads + $0.5625 short writes + $0.30 long writes + $1.50 output.
        let expected: Double = 3.4125
        #expect(abs((Pricing.estimatedCost(for: entry) ?? 0) - expected) < 0.000001)
    }

    @Test func solCacheWriteAndLongContextRates() {
        let entry = TokenEntry(provider: .openai, model: "gpt-6.1-sol", inputTokens: 300_000,
                               outputTokens: 10_000, cachedTokens: 100_000, cacheWriteTokens: 50_000)
        // Long-context input/cache total $0.87, plus $0.15 output.
        let expected: Double = 1.02
        #expect(abs((Pricing.estimatedCost(for: entry) ?? 0) - expected) < 0.000001)
    }
}
