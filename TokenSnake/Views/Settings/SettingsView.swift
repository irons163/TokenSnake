import SwiftUI

struct SettingsPane: View {
    @Environment(AppStore.self) private var store
    var onClose: () -> Void
    @State private var confirmReset = false
    @State private var confirmDemo = false
    @State private var exportError: String?
    @State private var restoreURL: URL?
    @State private var confirmRestore = false
    @State private var showSubscriptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("App 更新") { UpdateSettingsSection() }
                section("用量來源") { LocalSyncSection() }

                section("選單列顯示") {
                    VStack(spacing: 6) {
                        ForEach(MenuBarDisplay.allCases) { item in
                            Chip(
                                title: item.label,
                                selected: store.settings.menuBarDisplay == item
                            ) {
                                store.updateSettings { $0.menuBarDisplay = item }
                            }
                        }
                    }
                }

                section("每日預算") {
                    stepperRow(
                        "花費 \(Formatters.currency(store.settings.dailyCostBudget))",
                        minus: { store.updateSettings { $0.dailyCostBudget = max(0.5, $0.dailyCostBudget - 0.5) } },
                        plus: { store.updateSettings { $0.dailyCostBudget += 0.5 } }
                    )
                    stepperRow(
                        "Tokens \(Formatters.compactTokens(store.settings.dailyTokenBudget))",
                        minus: { store.updateSettings { $0.dailyTokenBudget = max(10_000, $0.dailyTokenBudget - 10_000) } },
                        plus: { store.updateSettings { $0.dailyTokenBudget += 10_000 } }
                    )
                }

                DisclosureGroup(isExpanded: $showSubscriptions) {
                    SubscriptionSettingsSection()
                        .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("訂閱管理")
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.text)
                        Text(subscriptionSummary)
                            .font(Typography.caption())
                            .foregroundStyle(Theme.text3)
                    }
                }
                .tint(Theme.text2)

                section("小蛇") {
                    HStack(spacing: 6) {
                        ForEach(["小蛇", "Byte", "Naga", "青行"], id: \.self) { name in
                            Chip(
                                title: name,
                                selected: store.settings.snakeName == name,
                                flexible: false
                            ) {
                                store.updateSettings { $0.snakeName = name }
                            }
                        }
                    }
                    Text("用量自動餵養，累積 tokens 決定等級與身長。休息或超過預算不會扣除成長。")
                        .font(Typography.caption())
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("登入時啟動", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    Button("匯出資料備份…") { exportBackup() }
                        .font(Typography.body(13))
                        .frame(maxWidth: .infinity, minHeight: 32)
                    Button("還原資料備份…") { chooseBackup() }
                        .font(Typography.body(13))
                        .frame(maxWidth: .infinity, minHeight: 32)
                    if let exportError {
                        Text(exportError).font(Typography.caption()).foregroundStyle(Theme.warning)
                    }
                    Button {
                        confirmDemo = true
                    } label: {
                        Text("載入示範資料")
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        confirmReset = true
                    } label: {
                        Text("清除所有紀錄")
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Text("結束 TokenSnake")
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.text3)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .confirmationDialog("清除所有紀錄？", isPresented: $confirmReset) {
            Button("清除所有紀錄", role: .destructive) { store.resetAll(); store.flushPersistence() }
        } message: {
            Text("會清除用量、訂閱與小蛇成長，並停用自動同步。請先匯出備份；需要時可用「重新匯入」恢復本機用量與成長。")
        }
        .confirmationDialog("載入示範資料？", isPresented: $confirmDemo) {
            Button("載入示範資料", role: .destructive) { store.loadDemoData(); store.flushPersistence(); onClose() }
        } message: {
            Text("會取代現有紀錄並停用自動同步。請先匯出備份。")
        }
        .confirmationDialog("還原資料備份？", isPresented: $confirmRestore) {
            Button("還原備份", role: .destructive) {
                guard let url = restoreURL else { return }
                do { try store.restoreData(from: url); exportError = nil }
                catch { exportError = "無法還原：請確認檔案是有效的 TokenSnake 備份，且資料目錄可寫入。" }
                restoreURL = nil
            }
        } message: {
            Text("會以備份取代目前紀錄，並暫停自動同步。原資料會保留在資料目錄中。")
        }
    }

    private var subscriptionSummary: String {
        guard !store.subscriptions.isEmpty else { return "選填 · 手動記錄月費與續費日" }
        let active = store.subscriptions.filter(\.isActive)
        let monthlyTotal = active.reduce(0) { $0 + $1.monthlyPrice }
        return "\(active.count) 個啟用 · \(Formatters.monthlyCurrency(monthlyTotal))／月"
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TokenSnake-backup.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.exportData(to: url); exportError = nil }
            catch { exportError = "無法匯出備份，請選擇可寫入的位置。" }
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "選擇 TokenSnake 匯出的 JSON 備份"
        if panel.runModal() == .OK, let url = panel.url {
            restoreURL = url
            confirmRestore = true
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.caption())
                .foregroundStyle(Theme.text3)
            content()
        }
    }

    private func stepperRow(_ title: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Typography.body(13))
                .foregroundStyle(Theme.text)
            Spacer()
            Button("−", action: minus)
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surfaceRaised))
            Button("+", action: plus)
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceRaised))
        }
        .foregroundStyle(Theme.text)
    }
}
