import SwiftUI

struct SubscriptionSettingsSection: View {
    @Environment(AppStore.self) private var store
    @State private var editingAccount: SubscriptionAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手動記錄月費與續費日，與用量估算分開計算。用量額度需自行更新。")
                .font(Typography.caption())
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if let next = nextAccount {
                Text("下次續費：\(next.name) · \(next.daysRemaining()) 天後")
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Menu("加入範本") {
                    ForEach(Pricing.subscriptionTemplates) { template in
                        Button(template.name) { _ = store.addTemplate(template) }
                            .disabled(store.subscriptions.contains { $0.name == template.name })
                    }
                }
                .fixedSize()
                Spacer()
                Button("+ 自訂") {
                    editingAccount = SubscriptionAccount(name: "", provider: .custom, planName: "", monthlyPrice: 0)
                }
            }
            .font(Typography.caption())

            if store.subscriptions.isEmpty {
                Text("尚未加入訂閱")
                    .font(Typography.caption())
                    .foregroundStyle(Theme.text3)
            }
            ForEach(store.subscriptions) { account in
                SubscriptionCard(account: account) { editingAccount = account }
            }
        }
        .sheet(item: $editingAccount) { account in
            SubscriptionEditor(account: account) { store.upsertSubscription($0) }
        }
    }

    private var nextAccount: SubscriptionAccount? {
        store.subscriptions.filter(\.isActive).min { $0.daysRemaining() < $1.daysRemaining() }
    }
}

struct SubscriptionCard: View {
    @Environment(AppStore.self) private var store
    var account: SubscriptionAccount
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProviderBadge(provider: account.provider)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.text)
                        Text(account.isActive ? "\(Formatters.monthlyCurrency(account.monthlyPrice))/月 · \(account.daysRemaining()) 天後續費" : "已停用")
                            .font(Typography.caption())
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    if let onEdit {
                        Button(action: onEdit) { Image(systemName: "pencil").font(.system(size: 11)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.text2)
                            .help("編輯訂閱")
                    }
                    Button {
                        store.deleteSubscription(account)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.text3)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .help("刪除")
                }

                if !account.unlimited {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(account.quotaUsed) / \(account.quotaLimit) \(account.quotaUnit.label)")
                                .font(Typography.caption())
                                .monospacedDigit()
                                .foregroundStyle(Theme.text2)
                            Spacer()
                            Text("剩 \(account.remaining)")
                                .font(Typography.caption())
                                .foregroundStyle(account.quotaProgress > 0.85 ? Theme.danger : Theme.text3)
                        }
                        GlowProgress(
                            progress: account.quotaProgress,
                            tint: account.quotaProgress > 0.85 ? Theme.danger : account.provider.tint
                        )
                        HStack(spacing: 8) {
                            quotaButton("−") { store.adjustQuota(for: account, delta: -1) }
                            quotaButton("+1") { store.adjustQuota(for: account, delta: 1) }
                            quotaButton("+10") { store.adjustQuota(for: account, delta: 10) }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func quotaButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Typography.body(13))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 44, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
    }
}
