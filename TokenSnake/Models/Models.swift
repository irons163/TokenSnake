import SwiftUI

nonisolated enum AIProvider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case openai
    case anthropic
    case google
    case xai
    case cursor
    case copilot
    case perplexity
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google"
        case .xai: "xAI"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .perplexity: "Perplexity"
        case .custom: "自訂"
        }
    }

    var symbol: String {
        switch self {
        case .openai: "sparkle"
        case .anthropic: "leaf.fill"
        case .google: "diamond.fill"
        case .xai: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .perplexity: "magnifyingglass"
        case .custom: "hexagon.fill"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .openai: Color(red: 0.22, green: 0.78, blue: 0.58)
        case .anthropic: Color(red: 0.86, green: 0.48, blue: 0.30)
        case .google: Color(red: 0.38, green: 0.58, blue: 0.98)
        case .xai: Color(red: 0.86, green: 0.88, blue: 0.90)
        case .cursor: Color(red: 0.72, green: 0.56, blue: 1.00)
        case .copilot: Color(red: 0.40, green: 0.72, blue: 1.00)
        case .perplexity: Color(red: 0.18, green: 0.78, blue: 0.82)
        case .custom: Theme.accent
        }
    }
}

enum QuotaUnit: String, Codable, CaseIterable, Identifiable {
    case requests
    case fastRequests
    case messages
    case tokens
    case credits

    var id: String { rawValue }

    var label: String {
        switch self {
        case .requests: "請求"
        case .fastRequests: "Fast 次數"
        case .messages: "訊息"
        case .tokens: "Tokens"
        case .credits: "點數"
        }
    }
}

enum MenuBarDisplay: String, Codable, CaseIterable, Identifiable {
    case snake
    case todayTokens
    case todayCost
    case monthCost
    case nextRenewal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .snake: "小蛇等級"
        case .todayTokens: "今日 tokens"
        case .todayCost: "今日花費"
        case .monthCost: "本月花費"
        case .nextRenewal: "最近續費"
        }
    }
}

nonisolated struct TokenEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var provider: AIProvider
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var note: String
    var source: UsageSource?
    var importID: String?
    var importAliases: [String]?
    var cacheWriteTokens: Int?
    var cacheWrite1hTokens: Int?
    // Source-reported USD cost: Cursor billing data or OpenCode's usage estimate.
    var reportedCost: Double?

    var totalTokens: Int { inputTokens + outputTokens }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        provider: AIProvider,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int = 0,
        note: String = "",
        source: UsageSource? = nil,
        importID: String? = nil,
        importAliases: [String]? = nil,
        cacheWriteTokens: Int? = nil,
        cacheWrite1hTokens: Int? = nil,
        reportedCost: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.inputTokens = min(max(0, inputTokens), Int.max / 16)
        self.outputTokens = min(max(0, outputTokens), Int.max / 16)
        self.cachedTokens = min(max(0, cachedTokens), self.inputTokens)
        self.note = note
        self.source = source
        self.importID = importID
        self.importAliases = importAliases
        self.cacheWriteTokens = cacheWriteTokens.map { min(max(0, $0), self.inputTokens - self.cachedTokens) }
        self.cacheWrite1hTokens = cacheWrite1hTokens.map { min(max(0, $0), self.cacheWriteTokens ?? 0) }
        self.reportedCost = reportedCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

