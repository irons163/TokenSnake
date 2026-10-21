import SwiftUI
import AppKit

struct LocalSyncSection: View {
    @Environment(AppStore.self) private var store
    @State private var confirmReimport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("自動同步本機用量", isOn: Binding(
                get: { store.settings.localSync.enabled },
                set: { enabled in
                    store.updateSyncSettings { $0.enabled = enabled }
                    if enabled { Task { await store.syncLocalUsage() } }
                }
            ))
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .font(Typography.body(13))

            ForEach(UsageSource.allCases) { source in
                sourceRow(source)
            }

            HStack {
                Button {
                    Task { await store.syncLocalUsage(force: true) }
                } label: {
                    HStack(spacing: 5) {
                        if store.isSyncing { ProgressView().controlSize(.small) }
                        Text(store.isSyncing ? "同步中…" : "立即同步")
                    }
                }
                .disabled(store.isSyncing || !hasEnabledSource)
                Spacer()
                Button("重新匯入") { confirmReimport = true }
                    .disabled(store.isSyncing || !hasEnabledSource)
            }
            .font(Typography.body(12))

            if let last = store.localSyncState.lastSyncAt {
                Text("上次掃描 \(Formatters.time(last)) · 新增 \(store.lastSyncInserted)、更新 \(store.lastSyncUpdated) 筆")
                    .font(Typography.caption(10))
                    .foregroundStyle(Theme.text2)
            }
            Text("每 30 秒更新。只保留用量與模型，不儲存對話內容。費用依標準 API 費率估算，訂閱帳單另計。")
                .font(Typography.caption())
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.text)
        .confirmationDialog("重新匯入本機用量？", isPresented: $confirmReimport) {
            Button("重新匯入") { Task { await store.reimportLocalUsage() } }
        } message: {
            Text("會重新掃描兩個來源，恢復先前刪除的匯入紀錄。現有紀錄會去重，手動紀錄會保留。")
        }
    }

    private var hasEnabledSource: Bool {
        store.settings.localSync.codexEnabled || store.settings.localSync.claudeEnabled
    }

    private func sourceRow(_ source: UsageSource) -> some View {
        let status = store.syncStatuses.first { $0.source == source }
        let enabled = store.settings.localSync.isEnabled(source)
        let directory = store.settings.localSync.directory(for: source)
        let count = store.entries.filter { $0.source == source }.count
        return Panel(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle(source.label, isOn: Binding(
                        get: { store.settings.localSync.isEnabled(source) },
                        set: { value in
                            store.updateSyncSettings {
                                if source == .codex { $0.codexEnabled = value } else { $0.claudeEnabled = value }
                            }
                            if store.settings.localSync.enabled { Task { await store.syncLocalUsage() } }
                        }
                    ))
                    .font(Typography.body(12))
                    Spacer()
                    Text("\(count) 筆")
                        .font(Typography.caption())
                        .foregroundStyle(Theme.text2)
                }
                Text(enabled ? (status?.message ?? "尚未掃描") : "已停用")
                    .font(Typography.caption())
                    .foregroundStyle(status?.state == .failed ? Theme.warning : Theme.text2)
                Text(directory.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(directory.path)
                HStack {
                    Button("選擇資料目錄…") { chooseDirectory(source) }
                    Spacer()
                    Button("使用預設") {
                        store.updateSyncSettings {
                            if source == .codex { $0.codexDirectory = "" } else { $0.claudeDirectory = "" }
                        }
                        if store.settings.localSync.enabled { Task { await store.syncLocalUsage() } }
                    }
                }
                .font(Typography.caption())
            }
        }
    }

    private func chooseDirectory(_ source: UsageSource) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = store.settings.localSync.directory(for: source)
        panel.message = source == .codex ? "選擇包含 sessions 的 Codex 資料目錄" : "選擇包含 projects 的 Claude Code 資料目錄"
        if panel.runModal() == .OK, let url = panel.url {
            store.updateSyncSettings {
                if source == .codex { $0.codexDirectory = url.path } else { $0.claudeDirectory = url.path }
            }
            if store.settings.localSync.enabled { Task { await store.syncLocalUsage() } }
        }
    }
}
