# Security and privacy

TokenSnake runs locally on macOS. It has no telemetry or TokenSnake cloud account.
It reads usage metadata from the configured Codex, Claude
Code, and OpenCode data directories. Conversation messages and tool output are not
persisted, and the OpenCode database is opened read-only.

The only usage-sync network client is the optional **Cursor source**, which is off by default.
It exists because Cursor stopped writing token counts to disk. When you switch it on
and confirm the prompt, the app reads Cursor's own login token from
`state.vscdb` (`cursorAuth/accessToken`), sends it to `cursor.com` to fetch your own
usage events, and never logs or stores the token. The request carries only a date
range; no usage counters, prompts, project paths, or conversation content are
uploaded. Automatic sync queries at most once every five minutes, uses an ephemeral
URL session with cookies disabled, and keeps the token in memory for the duration of
the request.

From 1.4.0, the embedded Sparkle updater also contacts GitHub for update feeds and
App downloads. Automatic checks default to once an hour and can be disabled in
settings; automatic downloads are off by default. No usage history, account tokens,
or local project paths are submitted to the update service. Sparkle system profiling
is disabled. Appcasts and DMGs use a dedicated Ed25519 signing key, and signature
validation is required before extraction. The App, embedded Sparkle helpers and DMG
are Developer ID signed and notarized for public releases. The private update key
is kept in the maintainer's Keychain and GitHub Actions secrets, outside public source.

## Local data

- The store contains token counts, model names, timestamps, import identifiers,
  configured directory paths, and any manually entered notes or subscriptions.
  Treat stores and exported backups as private data.
- The default data directory is restricted to the owner. Stores, exports,
  corruption copies, and prior-store backups are written atomically using files
  created with owner-only permissions (`0600`).
- Startup data and restored backups share validation for token counts, cache
  relationships, dates, quotas, duplicate identities, and parser checkpoints.
  Invalid backups do not replace the current store. Invalid startup data is
  preserved for recovery before a fresh store can be written.
- Snapshot reads are limited to 256 MiB. JSONL is read in chunks, with a 16 MiB
  line limit. Invalid or oversized log lines are skipped. OpenCode messages are
  parsed from `opencode.db` without copying conversation content; only token
  counters, model, timestamp, source cost estimate, and the message identifier are retained. Unreadable
  sources are reported without discarding existing usage. Cursor HTTP responses are
  parsed in memory and are not written to disk; only usage counters, model, timestamp,
  and the event identifier are retained.
- Standard log-directory symlinks are supported; descendant symlinks are skipped.
  Only point the app at directories and backups you trust. The app is not sandboxed
  and uses the access permissions granted by macOS.
- Local builds use ad-hoc signatures. A public distributor must arrange their own
  Developer ID signing and notarization; a successful local signature check is not
  notarization.

## Publication review

The initial public source snapshot was prepared on 2026-10-21. Review included
Gitleaks scanning, manual inspection of input parsing and persistence, regression
tests for malformed stores and backups, and Xcode analysis. Personal verification
data, local paths, account snapshots, and private development-history metadata are
excluded from the public history. Tests use synthetic fixtures and temporary data.

This is a bounded source and publication review, not a guarantee that every defect
has been found. The only third-party runtime framework is Sparkle, fixed at 2.10.0
with its package revision recorded in the Xcode project workspace's Package.resolved.

## Reporting a vulnerability

Use the private vulnerability reporting option on the repository's
[Security page](https://github.com/irons163/TokenSnake/security).
Do not put credentials, raw conversations, real usage stores, or personal billing
details in public issues. A minimal synthetic reproducer is preferred.
