import Foundation

struct ModelUsageGroup: Identifiable {
    struct ID: Hashable {
        var provider: AIProvider
        var model: String
    }

    var id: ID
    var entries: [TokenEntry]
    var totalTokens: Int
    var knownCost: Double
    var unpricedCount: Int

    var latestAt: Date { entries[0].createdAt }

    var costLabel: String {
        if unpricedCount == entries.count { return Pricing.missingRateLabel }
        let cost = Formatters.currency(knownCost)
        return unpricedCount > 0 ? "已知 \(cost) · \(unpricedCount) 筆待補費率" : "\(cost) 估算"
    }

    static func groups(from entries: [TokenEntry]) -> [ModelUsageGroup] {
        // Group the full history before paginating details. Sources share a group,
        // but different providers and exact model versions keep their identities.
        Dictionary(grouping: entries) { ID(provider: $0.provider, model: $0.model) }
            .map { id, entries in
                let sorted = entries.sorted {
                    $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
                }
                var tokens = 0
                var cost = 0.0
                var unpriced = 0
                for entry in sorted {
                    tokens += entry.totalTokens
                    // Price each response separately to preserve cache and context rates.
                    if let estimate = Pricing.estimatedCost(for: entry) { cost += estimate }
                    else { unpriced += 1 }
                }
                return ModelUsageGroup(id: id, entries: sorted, totalTokens: tokens, knownCost: cost, unpricedCount: unpriced)
            }
            .sorted {
                if $0.latestAt != $1.latestAt { return $0.latestAt > $1.latestAt }
                if $0.id.model != $1.id.model { return $0.id.model < $1.id.model }
                return $0.id.provider.rawValue < $1.id.provider.rawValue
            }
    }
}
