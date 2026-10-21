#!/usr/bin/env python3
"""Independently reconcile a fresh App snapshot against its committed JSONL cursors.

Reads local usage metadata only; prints aggregate counts. Use a snapshot without
manually hidden imports, such as one created with --data-directory for verification.
"""
import argparse
import collections
import json
from pathlib import Path


def counters(usage, source):
    cached = usage.get("cache_read_input_tokens" if source == "claudeCode" else "cached_input_tokens", 0)
    write = usage.get("cache_creation_input_tokens" if source == "claudeCode" else "cache_write_input_tokens", 0)
    input_tokens = usage.get("input_tokens", 0) + (cached + write if source == "claudeCode" else 0)
    return input_tokens, usage.get("output_tokens", 0), cached, write


def reconcile(path):
    store = json.loads(path.read_text())
    state = store["localSyncState"]
    if state.get("ignoredImportIDs"):
        raise ValueError("Use a fresh snapshot without hidden imports.")
    responses = {"codex": {}, "claudeCode": {}}
    legacy_responses = {}
    mirrored_legacy = set()
    for key, cursor in state["checkpoints"].items():
        source, filename = key.split(":", 1)
        records = []
        with Path(filename).open("rb") as stream:
            while stream.tell() < cursor["offset"]:
                line = stream.readline()
                if not line or stream.tell() > cursor["offset"]:
                    break
                try:
                    records.append(json.loads(line))
                except (ValueError, UnicodeDecodeError):
                    continue
        modern = [r for r in records if r.get("type") == "token_usage_record"]
        if source == "codex":
            for record in modern:
                payload = record["payload"]
                identity = payload.get("response_id")
                if not identity:
                    raise ValueError("Modern Codex record lacks response_id; extend the independent verifier.")
                responses[source][identity] = counters(payload["usage"], source)
            previous = (0, 0, 0, 0)
            legacy_in_file = []
            for index, record in enumerate(records):
                payload = record.get("payload", {})
                if record.get("type") != "event_msg" or payload.get("type") != "token_count":
                    continue
                info = payload.get("info") or {}
                if not info.get("total_token_usage"):
                    continue
                total = counters(info["total_token_usage"], source)
                if total == previous:
                    continue
                if total[0] < previous[0] or total[1] < previous[1]:
                    previous = (0, 0, 0, 0)
                usage = counters(info["last_token_usage"], source) if info.get("last_token_usage") else tuple(max(0, new - old) for new, old in zip(total, previous))
                identity = (record["timestamp"], usage)
                if usage[0] or usage[1]:
                    legacy_responses[identity] = usage
                    legacy_in_file.append((index, identity, usage))
                previous = total
            # Reconcile the full file in reverse: a legacy event represents a
            # modern response when its per-request counters match an earlier
            # response record, even if cumulative counters or timestamps differ.
            claimed = set()
            for index in reversed(range(len(records))):
                record = records[index]
                if record.get("type") != "token_usage_record":
                    continue
                usage = counters(record["payload"]["usage"], source)
                following = [(i, identity) for i, identity, value in legacy_in_file
                             if i > index and value == usage and i not in claimed]
                if following:
                    i, identity = min(following)
                    claimed.add(i)
                    mirrored_legacy.add(identity)
        else:
            for record in records:
                message = record.get("message") or {}
                if record.get("type") != "assistant" or not message.get("usage"):
                    continue
                if message.get("model", "<unknown>").startswith("<"):
                    continue
                identity = message.get("id") or record.get("requestId")
                if not identity or not record.get("timestamp"):
                    continue
                usage = counters(message["usage"], source)
                old = responses[source].get(identity, (0, 0, 0, 0))
                responses[source][identity] = tuple(max(a, b) for a, b in zip(old, usage))
    for identity, usage in legacy_responses.items():
        if identity not in mirrored_legacy:
            responses["codex"][("legacy", identity)] = usage
    report = {}
    for source, records in responses.items():
        expected = tuple(sum(values[i] for values in records.values()) for i in range(4))
        imported = [entry for entry in store["entries"] if entry.get("source") == source]
        actual = tuple(sum(entry.get(key, 0) or 0 for entry in imported)
                       for key in ["inputTokens", "outputTokens", "cachedTokens", "cacheWriteTokens"])
        matched = actual == expected and len(imported) == len(records)
        report[source] = {"matched": matched, "responses": len(records), "imported": len(imported),
                          "expected": expected, "actual": actual}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return all(item["matched"] for item in report.values())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    arguments = parser.parse_args()
    raise SystemExit(0 if reconcile(arguments.snapshot) else 1)
