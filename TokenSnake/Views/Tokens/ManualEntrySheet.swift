import SwiftUI

struct ManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (TokenEntry) -> Void
    @State private var provider: AIProvider = .openai
    @State private var model = "GPT-5"
    @State private var input = 0
    @State private var output = 0
    @State private var cached = 0
    @State private var createdAt = Date.now
    @State private var note = ""

    private var valid: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && input >= 0 && output >= 0
            && input <= 1_000_000_000_000 && output <= 1_000_000_000_000
            && (input > 0 || output > 0) && cached >= 0 && cached <= input
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("精確記錄用量").font(Typography.title(16))
            Form {
                Picker("供應商", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("模型", text: $model)
                TextField("輸入 tokens（含快取）", value: $input, format: .number)
                TextField("輸出 tokens", value: $output, format: .number)
                TextField("快取讀取 tokens", value: $cached, format: .number)
                DatePicker("使用時間", selection: $createdAt)
                TextField("備註", text: $note)
            }
            Text("快取讀取包含在輸入中。未收錄費率的模型仍可記錄 tokens，費用顯示「費率未收錄」。")
                .font(Typography.caption()).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("儲存") {
                    onSave(TokenEntry(createdAt: createdAt, provider: provider,
                                      model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                      inputTokens: input, outputTokens: output, cachedTokens: cached, note: note))
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
        .onChange(of: provider) { _, value in model = Pricing.models(for: value).first?.name ?? "" }
    }
}