struct SubscriptionAccount: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var provider: AIProvider
    var planName: String
    var monthlyPrice: Double
    var cycleAnchor: Date
    var quotaLimit: Int
    var quotaUsed: Int
    var quotaUnit: QuotaUnit
    var notes: String
    var isActive: Bool
    var unlimited: Bool
    var quotaCycleStart: Date?

    init(
        id: UUID = UUID(),
        name: String,
        provider: AIProvider,
        planName: String,
        monthlyPrice: Double,
        cycleAnchor: Date = .now,
        quotaLimit: Int = 0,
        quotaUsed: Int = 0,
        quotaUnit: QuotaUnit = .requests,
        notes: String = "",
        isActive: Bool = true,
        unlimited: Bool = false,
        quotaCycleStart: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.planName = planName
        self.monthlyPrice = monthlyPrice
        self.cycleAnchor = cycleAnchor
        self.quotaLimit = quotaLimit
        self.quotaUsed = quotaUsed
        self.quotaUnit = quotaUnit
        self.notes = notes
        self.isActive = isActive
        self.unlimited = unlimited
        self.quotaCycleStart = quotaCycleStart
    }

    var quotaProgress: Double {
        guard !unlimited, quotaLimit > 0 else { return 0 }
        return min(1, Double(quotaUsed) / Double(quotaLimit))
    }

    var remaining: Int {
        max(0, quotaLimit - quotaUsed)
    }

    func cycleEnd(now: Date = .now, calendar: Calendar = .current) -> Date {
        var months = max(1, (calendar.dateComponents([.month], from: cycleAnchor, to: now).month ?? 0) + 1)
        var next = calendar.date(byAdding: .month, value: months, to: cycleAnchor) ?? now
        while next <= now {
            months += 1
            guard let later = calendar.date(byAdding: .month, value: months, to: cycleAnchor), later > next else { break }
            next = later
        }
        return next
    }

    func cycleStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        var months = max(0, calendar.dateComponents([.month], from: cycleAnchor, to: now).month ?? 0)
        var start = calendar.date(byAdding: .month, value: months, to: cycleAnchor) ?? cycleAnchor
        if start > now, months > 0 {
            months -= 1
            start = calendar.date(byAdding: .month, value: months, to: cycleAnchor) ?? cycleAnchor
        }
        while let next = calendar.date(byAdding: .month, value: months + 1, to: cycleAnchor), next <= now, next > start {
            months += 1
            start = next
        }
        return start
    }

    func daysRemaining(now: Date = .now, calendar: Calendar = .current) -> Int {
        let end = cycleEnd(now: now, calendar: calendar)
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0)
    }
}

enum HabitKind: String, Codable, CaseIterable, Identifiable {
    case logDaily
    case stayUnderBudget
    case checkIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logDaily: "記錄用量"
        case .stayUnderBudget: "守住預算"
        case .checkIn: "回來看一眼"
        }
    }

    var detail: String {
        switch self {
        case .logDaily: "今天至少記下一筆 token 使用"
        case .stayUnderBudget: "今日花費與 tokens 都在每日預算內"
        case .checkIn: "打開 TokenSnake，餵一下小蛇"
        }
    }

    var symbol: String {
        switch self {
        case .logDaily: "square.and.pencil"
        case .stayUnderBudget: "leaf.circle"
        case .checkIn: "checkmark.circle"
        }
    }
}

struct HabitDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: HabitKind
    var isEnabled: Bool

    init(id: UUID = UUID(), kind: HabitKind, isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

struct HabitDay: Identifiable, Codable, Hashable {
    var id: UUID
    var day: Date
    var completedKinds: [HabitKind]
    var checkedIn: Bool

    init(
        id: UUID = UUID(),
        day: Date,
        completedKinds: [HabitKind] = [],
        checkedIn: Bool = false
    ) {
        self.id = id
        self.day = day
        self.completedKinds = completedKinds
        self.checkedIn = checkedIn
    }
}

enum SessionSize: String, CaseIterable, Identifiable {
    case short
    case medium
    case long
    case huge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "短"
        case .medium: "中"
        case .long: "長"
        case .huge: "超長"
        }
    }

    var tokenLabel: String {
        Formatters.compactTokens(inputTokens + outputTokens)
    }

    var inputTokens: Int {
        switch self {
        case .short: 1_800
        case .medium: 6_000
        case .long: 24_000
        case .huge: 80_000
        }
    }

    var outputTokens: Int {
        switch self {
        case .short: 500
        case .medium: 1_800
        case .long: 8_000
        case .huge: 20_000
        }
    }
}

struct AppSettings: Codable, Hashable {
    var snakeName: String
    var dailyCostBudget: Double
    var dailyTokenBudget: Int
    var menuBarDisplay: MenuBarDisplay
    var launchAtLogin: Bool
    var eveningNudge: Bool
    var lastProvider: AIProvider
    var lastModel: String
    var localSync: LocalSyncSettings

