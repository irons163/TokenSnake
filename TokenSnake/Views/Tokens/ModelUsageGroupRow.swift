import SwiftUI

struct ModelUsageGroupRow: View {
    var group: ModelUsageGroup
    var onDelete: (TokenEntry) -> Void
    @State private var isExpanded = false
    @State private var visibleLimit = 100

    var body: some View {
        VStack(spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    ProviderBadge(provider: group.id.provider)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.id.model)
                            .font(Typography.body(12))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text("\(group.entries.count) 筆")
                            Text("·")
                            Text(Formatters.compactTokens(group.totalTokens))
                            Text("tokens")
                        }
                        .font(Typography.caption())
                        .foregroundStyle(Theme.text2)
                        Text(group.costLabel)
                            .font(Typography.caption(10))
                            .foregroundStyle(group.unpricedCount > 0 ? Theme.warning : Theme.text3)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface.opacity(0.9)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收合 \(group.id.model) 明細" : "展開 \(group.id.model) 明細")
            .accessibilityLabel("\(group.id.model)，\(group.entries.count) 筆，\(group.totalTokens) tokens，\(group.costLabel)")
            .accessibilityValue(isExpanded ? "已展開" : "已收合")

            if isExpanded {
                LazyVStack(spacing: 6) {
                    ForEach(group.entries.prefix(visibleLimit)) { entry in
                        TokenRow(entry: entry, showsModel: false) { onDelete(entry) }
                    }
                    if group.entries.count > visibleLimit {
                        Button("顯示更多明細（\(min(visibleLimit, group.entries.count)) / \(group.entries.count) 筆）") {
                            visibleLimit += 100
                        }
                        .font(Typography.caption())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}
