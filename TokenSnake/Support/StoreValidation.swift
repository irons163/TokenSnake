import Foundation

extension PersistedStore {
    /// Apply the same trust boundary to startup files and user-selected backups.
    func validate() throws {
        let limit = 1_000_000_000_000
        func dateIsValid(_ date: Date) -> Bool {
            date.timeIntervalSinceReferenceDate.isFinite && date >= .distantPast && date <= .distantFuture
        }
        func entryIsValid(_ entry: TokenEntry) -> Bool {
            let write = entry.cacheWriteTokens ?? 0
            let longWrite = entry.cacheWrite1hTokens ?? 0
            return (0...limit).contains(entry.inputTokens) && (0...limit).contains(entry.outputTokens)
                && (0...entry.inputTokens).contains(entry.cachedTokens)
                && (0...(entry.inputTokens - entry.cachedTokens)).contains(write)
                && (0...write).contains(longWrite) && dateIsValid(entry.createdAt)
        }
        func countersAreValid(_ counters: UsageCounters) -> Bool {
            [counters.input, counters.output, counters.cached, counters.write].allSatisfy { (0...limit).contains($0) }
        }
        guard entries.allSatisfy(entryIsValid),
              settings.dailyCostBudget.isFinite, (0...Double(limit)).contains(settings.dailyCostBudget),
              (0...limit).contains(settings.dailyTokenBudget),
              subscriptions.allSatisfy({
                  $0.monthlyPrice.isFinite && (0...Double(limit)).contains($0.monthlyPrice)
                      && (0...limit).contains($0.quotaUsed) && (0...limit).contains($0.quotaLimit)
                      && dateIsValid($0.cycleAnchor) && ($0.quotaCycleStart.map(dateIsValid) ?? true)
              }), days.allSatisfy({ dateIsValid($0.day) }),
              localSyncState?.lastSyncAt.map(dateIsValid) ?? true else { throw CocoaError(.fileReadCorruptFile) }
        guard Set(entries.map(\.id)).count == entries.count,
              Set(entries.compactMap(\.importID)).count == entries.compactMap(\.importID).count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var total = 0
        for entry in entries {
            let next = total.addingReportingOverflow(entry.totalTokens)
            guard !next.overflow else { throw CocoaError(.fileReadCorruptFile) }
            total = next.partialValue
        }
        for checkpoint in localSyncState?.checkpoints.values ?? Dictionary<String, UsageFileCheckpoint>().values {
            guard checkpoint.offset <= checkpoint.size, dateIsValid(checkpoint.modifiedAt),
                  (0...1_000_000_000).contains(checkpoint.context.counterGeneration),
                  checkpoint.context.total.map(countersAreValid) ?? true,
                  (checkpoint.context.pendingCodexEntries?.count ?? 0) <= 16,
                  checkpoint.context.pendingCodexEntries?.allSatisfy(entryIsValid) ?? true else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
}
