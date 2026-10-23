import SwiftUI

struct UpdateSettingsSection: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                Spacer()
                Button(updater.availableVersion.map { "更新至 \($0)…" } ?? "檢查更新…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Toggle("自動檢查更新", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticChecks($0) }
            ))
            Toggle("自動下載並在結束後安裝", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.setAutomaticDownloads($0) }
            ))
            .disabled(!updater.automaticallyChecksForUpdates)
            Text("每小時檢查新版。下載、安裝與重新啟動由更新視窗處理。")
                .font(Typography.caption()).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let error = updater.errorMessage {
                Text(error).font(Typography.caption()).foregroundStyle(Theme.warning)
            }
        }
        .font(Typography.body(12))
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .foregroundStyle(Theme.text)
    }
}
