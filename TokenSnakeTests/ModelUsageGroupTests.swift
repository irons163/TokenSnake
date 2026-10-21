import Foundation
import Testing
@testable import TokenSnake

struct ModelUsageGroupTests {
    @Test func groupsSameModelAcrossSourcesAndSortsByLatestUse() throws {
        let older = TokenEntry(createdAt: Date(timeIntervalSince1970: 10), provider: .openai, model: "gpt-6.1-sol", inputTokens: 100, outputTokens: 20, source: .codex)
        let newer = TokenEntry(createdAt: Date(timeIntervalSince1970: 30), provider: .openai, model: "gpt-6.1-sol", inputTokens: 200, outputTokens: 40)
        let other = TokenEntry(createdAt: Date(timeIntervalSince1970: 20), provider: .anthropic, model: "claude-opus-4-8", inputTokens: 300, outputTokens: 60, source: .claudeCode)

        let groups = ModelUsageGroup.groups(from: [older, other, newer])
        #expect(groups.count == 2)
        let group = try #require(groups.first)
        #expect(group.id.model == "gpt-6.1-sol")
        #expect(group.entries.map(\.id) == [newer.id, older.id])
        #expect(group.totalTokens == 360)
        // Filtering a source must change both the details and its group total.
        let filtered = try #require(ModelUsageGroup.groups(from: [older, other, newer].filter { $0.source == .codex }).first)
        #expect(filtered.entries.count == 1)
        #expect(filtered.totalTokens == 120)
    }

    @Test func totalsIncludeFullHistoryAndPriceResponsesIndividually() throws {
        // The group's input exceeds the context threshold, but no response does.
        let entries = (0..<205).map { _ in
            TokenEntry(provider: .openai, model: "gpt-6.1-sol", inputTokens: 10_000, outputTokens: 100, cachedTokens: 8_000)
        }
        let group = try #require(ModelUsageGroup.groups(from: entries).first)
        #expect(group.entries.count == 205)
        #expect(group.totalTokens == 2_070_500)
        #expect(abs(group.knownCost - 1.189) < 0.000001)
        #expect(group.unpricedCount == 0)
        #expect(group.costLabel.contains("估算"))
    }

    @Test func exactVersionsAndProvidersRemainSeparate() {
        let entries = [
            TokenEntry(provider: .openai, model: "gpt-5", inputTokens: 10, outputTokens: 0),
            TokenEntry(provider: .openai, model: "gpt-5-codex", inputTokens: 20, outputTokens: 0),
            TokenEntry(provider: .custom, model: "gpt-5", inputTokens: 30, outputTokens: 0)
        ]
        #expect(ModelUsageGroup.groups(from: entries).count == 3)
    }

    @Test func unknownPricesStayVisibleAndEmptyHistoryHasNoGroups() throws {
        let entry = TokenEntry(provider: .openai, model: "unknown-model", inputTokens: 800, outputTokens: 200)
        let group = try #require(ModelUsageGroup.groups(from: [entry, entry]).first)
        #expect(group.totalTokens == 2_000)
        #expect(group.unpricedCount == 2)
        #expect(group.costLabel == "費率未收錄")
        #expect(ModelUsageGroup.groups(from: []).isEmpty)
    }

    @Test func stableIdentityAndOrderSurviveNewEntriesAndDeletion() throws {
        let date = Date(timeIntervalSince1970: 30)
        let first = TokenEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: date, provider: .openai, model: "gpt-6.1-sol", inputTokens: 100, outputTokens: 0)
        let second = TokenEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: date, provider: .openai, model: "gpt-6.1-sol", inputTokens: 200, outputTokens: 0)
        let before = try #require(ModelUsageGroup.groups(from: [first]).first)
        let after = try #require(ModelUsageGroup.groups(from: [second, first]).first)
        #expect(before.id == after.id)
        #expect(after.entries.map(\.id) == [first.id, second.id])
        let remaining = try #require(ModelUsageGroup.groups(from: after.entries.filter { $0.id != first.id }).first)
        #expect(remaining.id == before.id)
        #expect(remaining.totalTokens == 200)
    }
}
