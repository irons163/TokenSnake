import CryptoKit
import Foundation
import CoreFoundation

nonisolated enum UsageLogParser {
    enum ParseError: Error { case invalidUsage }

    static func parse(_ data: Data, source: UsageSource, context: inout UsageParserContext) throws -> TokenEntry? {
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = record["type"] as? String else { return nil }
        if source == .claudeCode { return try claude(record, type: type) }

        let payload = record["payload"] as? [String: Any] ?? [:]
        if type == "session_meta" {
            context.sessionID = payload["id"] as? String ?? payload["session_id"] as? String ?? context.sessionID
            if let provider = payload["model_provider"] as? String {
                context.provider = provider == "openai" ? .openai : .custom
            }
            return nil
        }
        if type == "turn_context" {
            context.model = payload["model"] as? String ?? context.model
            return nil
        }
        guard let date = date(record["timestamp"]) else { return nil }

        if type == "token_usage_record", let raw = payload["usage"] as? [String: Any] {
            let usage = try codexCounters(raw)
            let session = payload["thread_id"] as? String ?? payload["session_id"] as? String ?? context.sessionID
            let key: String
            if let response = payload["response_id"] as? String {
                key = "codex:response:\(response)"
            } else {
                key = "codex:\(session):\(record["timestamp"] ?? ""):\(usage.key)"
            }
            let parsed = entry(key: key, source: .codex, model: payload["model"] as? String ?? context.model,
                               date: date, usage: usage, provider: context.provider)
            if let parsed {
                var pending = context.pendingCodexEntries ?? []
                pending.append(parsed)
                context.pendingCodexEntries = Array(pending.suffix(16))
            }
            return parsed
        }

        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let rawTotal = info["total_token_usage"] as? [String: Any] else { return nil }
        let total = try codexCounters(rawTotal)
        let previous = context.total
        let didReset = resetCounterIfNeeded(total, context: &context)
        let usage: UsageCounters
        if let last = info["last_token_usage"] as? [String: Any] {
            usage = try codexCounters(last)
        } else if let previous, !didReset {
            usage = total.delta(from: previous)
        } else {
            usage = total
        }
        let key = "codex:legacy:\(record["timestamp"] ?? ""):\(usage.key)"
        // Legacy totals can reset on compaction and include inherited fork history.
        if let index = context.pendingCodexEntries?.firstIndex(where: {
            $0.inputTokens == usage.input && $0.outputTokens == usage.output
                && $0.cachedTokens == usage.cached && ($0.cacheWriteTokens ?? 0) == usage.write
        }), var modern = context.pendingCodexEntries?.remove(at: index) {
            modern.importAliases = [key]
            context.total = total
            return modern
        }
        if total == previous { return nil } // Rate-limit updates repeat the cumulative count.
        context.total = total
        return entry(key: key, source: .codex, model: context.model, date: date,
                     usage: usage, provider: context.provider)
    }

    private static func claude(_ record: [String: Any], type: String) throws -> TokenEntry? {
        guard type == "assistant", let message = record["message"] as? [String: Any],
              let raw = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let id = message["id"] as? String ?? record["requestId"] as? String,
              !id.isEmpty, let date = date(record["timestamp"]) else { return nil }
        let read = try count(raw, "cache_read_input_tokens")
        let write = try count(raw, "cache_creation_input_tokens")
        let base = try count(raw, "input_tokens")
        let usage = UsageCounters(input: base + read + write, cached: read, write: write,
                                  output: try count(raw, "output_tokens"))
        let creation = raw["cache_creation"] as? [String: Any] ?? [:]
        let longWrite = min(write, try count(creation, "ephemeral_1h_input_tokens"))
        return entry(key: "claude:\(id)", source: .claudeCode, model: model, date: date,
                     usage: usage, provider: .anthropic, longWrite: longWrite)
    }

    private static func codexCounters(_ raw: [String: Any]) throws -> UsageCounters {
        UsageCounters(input: try count(raw, "input_tokens"), cached: try count(raw, "cached_input_tokens"),
                      write: try count(raw, "cache_write_input_tokens"), output: try count(raw, "output_tokens"))
    }

    static func count(_ raw: [String: Any], _ key: String) throws -> Int {
        guard let value = raw[key], !(value is NSNull) else { return 0 }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue <= 1_000_000_000_000,
              number.doubleValue.rounded(.down) == number.doubleValue else { throw ParseError.invalidUsage }
        return number.intValue
    }

    @discardableResult
    private static func resetCounterIfNeeded(_ total: UsageCounters, context: inout UsageParserContext) -> Bool {
        if let previous = context.total, total.input < previous.input || total.output < previous.output {
            context.counterGeneration += 1
            return true
        }
        return false
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }

    static func entry(key: String, source: UsageSource, model: String, date: Date,
                      usage: UsageCounters, provider: AIProvider, longWrite: Int = 0) -> TokenEntry? {
        guard usage.hasUsage else { return nil }
        let digest = Array(SHA256.hash(data: Data(key.utf8)))
        let id = UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                             (digest[6] & 0x0f) | 0x50, digest[7], (digest[8] & 0x3f) | 0x80,
                             digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
        return TokenEntry(id: id, createdAt: date, provider: provider,
                          model: model.isEmpty ? "\(source.label)（未知模型）" : model,
                          inputTokens: usage.input, outputTokens: usage.output, cachedTokens: usage.cached,
                          source: source, importID: key, cacheWriteTokens: usage.write, cacheWrite1hTokens: longWrite)
    }
}
