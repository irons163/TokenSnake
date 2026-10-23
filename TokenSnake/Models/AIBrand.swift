import SwiftUI

/// Display identity only. Imported providers, pricing and grouping stay unchanged.
nonisolated enum AIBrand: String, CaseIterable, Sendable {
    case openai, claude, gemini, grok, cursor, copilot, perplexity
    case deepseek, qwen, kimi, zai, meta, unknown

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .perplexity: "Perplexity"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .zai: "Z.ai"
        case .meta: "Meta"
        case .unknown: "未識別的 AI 品牌"
        }
    }

    var assetName: String? {
        switch self {
        case .unknown: nil
        case .copilot: "Brand-githubcopilot"
        default: "Brand-\(rawValue)"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .openai: AIProvider.openai.tint
        case .claude: AIProvider.anthropic.tint
        case .gemini: Color(red: 0.20, green: 0.40, blue: 0.85)
        case .grok, .cursor, .kimi, .zai: Color(white: 0.92)
        case .copilot: AIProvider.copilot.tint
        case .perplexity: AIProvider.perplexity.tint
        case .deepseek: Color(red: 0.23, green: 0.36, blue: 0.87)
        case .qwen: Color(red: 0.38, green: 0.30, blue: 0.83)
        case .meta: Color(red: 0.03, green: 0.40, blue: 0.90)
        case .unknown: Theme.surfaceRaised
        }
    }

    @MainActor var foreground: Color {
        switch self {
        case .gemini, .deepseek, .qwen, .meta: .white
        case .unknown: Theme.text2
        default: Theme.ink
        }
    }

    static func resolve(model: String? = nil, provider: AIProvider) -> Self {
        // Gateways can wrap a model in one or more namespaces. The model family
        // takes precedence over the transport provider (e.g. OpenAI-compatible APIs).
        let name = model?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().split(separator: "/").last.map(String.init) ?? ""
        func matches(_ families: [String]) -> Bool {
            families.contains { family in
                guard name.hasPrefix(family) else { return false }
                guard let next = name.dropFirst(family.count).first else { return true }
                return next.isNumber || "-_. ".contains(next)
            }
        }

        if matches(["deepseek"]) { return .deepseek }
        if matches(["claude"]) { return .claude }
        if matches(["gpt", "chatgpt", "codex", "o1", "o3", "o4"]) { return .openai }
        if matches(["gemini"]) { return .gemini }
        if matches(["grok"]) { return .grok }
        if matches(["qwen", "qwq"]) { return .qwen }
        if matches(["kimi", "moonshot"]) { return .kimi }
        if matches(["glm", "chatglm"]) { return .zai }
        if matches(["llama", "muse-spark", "muse-wonder", "muse-glimmer"]) { return .meta }
        if matches(["sonar", "pplx"]) { return .perplexity }

        switch provider {
        case .openai: return .openai
        case .anthropic: return .claude
        case .google: return .gemini
        case .xai: return .grok
        case .cursor: return .cursor
        case .copilot: return .copilot
        case .perplexity: return .perplexity
        case .custom: return .unknown
        }
    }
}
