import SwiftUI

struct TokensPane: View {
    @Environment(AppStore.self) private var store
    @State private var provider: AIProvider = .cursor
    @State private var model: String = "Cursor 包含額度"
    @State private var toast: String?
    @State private var lastLoggedID: UUID?
    @State private var showQuickLog = false
    @State private var showManualEntry = false
    @State private var sourceFilter = "all"
    @State private var visibleGroupLimit = 100

    private var visibleEntries: [TokenEntry] {
        store.entries.filter { sourceFilter == "all" || ($0.source?.rawValue ?? "manual") == sourceFilter }
    }

    var body: some View {
        let entries = visibleEntries
        let groups = ModelUsageGroup.groups(from: entries)
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: store.isSyncing ? "arrow.triangle.2.circlepath" : "externaldrive")
                Text(store.isSyncing ? "正在同步本機用量…" : (store.settings.localSync.enabled ? "本機用量 · 每 30 秒同步" : "自動同步已暫停"))
                Spacer()
                Button { Task { await store.syncLocalUsage(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(store.isSyncing)
                .help("立即同步")
            }
            .font(Typography.caption())
            .foregroundStyle(Theme.text2)

            if let toast {
                HStack {
                    Text(toast)
                        .font(Typography.caption())
                        .foregroundStyle(Theme.text2)
                    Spacer()
                    Button("復原") {
                        if let id = lastLoggedID, let entry = store.entries.first(where: { $0.id == id }) { store.deleteEntry(entry) }
                        self.toast = nil
                        lastLoggedID = nil
                    }
                    .buttonStyle(.plain)
                    .font(Typography.body(12))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                compactStat("今日", Formatters.compactTokens(store.insights.todayTokens), costSubtitle(store.insights.todayCost, unknown: store.unpricedTodayCount))
                compactStat("本月", Formatters.compactTokens(store.insights.monthTokens), costSubtitle(store.insights.monthCost, unknown: store.unpricedMonthCount))
            }

            if store.insights.monthTokens > 0 {
                Panel(padding: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("最近 14 天").font(Typography.caption(10)).foregroundStyle(Theme.text3)
                        Sparkline(values: store.insights.last14Days).frame(height: 36)
                    }
                }
            }

            HStack {
                DisclosureGroup("快速估算記錄", isExpanded: $showQuickLog) {
                    QuickLogCard(provider: $provider, model: $model) { size in
                        lastLoggedID = store.logSession(provider: provider, model: model, size: size)
                        toast = "已記入 \(provider.displayName) \(size.title)（\(size.tokenLabel)）"
                    }
                }
                .font(Typography.caption())
                if !showQuickLog {
                    Button("+ 精確記錄") { showManualEntry = true }.font(Typography.caption())
                }
            }
            .foregroundStyle(Theme.text2)

            HStack {
                Text("全部紀錄 · \(entries.count) 筆 · \(groups.count) 個模型").font(Typography.caption(10)).foregroundStyle(Theme.text3)
                Spacer()
                Picker("來源", selection: $sourceFilter) {
                    Text("全部").tag("all")
                    Text("手動").tag("manual")
                    ForEach(UsageSource.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 105)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if entries.isEmpty {
                        Text("尚無用量紀錄\n可在設定選擇本機來源，或手動新增。")
                            .font(Typography.body(12)).foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    ForEach(groups.prefix(visibleGroupLimit)) { group in
                        ModelUsageGroupRow(group: group, onDelete: store.deleteEntry)
                    }
                    if groups.count > visibleGroupLimit {
                        Button("顯示更多模型") { visibleGroupLimit += 100 }
                            .font(Typography.caption())
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                }
                .id(sourceFilter)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet { entry in
                store.addEntry(entry)
                lastLoggedID = entry.id
                toast = "已記入 \(Formatters.compactTokens(entry.totalTokens)) tokens"
            }
        }
        .onAppear {
            provider = store.settings.lastProvider
            let models = Pricing.models(for: provider)
            if models.contains(where: { $0.name == store.settings.lastModel }) {
                model = store.settings.lastModel
            } else {
                model = models.first?.name ?? store.settings.lastModel
            }
        }
        .onChange(of: provider) { _, newValue in
            let models = Pricing.models(for: newValue)
            if !models.contains(where: { $0.name == model }) {
                model = models.first?.name ?? model
            }
        }
        .onChange(of: sourceFilter) { _, _ in visibleGroupLimit = 100 }
    }

    private func costSubtitle(_ cost: Double, unknown: Int) -> String {
        unknown > 0 ? "\(unknown) 筆待補費率 · 已知 \(Formatters.currency(cost))" : "\(Formatters.currency(cost)) 參考估算"
    }

    private func compactStat(_ title: String, _ value: String, _ footnote: String) -> some View {
        Panel(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text3)
                Text(value)
                    .font(Typography.display(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(footnote)
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct QuickLogCard: View {
    @Binding var provider: AIProvider
    @Binding var model: String
    var onLog: (SessionSize) -> Void

    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("點一下就記入")
                    .font(Typography.body(12))
                    .foregroundStyle(Theme.text2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(AIProvider.allCases.filter { $0 != .custom }) { item in
                        Chip(
                            title: shortName(item),
                            selected: provider == item,
                            tint: item.tint
                        ) {
                            provider = item
                        }
                    }
                }

                Menu {
                    ForEach(Pricing.models(for: provider)) { spec in
                        Button(spec.name) { model = spec.name }
                    }
                } label: {
                    HStack {
                        Text(model)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                    }
                    .font(Typography.body(12))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.surfaceRaised)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                HStack(spacing: 6) {
                    ForEach(SessionSize.allCases) { size in
                        Button {
                            onLog(size)
                        } label: {
                            VStack(spacing: 1) {
                                Text(size.title)
                                    .font(Typography.body(13))
                                Text(size.tokenLabel)
                                    .font(Typography.caption(10))
                                    .foregroundStyle(Theme.ink.opacity(0.7))
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shortName(_ provider: AIProvider) -> String {
        switch provider {
        case .openai: "GPT"
        case .anthropic: "Claude"
        case .google: "Gemini"
        case .xai: "Grok"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .perplexity: "Perplex"
        case .custom: "自訂"
        }
    }
}

struct TokenRow: View {
    var entry: TokenEntry
    var showsModel = true
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProviderBadge(provider: entry.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(showsModel ? entry.model : (entry.source?.label ?? "手動"))
                    .font(Typography.body(12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(showsModel ? "\(entry.source?.label ?? "手動") · " : "")\(Formatters.compactTokens(entry.totalTokens)) · \(Pricing.costLabel(for: entry))")
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            Text(Calendar.current.isDateInToday(entry.createdAt) ? Formatters.time(entry.createdAt) : Formatters.shortDate(entry.createdAt))
                .font(Typography.caption(10))
                .foregroundStyle(Theme.text3)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .help(entry.source == nil ? "刪除" : "隱藏此筆匯入紀錄；重新匯入可恢復")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface.opacity(0.9))
        )
    }
}

struct ProviderBadge: View {
    var provider: AIProvider

    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 22, height: 22)
            .background(Circle().fill(provider.tint))
    }
}

struct Sparkline: View {
    var values: [Int]

    var body: some View {
        Canvas { context, size in
            guard let maxValue = values.max(), maxValue > 0 else { return }

            let points: [CGPoint] = values.enumerated().map { index, value in
                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = size.height - (CGFloat(value) / CGFloat(maxValue)) * (size.height - 4) - 2
                return CGPoint(x: x, y: y)
            }

            var fill = Path()
            if let first = points.first, let last = points.last {
                fill.move(to: CGPoint(x: first.x, y: size.height))
                for point in points { fill.addLine(to: point) }
                fill.addLine(to: CGPoint(x: last.x, y: size.height))
                fill.closeSubpath()
            }
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            var line = Path()
            for (index, point) in points.enumerated() {
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
