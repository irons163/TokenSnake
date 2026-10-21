import Foundation

enum Pricing {
    static let missingRateLabel = "費率未收錄"

    static let catalogs: [ProviderCatalog] = [
        ProviderCatalog(provider: .openai, models: [
            ModelSpec(name: "GPT-6.1 Sol", inputPerMillion: 2.00, outputPerMillion: 10.00, cachedPerMillion: 0.10,
                      cacheWriteMultiplier: 1.25, longContextThreshold: 272_000),
            ModelSpec(name: "GPT-6 Astra", inputPerMillion: 10.00, outputPerMillion: 50.00, cachedPerMillion: 1.00,
                      cacheWriteMultiplier: 1.25, longContextThreshold: 272_000),
            // Standard API rates verified against each official model page on 2026-10-15.
            // https://developers.openai.com/api/docs/models/gpt-5.6-sol (promotional rate)
            ModelSpec(name: "GPT-5.6 Sol", inputPerMillion: 4.00, outputPerMillion: 20.00, cachedPerMillion: 0.40,
                      cacheWriteMultiplier: 1.25, longContextThreshold: 272_000),
            // https://developers.openai.com/api/docs/models/gpt-5.6-terra
            ModelSpec(name: "GPT-5.6 Terra", inputPerMillion: 2.00, outputPerMillion: 12.00, cachedPerMillion: 0.20,
                      cacheWriteMultiplier: 1.25, longContextThreshold: 272_000),
            // https://developers.openai.com/api/docs/models/gpt-5.6-luna
            ModelSpec(name: "GPT-5.6 Luna", inputPerMillion: 0.20, outputPerMillion: 1.20, cachedPerMillion: 0.02,
                      cacheWriteMultiplier: 1.25, longContextThreshold: 272_000),
            // https://developers.openai.com/api/docs/models/gpt-5.5
            ModelSpec(name: "GPT-5.5", inputPerMillion: 5.00, outputPerMillion: 30.00, cachedPerMillion: 0.50,
                      longContextThreshold: 272_000),
            ModelSpec(name: "GPT-5", inputPerMillion: 1.25, outputPerMillion: 10.00, cachedPerMillion: 0.125),
            ModelSpec(name: "GPT-4.1", inputPerMillion: 2.00, outputPerMillion: 8.00, cachedPerMillion: 0.50),
            ModelSpec(name: "GPT-4.1 mini", inputPerMillion: 0.40, outputPerMillion: 1.60, cachedPerMillion: 0.10),
            ModelSpec(name: "o3", inputPerMillion: 2.00, outputPerMillion: 8.00, cachedPerMillion: 0.50),
            ModelSpec(name: "o4-mini", inputPerMillion: 1.10, outputPerMillion: 4.40, cachedPerMillion: 0.275)
        ]),
        ProviderCatalog(provider: .anthropic, models: [
            // Standard rates verified 2026-10-21, including 5m/1h cache writes.
            // https://platform.claude.com/docs/en/models/opus-5-5/overview
            ModelSpec(name: "Claude Opus 5.5", inputPerMillion: 4.00, outputPerMillion: 20.00, cachedPerMillion: 0.20),
            ModelSpec(name: "Claude Opus 4.8", inputPerMillion: 5.00, outputPerMillion: 25.00, cachedPerMillion: 0.50),
            ModelSpec(name: "Claude Fable 5", inputPerMillion: 10.00, outputPerMillion: 50.00, cachedPerMillion: 1.00),
            ModelSpec(name: "Claude Opus 4.1", inputPerMillion: 15.00, outputPerMillion: 75.00, cachedPerMillion: 1.50),
            ModelSpec(name: "Claude Sonnet 4", inputPerMillion: 3.00, outputPerMillion: 15.00, cachedPerMillion: 0.30),
            ModelSpec(name: "Claude Haiku 3.5", inputPerMillion: 0.80, outputPerMillion: 4.00, cachedPerMillion: 0.08)
        ]),
        ProviderCatalog(provider: .google, models: [
            ModelSpec(name: "Gemini 2.5 Pro", inputPerMillion: 1.25, outputPerMillion: 10.00, cachedPerMillion: 0.315),
            ModelSpec(name: "Gemini 2.5 Flash", inputPerMillion: 0.15, outputPerMillion: 0.60, cachedPerMillion: 0.0375)
        ]),
        ProviderCatalog(provider: .xai, models: [
            ModelSpec(name: "Grok 4", inputPerMillion: 3.00, outputPerMillion: 15.00, cachedPerMillion: 0.75),
            ModelSpec(name: "Grok 3", inputPerMillion: 3.00, outputPerMillion: 15.00, cachedPerMillion: 0.75)
        ]),
        ProviderCatalog(provider: .cursor, models: [
            ModelSpec(name: "Cursor 包含額度", inputPerMillion: 0, outputPerMillion: 0, cachedPerMillion: 0),
            ModelSpec(name: "Cursor 用量計費", inputPerMillion: 1.25, outputPerMillion: 10.00, cachedPerMillion: 0.125)
        ]),
        ProviderCatalog(provider: .copilot, models: [
            ModelSpec(name: "Copilot 包含額度", inputPerMillion: 0, outputPerMillion: 0, cachedPerMillion: 0)
        ]),
        ProviderCatalog(provider: .perplexity, models: [
            ModelSpec(name: "Sonar", inputPerMillion: 1.00, outputPerMillion: 1.00, cachedPerMillion: 0),
            ModelSpec(name: "Sonar Pro", inputPerMillion: 3.00, outputPerMillion: 15.00, cachedPerMillion: 0)
        ]),
        ProviderCatalog(provider: .custom, models: [
            ModelSpec(name: "自訂模型", inputPerMillion: 0, outputPerMillion: 0, cachedPerMillion: 0)
        ])
    ]

