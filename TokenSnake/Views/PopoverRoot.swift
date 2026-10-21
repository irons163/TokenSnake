import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case tokens
    case snake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: "用量"
        case .snake: "小蛇"
        }
    }
}

struct PopoverRoot: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab
    @State private var showSettings: Bool

    init(tab: AppTab = .tokens, showSettings: Bool = false) {
        _tab = State(initialValue: tab)
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let warning = store.persistenceError ?? store.storageWarning {
                Text(warning)
                    .font(Typography.caption(10))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 14)
                    .padding(.top, 5)
            }
            if showSettings {
                SettingsPane { showSettings = false }
            } else {
                tabBar
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Group {
                    switch tab {
                    case .tokens: TokensPane()
                    case .snake: SnakePane()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: Theme.popoverWidth, height: Theme.popoverHeight)
        .background(GlassBackground())
        .background(HideTitleBar())
        .preferredColorScheme(.dark)
        .onAppear {
            NSApp.activate()
            store.refreshClock()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showSettings ? "設定" : "TokenSnake")
                    .font(Typography.title(16))
                    .foregroundStyle(Theme.text)
                Text(headerSubtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .help(showSettings ? "關閉設定" : "設定")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var headerSubtitle: String {
        if showSettings { return "本機同步、預算、訂閱與資料" }
        let cost = store.unpricedTodayCount > 0 ? "含待補費率" : "估算 \(Formatters.currency(store.insights.todayCost))"
        return "今天 \(Formatters.compactTokens(store.insights.todayTokens)) · \(cost)"
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(Typography.body(12))
                        .foregroundStyle(tab == item ? Theme.ink : Theme.text2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 30)
                        .background {
                            if tab == item {
                                Capsule().fill(Theme.accent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Theme.surface)
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        )
    }
}
