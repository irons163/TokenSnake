import Foundation
import Observation
import Darwin

@Observable
@MainActor
final class AppStore {
    var entries: [TokenEntry] = []
    var subscriptions: [SubscriptionAccount] = []
    // Preserve legacy habit metadata when round-tripping older backups.
    // Snake growth is derived only from deduplicated token entries.
    var habits: [HabitDefinition] = PersistedStore.empty.habits
    var days: [HabitDay] = []
    var settings: AppSettings = .default
    private(set) var localSyncState = LocalSyncState()
    private(set) var syncStatuses: [UsageSourceStatus] = []
    private(set) var isSyncing = false
    private(set) var lastSyncInserted = 0
    private(set) var lastSyncUpdated = 0
    private(set) var persistenceError: String?
    private(set) var storageWarning: String?
    private(set) var currentDay = Calendar.current.startOfDay(for: .now)

    private let fileURL: URL
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let usageImporter: LocalUsageImporter
    private var saveTask: Task<Void, Never>?
    private var syncGeneration = 0
    private var canWriteStore = true

    init(
        fileURL: URL? = nil,
        launchAtLogin: any LaunchAtLoginServicing = SystemLaunchAtLogin(),
        usageImporter: LocalUsageImporter = LocalUsageImporter()
    ) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let folder = appSupport.appending(path: "TokenSnake", directoryHint: .isDirectory)
        self.fileURL = fileURL ?? folder.appending(path: "store.json")
        try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if fileURL == nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        self.launchAtLoginService = launchAtLogin
        self.usageImporter = usageImporter
        load()
        settings.launchAtLogin = launchAtLoginService.isEnabled
        refreshSubscriptionCycles()
        refreshClock()
    }

    func flushPersistence() {
        saveTask?.cancel()
        saveTask = nil
        persistNow()
    }

    var todayEntries: [TokenEntry] {
        let start = currentDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .distantFuture
        return entries.filter { $0.createdAt >= start && $0.createdAt < end }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
    }

    var monthEntries: [TokenEntry] {
        let start = Calendar.current.startOfMonth(for: currentDay)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
        return entries.filter { $0.createdAt >= start && $0.createdAt < end }
    }

    var insights: UsageInsights {
        let today = todayEntries
        let month = monthEntries
        let todayTokens = today.reduce(0) { $0 + $1.totalTokens }
        let monthTokens = month.reduce(0) { $0 + $1.totalTokens }
        let todayCost = today.reduce(0.0) { $0 + Pricing.cost(for: $1) }
        let monthCost = month.reduce(0.0) { $0 + Pricing.cost(for: $1) }
        let monthInput = month.reduce(0) { $0 + $1.inputTokens }
        let monthOutput = month.reduce(0) { $0 + $1.outputTokens }
        let outputRatio = monthInput + monthOutput == 0 ? 0 : Double(monthOutput) / Double(monthInput + monthOutput)

        var counts: [AIProvider: Int] = [:]
        for entry in month { counts[entry.provider, default: 0] += entry.totalTokens }
        let top = counts.max { $0.value < $1.value }
        let share = (top == nil || monthTokens == 0) ? 0 : Double(top!.value) / Double(monthTokens)

        let calendar = Calendar.current
        let last14: [Int] = (0..<14).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) ?? .now
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return entries.filter { $0.createdAt >= day && $0.createdAt < next }.reduce(0) { $0 + $1.totalTokens }
        }

        return UsageInsights(
            todayTokens: todayTokens,
            todayCost: todayCost,
            monthTokens: monthTokens,
            monthCost: monthCost,
            outputRatio: outputRatio,
            topProvider: top?.key,
            topProviderShare: share,
            last14Days: last14
        )
    }

    var providerBreakdown: [(AIProvider, Int, Double)] {
        var map: [AIProvider: (Int, Double)] = [:]
        for entry in monthEntries {
            var current = map[entry.provider] ?? (0, 0)
            current.0 += entry.totalTokens
            current.1 += Pricing.cost(for: entry)
            map[entry.provider] = current
        }
        return map
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1 > $1.1 }
    }

    var snake: SnakeSnapshot {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: currentDay) ?? .distantFuture
        let meals = entries.filter { $0.totalTokens > 0 && $0.createdAt < end }
        let today = meals.filter { $0.createdAt >= currentDay }
        let total = meals.reduce(0) { total, entry in
            let result = total.addingReportingOverflow(entry.totalTokens)
            return result.overflow ? Int.max : result.partialValue
        }
        return SnakeSnapshot(
            name: settings.snakeName,
            growth: SnakeGrowth(totalTokens: total),
            todayTokens: today.reduce(0) { $0 + $1.totalTokens },
            todayFedCount: today.count,
            latestMealTokens: meals.max { $0.createdAt < $1.createdAt }?.totalTokens ?? 0
        )
    }

    var dailyTokenTotals: [Date: Int] {
        var totals: [Date: Int] = [:]
        for entry in entries where entry.totalTokens > 0 {
            let day = Calendar.current.startOfDay(for: entry.createdAt)
            totals[day, default: 0] += entry.totalTokens
        }
        return totals
    }

    var menuBarText: String {
        switch settings.menuBarDisplay {
        case .snake:
            let snapshot = snake
            return snapshot.growth.totalTokens == 0 ? "蛋" : "Lv.\(snapshot.growth.level)"
        case .todayTokens:
            return Formatters.compactTokens(insights.todayTokens)
        case .todayCost:
            return unpricedTodayCount > 0 ? "\(Formatters.currency(insights.todayCost))+" : Formatters.currency(insights.todayCost)
        case .monthCost:
            return unpricedMonthCount > 0 ? "\(Formatters.currency(insights.monthCost))+" : Formatters.currency(insights.monthCost)
        case .nextRenewal:
            if let next = subscriptions.filter(\.isActive).min(by: { $0.daysRemaining() < $1.daysRemaining() }) {
                return "\(next.daysRemaining())天"
            }
            return "—"
        }
    }

    var budgetProgress: Double {
        guard settings.dailyCostBudget > 0 else { return 0 }
        return insights.todayCost / settings.dailyCostBudget
    }

    func addEntry(_ entry: TokenEntry) {
        entries.insert(entry, at: 0)
        entries.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        settings.lastProvider = entry.provider
        settings.lastModel = entry.model
        refreshClock()
        persistSoon()
    }

    @discardableResult
    func logSession(provider: AIProvider, model: String, size: SessionSize) -> UUID {
        let entry = TokenEntry(
                provider: provider,
                model: model,
                inputTokens: size.inputTokens,
                outputTokens: size.outputTokens
            )
        addEntry(entry)
        return entry.id
    }

    func undoLastEntry() {
        guard let first = entries.first(where: { $0.source == nil }) else { return }
        deleteEntry(first)
    }

    func deleteEntry(_ entry: TokenEntry) {
        if let importID = entry.importID {
            localSyncState.ignoredImportIDs.formUnion([importID] + (entry.importAliases ?? []))
        }
        entries.removeAll { $0.id == entry.id }
        refreshClock()
        persistSoon()
    }

    func upsertSubscription(_ incoming: SubscriptionAccount) {
        var account = incoming
        account.quotaCycleStart = account.cycleStart()
        if let index = subscriptions.firstIndex(where: { $0.id == account.id }) {
            subscriptions[index] = account
        } else {
            subscriptions.insert(account, at: 0)
        }
        persistSoon()
    }

    @discardableResult
    func addTemplate(_ template: SubscriptionAccount) -> Bool {
        if subscriptions.contains(where: { $0.name == template.name }) {
            return false
        }
        var copy = template
        copy.id = UUID()
        copy.cycleAnchor = .now
        copy.quotaCycleStart = copy.cycleStart()
        subscriptions.insert(copy, at: 0)
        persistSoon()
        return true
    }

    func deleteSubscription(_ account: SubscriptionAccount) {
        subscriptions.removeAll { $0.id == account.id }
        persistSoon()
    }

    func adjustQuota(for account: SubscriptionAccount, delta: Int) {
        refreshSubscriptionCycles()
        guard let index = subscriptions.firstIndex(where: { $0.id == account.id }) else { return }
        subscriptions[index].quotaUsed = max(0, subscriptions[index].quotaUsed + delta)
        persistSoon()
    }

    func refreshSubscriptionCycles(now: Date = .now) {
        var changed = false
        for index in subscriptions.indices {
            let cycle = subscriptions[index].cycleStart(now: now)
            if let previous = subscriptions[index].quotaCycleStart, cycle > previous {
                subscriptions[index].quotaUsed = 0
            }
            if subscriptions[index].quotaCycleStart != cycle {
                subscriptions[index].quotaCycleStart = cycle
                changed = true
            }
        }
        if changed { persistSoon() }
    }

    func heatmapValue(for date: Date) -> Double {
        SnakeGrowth.activityValue(tokens: dailyTokenTotals[Calendar.current.startOfDay(for: date)] ?? 0)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        persistSoon()
        do {
            try launchAtLoginService.setEnabled(enabled)
        } catch {
            settings.launchAtLogin = launchAtLoginService.isEnabled
        }
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        refreshClock()
        persistSoon()
    }

    var unpricedTodayCount: Int { todayEntries.filter { Pricing.estimatedCost(for: $0) == nil }.count }
    var unpricedMonthCount: Int { monthEntries.filter { Pricing.estimatedCost(for: $0) == nil }.count }

    func updateSyncSettings(_ mutate: (inout LocalSyncSettings) -> Void) {
        mutate(&settings.localSync)
        syncGeneration += 1
        persistSoon()
    }

    func runAutomaticSync(interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            refreshClock()
            refreshSubscriptionCycles()
            await syncLocalUsage()
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    func refreshClock(now: Date = .now) {
        let day = Calendar.current.startOfDay(for: now)
        if currentDay != day { currentDay = day }
    }

    func syncLocalUsage(force: Bool = false) async {
        guard !isSyncing, force || settings.localSync.enabled else { return }
        isSyncing = true
        defer { isSyncing = false }
        let generation = syncGeneration
        let configuration = settings.localSync
        do {
            let result = try await usageImporter.scan(settings: configuration, checkpoints: localSyncState.checkpoints,
                                                      opencodeCheckpoint: localSyncState.opencodeCheckpoint,
                                                      cursorCheckpoint: localSyncState.cursorCheckpoint,
                                                      forceRemote: force)
            guard !Task.isCancelled, generation == syncGeneration, configuration == settings.localSync else { return }
            mergeImported(result.entries)
            localSyncState.checkpoints = result.checkpoints
            localSyncState.opencodeCheckpoint = result.opencodeCheckpoint
            localSyncState.cursorCheckpoint = result.cursorCheckpoint
            localSyncState.lastSyncAt = .now
            syncStatuses = result.statuses
            refreshClock()
            // Entries and cursors are committed together, so a restart cannot skip uncommitted usage.
            flushPersistence()
        } catch is CancellationError { return }
        catch { storageWarning = "同步未完成，稍後會重試。" }
    }

    private func mergeImported(_ incomingEntries: [TokenEntry]) {
        let priorEntries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var imported = Dictionary(entries.compactMap { entry in entry.importID.map { ($0, entry) } },
                                  uniquingKeysWith: { first, _ in first })
        var identityMap: [String: String] = [:]
        for (canonical, entry) in imported {
            for key in [canonical] + (entry.importAliases ?? []) { identityMap[key] = canonical }
        }
        for incoming in incomingEntries {
            guard let key = incoming.importID else { continue }
            var keys = Set([key] + (incoming.importAliases ?? []))
            let matches = Set(keys.compactMap { identityMap[$0] }).sorted()
            let existing = matches.compactMap { imported[$0] }
            for entry in existing {
                if let canonical = entry.importID { keys.formUnion([canonical] + (entry.importAliases ?? [])) }
            }
            for match in matches { imported.removeValue(forKey: match) }
            for identity in keys { identityMap.removeValue(forKey: identity) }
            if !keys.isDisjoint(with: localSyncState.ignoredImportIDs) {
                localSyncState.ignoredImportIDs.formUnion(keys)
                continue
            }
            let canonical = keys.sorted().first { $0.hasPrefix("codex:response:") } ?? existing.first?.importID ?? key
            var merged = existing.first(where: { $0.importID == canonical }) ?? existing.first ?? incoming
            for candidate in existing + [incoming] {
                merged.inputTokens = max(merged.inputTokens, candidate.inputTokens)
                merged.outputTokens = max(merged.outputTokens, candidate.outputTokens)
                merged.cachedTokens = max(merged.cachedTokens, candidate.cachedTokens)
                merged.cacheWriteTokens = max(merged.cacheWriteTokens ?? 0, candidate.cacheWriteTokens ?? 0)
                merged.cacheWrite1hTokens = max(merged.cacheWrite1hTokens ?? 0, candidate.cacheWrite1hTokens ?? 0)
                if let cost = candidate.reportedCost { merged.reportedCost = max(merged.reportedCost ?? 0, cost) }
                if !candidate.model.contains("未知模型") { merged.model = candidate.model }
                if candidate.importID == canonical { merged.createdAt = candidate.createdAt }
            }
            merged.importID = canonical
            merged.importAliases = keys.subtracting([canonical]).sorted()
            imported[canonical] = merged
            for identity in keys { identityMap[identity] = canonical }
        }
        entries = entries.filter { $0.importID == nil } + Array(imported.values)
        entries.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        lastSyncInserted = entries.filter { priorEntries[$0.id] == nil }.count
        lastSyncUpdated = entries.filter { priorEntries[$0.id] != nil && priorEntries[$0.id] != $0 }.count
    }

    func reimportLocalUsage() async {
        guard !isSyncing else { return }
        localSyncState.checkpoints = [:]
        localSyncState.opencodeCheckpoint = nil
        localSyncState.cursorCheckpoint = nil
        localSyncState.ignoredImportIDs = []
        await syncLocalUsage(force: true)
    }

    func exportData(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writePrivate(encoder.encode(persistedStore), to: url)
    }

    func restoreData(from url: URL) throws {
        var restored = try JSONDecoder().decode(PersistedStore.self, from: readSnapshot(url))
        try restored.validate()
        // Always retain the prior store before replacing it with a user-selected backup.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let prior = fileURL.appendingPathExtension("backup-\(UUID().uuidString).json")
            try writePrivate(readSnapshot(fileURL), to: prior)
        }
        restored.settings.localSync.enabled = false
        restored.settings.launchAtLogin = launchAtLoginService.isEnabled
        try writePrivate(JSONEncoder().encode(restored), to: fileURL)
        saveTask?.cancel()
        syncGeneration += 1
        canWriteStore = true
        apply(restored)
        syncStatuses = []
        persistenceError = nil
        storageWarning = nil
    }

    func loadDemoData() {
        syncGeneration += 1
        settings.localSync.enabled = false
        let calendar = Calendar.current
        let now = Date.now
        entries = (0..<18).compactMap { offset -> TokenEntry? in
            let date = calendar.date(byAdding: .day, value: -offset / 2, to: now) ?? now
            let providers = AIProvider.allCases.filter { $0 != .custom }
            let provider = providers[offset % providers.count]
            let model = Pricing.models(for: provider).first?.name ?? "自訂模型"
            return TokenEntry(
                createdAt: date,
                provider: provider,
                model: model,
                inputTokens: [2_400, 8_200, 18_000, 4_100][offset % 4],
                outputTokens: [800, 2_200, 6_400, 1_500][offset % 4],
                note: offset % 5 == 0 ? "長對話" : ""
            )
        }
        subscriptions = [
            SubscriptionAccount(name: "Cursor Pro", provider: .cursor, planName: "Pro", monthlyPrice: 20, quotaLimit: 500, quotaUsed: 186, quotaUnit: .fastRequests),
            SubscriptionAccount(name: "Claude Pro", provider: .anthropic, planName: "Pro", monthlyPrice: 20, unlimited: true),
            SubscriptionAccount(name: "ChatGPT Plus", provider: .openai, planName: "Plus", monthlyPrice: 20, unlimited: true)
        ]
        days = []
        refreshClock()
        persistSoon()
    }

    func resetAll() {
        syncGeneration += 1
        settings.localSync.enabled = false
        for entry in entries {
            if let key = entry.importID { localSyncState.ignoredImportIDs.formUnion([key] + (entry.importAliases ?? [])) }
        }
        entries = []
        subscriptions = []
        habits = PersistedStore.empty.habits
        days = []
        settings.snakeName = AppSettings.default.snakeName
        syncStatuses = []
        persistSoon()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do { data = try readSnapshot(fileURL) }
        catch {
            storageWarning = "原資料檔無法讀取，請檢查資料目錄權限；原檔會保留。"
            canWriteStore = false
            return
        }
        guard let decoded = try? JSONDecoder().decode(PersistedStore.self, from: data),
              (try? decoded.validate()) != nil else {
            let backup = fileURL.appendingPathExtension("corrupt-\(UUID().uuidString).json")
            if (try? writePrivate(data, to: backup)) != nil {
                storageWarning = "原資料檔無法讀取，已保留損毀檔備份。"
            } else {
                storageWarning = "原資料檔無法讀取，請先備份資料目錄。"
                canWriteStore = false
            }
            return
        }
        apply(decoded)
    }

    private func readSnapshot(_ url: URL) throws -> Data {
        let maximumBytes: UInt64 = 256 * 1_024 * 1_024
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.uint64Value, size <= maximumBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            guard UInt64(data.count) + UInt64(chunk.count) <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            data.append(chunk)
        }
        return data
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appending(path: ".tokensnake-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func apply(_ decoded: PersistedStore) {
        entries = decoded.entries
        subscriptions = decoded.subscriptions
        habits = decoded.habits.isEmpty ? PersistedStore.empty.habits : decoded.habits
        days = decoded.days
        settings = decoded.settings
        localSyncState = decoded.localSyncState ?? LocalSyncState()
    }

    private func persistSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.persistNow()
        }
    }

    private var persistedStore: PersistedStore {
        PersistedStore(
            entries: entries,
            subscriptions: subscriptions,
            habits: habits,
            days: days,
            settings: settings,
            localSyncState: localSyncState
        )
    }

    private func persistNow() {
        guard canWriteStore else {
            persistenceError = "尚未保存：原資料檔無法備份，請先修復資料目錄權限。"
            return
        }
        do {
            let data = try JSONEncoder().encode(persistedStore)
            try writePrivate(data, to: fileURL)
            persistenceError = nil
        } catch {
            persistenceError = "資料尚未儲存，請檢查磁碟空間與資料目錄權限。"
        }
    }
}
