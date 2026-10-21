import SwiftUI

struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var account: SubscriptionAccount
    var onSave: (SubscriptionAccount) -> Void

    private var valid: Bool {
        !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && account.monthlyPrice.isFinite && account.monthlyPrice >= 0
            && account.quotaLimit >= 0 && account.quotaUsed >= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("訂閱設定").font(Typography.title(16))
            Form {
                TextField("帳號名稱", text: $account.name)
                Picker("供應商", selection: $account.provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("方案", text: $account.planName)
                TextField("月費（USD）", value: $account.monthlyPrice, format: .number)
                DatePicker("帳單錨點", selection: $account.cycleAnchor, displayedComponents: .date)
                Toggle("啟用此訂閱", isOn: $account.isActive)
                Toggle("追蹤用量額度", isOn: Binding(get: { !account.unlimited }, set: { account.unlimited = !$0 }))
                if !account.unlimited {
                    Picker("額度單位", selection: $account.quotaUnit) {
                        ForEach(QuotaUnit.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("週期額度", value: $account.quotaLimit, format: .number)
                    TextField("已用額度", value: $account.quotaUsed, format: .number)
                }
                TextField("備註", text: $account.notes)
            }
            Text("請依帳單調整實際月費與額度；每月進入新週期會重設已用額度。訂閱費用與 token 估算分開顯示。")
                .font(Typography.caption()).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("儲存") {
                    account.name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(account)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}