    static let `default` = AppSettings(
        snakeName: "小蛇",
        dailyCostBudget: 3.0,
        dailyTokenBudget: 200_000,
        menuBarDisplay: .todayTokens,
        launchAtLogin: false,
        eveningNudge: false,
        lastProvider: .cursor,
        lastModel: "Cursor 包含額度"
    )

    init(
        snakeName: String,
        dailyCostBudget: Double,
        dailyTokenBudget: Int,
        menuBarDisplay: MenuBarDisplay,
        launchAtLogin: Bool,
        eveningNudge: Bool,
        lastProvider: AIProvider,
        lastModel: String,
        localSync: LocalSyncSettings = .default
    ) {
        self.snakeName = snakeName
        self.dailyCostBudget = dailyCostBudget
        self.dailyTokenBudget = dailyTokenBudget
        self.menuBarDisplay = menuBarDisplay
        self.launchAtLogin = launchAtLogin
        self.eveningNudge = eveningNudge
        self.lastProvider = lastProvider
        self.lastModel = lastModel
        self.localSync = localSync
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snakeName = try c.decodeIfPresent(String.self, forKey: .snakeName) ?? Self.default.snakeName
        dailyCostBudget = try c.decodeIfPresent(Double.self, forKey: .dailyCostBudget) ?? Self.default.dailyCostBudget
        dailyTokenBudget = try c.decodeIfPresent(Int.self, forKey: .dailyTokenBudget) ?? Self.default.dailyTokenBudget
        menuBarDisplay = try c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay) ?? Self.default.menuBarDisplay
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        eveningNudge = try c.decodeIfPresent(Bool.self, forKey: .eveningNudge) ?? false
        lastProvider = try c.decodeIfPresent(AIProvider.self, forKey: .lastProvider) ?? .cursor
        lastModel = try c.decodeIfPresent(String.self, forKey: .lastModel) ?? Self.default.lastModel
        localSync = try c.decodeIfPresent(LocalSyncSettings.self, forKey: .localSync) ?? .default
    }
}

struct PersistedStore: Codable {
    var entries: [TokenEntry]
    var subscriptions: [SubscriptionAccount]
    var habits: [HabitDefinition]
    var days: [HabitDay]
    var settings: AppSettings
    var localSyncState: LocalSyncState? = nil

    static let empty = PersistedStore(
        entries: [],
        subscriptions: [],
        habits: [
            HabitDefinition(kind: .logDaily),
            HabitDefinition(kind: .stayUnderBudget),
            HabitDefinition(kind: .checkIn)
        ],
        days: [],
        settings: .default
    )
}

enum SnakeMood: String {
    case sleeping
    case resting
    case growing
    case legendary

    var label: String {
        switch self {
        case .sleeping: "還在蛋裡"
        case .resting: "休息中 · 成長保留"
        case .growing: "吃進 tokens，持續長大"
        case .legendary: "星蛇 · 持續進化"
        }
    }

    var symbol: String {
        switch self {
        case .sleeping: "moon.zzz.fill"
        case .resting: "moon.fill"
        case .growing: "leaf.fill"
        case .legendary: "sparkles"
        }
    }
}

struct SnakeSnapshot: Equatable {
    var name: String
    var growth: SnakeGrowth
    var todayTokens: Int
    var todayFedCount: Int
    var latestMealTokens: Int = 0

    var mood: SnakeMood {
        if growth.totalTokens == 0 { return .sleeping }
        if todayTokens == 0 { return .resting }
        return growth.level >= 50 ? .legendary : .growing
    }
}

struct UsageInsights: Equatable {
    var todayTokens: Int
    var todayCost: Double
    var monthTokens: Int
    var monthCost: Double
    var outputRatio: Double
    var topProvider: AIProvider?
    var topProviderShare: Double
    var last14Days: [Int]
}

struct ModelSpec: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var inputPerMillion: Double
    var outputPerMillion: Double
    var cachedPerMillion: Double
    var cacheWriteMultiplier: Double = 1
    var longContextThreshold: Int? = nil
}

struct ProviderCatalog {
    var provider: AIProvider
    var models: [ModelSpec]
}