    static func models(for provider: AIProvider) -> [ModelSpec] {
        catalogs.first(where: { $0.provider == provider })?.models ?? []
    }

    static func spec(provider: AIProvider, model: String) -> ModelSpec? {
        let aliases = [
            "gpt-6.1-sol": "GPT-6.1 Sol", "gpt-6-astra": "GPT-6 Astra",
            "gpt-5.6-sol": "GPT-5.6 Sol", "gpt-5.6": "GPT-5.6 Sol",
            "gpt-5.6-terra": "GPT-5.6 Terra", "gpt-5.6-luna": "GPT-5.6 Luna",
            "gpt-5.5": "GPT-5.5",
            "claude-opus-5-5": "Claude Opus 5.5",
            "claude-opus-4-8": "Claude Opus 4.8", "claude-fable-5": "Claude Fable 5",
            "gpt-5": "GPT-5", "gpt-5-codex": "GPT-5", "gpt-4.1": "GPT-4.1",
            "gpt-4.1-mini": "GPT-4.1 mini", "o4-mini": "o4-mini", "o3": "o3",
            "claude-opus-4-1": "Claude Opus 4.1", "claude-sonnet-4": "Claude Sonnet 4",
            "claude-3-5-haiku": "Claude Haiku 3.5"
        ]
        let normalized: String
        if let alias = aliases[model] { normalized = alias }
        else if let match = model.range(of: "-[0-9]{8}$", options: .regularExpression),
                let alias = aliases[String(model[..<match.lowerBound])] { normalized = alias }
        else { normalized = model }
        return models(for: provider).first(where: { $0.name == normalized })
    }

    static func cost(for entry: TokenEntry) -> Double {
        estimatedCost(for: entry) ?? 0
    }

    static func estimatedCost(for entry: TokenEntry) -> Double? {
        if let reported = entry.reportedCost { return reported }
        guard let spec = spec(provider: entry.provider, model: entry.model) else { return nil }
        let cachedTokens = min(max(0, entry.cachedTokens), max(0, entry.inputTokens))
        let writeTokens = min(max(0, entry.cacheWriteTokens ?? 0), max(0, entry.inputTokens - cachedTokens))
        let longWriteTokens = min(max(0, entry.cacheWrite1hTokens ?? 0), writeTokens)
        let input = Double(max(0, entry.inputTokens - cachedTokens - writeTokens)) / 1_000_000 * spec.inputPerMillion
        let cached = Double(cachedTokens) / 1_000_000 * spec.cachedPerMillion
        let shortMultiplier = entry.provider == .anthropic ? 1.25 : spec.cacheWriteMultiplier
        let longMultiplier = entry.provider == .anthropic ? 2.0 : spec.cacheWriteMultiplier
        let writes = Double(writeTokens - longWriteTokens) / 1_000_000 * spec.inputPerMillion * shortMultiplier
            + Double(longWriteTokens) / 1_000_000 * spec.inputPerMillion * longMultiplier
        let output = Double(max(0, entry.outputTokens)) / 1_000_000 * spec.outputPerMillion
        let longContext = spec.longContextThreshold.map { entry.inputTokens > $0 } ?? false
        return (input + cached + writes) * (longContext ? 2 : 1) + output * (longContext ? 1.5 : 1)
    }

    static func costLabel(for entry: TokenEntry) -> String {
        estimatedCost(for: entry).map { Formatters.currency($0) } ?? missingRateLabel
    }

    static let subscriptionTemplates: [SubscriptionAccount] = [
        SubscriptionAccount(name: "ChatGPT Plus", provider: .openai, planName: "Plus", monthlyPrice: 20, quotaLimit: 0, unlimited: true),
        SubscriptionAccount(name: "Claude Pro", provider: .anthropic, planName: "Pro", monthlyPrice: 20, quotaLimit: 0, unlimited: true),
        SubscriptionAccount(name: "Cursor Pro", provider: .cursor, planName: "Pro", monthlyPrice: 20, quotaLimit: 500, quotaUnit: .fastRequests),
        SubscriptionAccount(name: "GitHub Copilot", provider: .copilot, planName: "Individual", monthlyPrice: 10, unlimited: true),
        SubscriptionAccount(name: "Gemini Advanced", provider: .google, planName: "AI Pro", monthlyPrice: 19.99, unlimited: true),
        SubscriptionAccount(name: "Perplexity Pro", provider: .perplexity, planName: "Pro", monthlyPrice: 20, quotaLimit: 300, quotaUnit: .requests),
        SubscriptionAccount(name: "SuperGrok", provider: .xai, planName: "SuperGrok", monthlyPrice: 30, unlimited: true)
    ]
}
