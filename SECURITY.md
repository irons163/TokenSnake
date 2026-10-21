# Security and privacy

TokenSnake runs locally on macOS. The application has no network client, telemetry,
cloud account connection, or runtime package download. It reads usage metadata from
the configured Codex and Claude Code log directories. It does not intentionally
open authentication files or persist conversation messages and tool output.

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
  line limit. Invalid or oversized log lines are skipped. Unreadable sources are
  reported without discarding existing usage.
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
has been found. The repository has no third-party runtime package dependencies.

## Reporting a vulnerability

Use the private vulnerability reporting option on the repository's
[Security page](https://github.com/irons163/TokenSnake/security).
Do not put credentials, raw conversations, real usage stores, or personal billing
details in public issues. A minimal synthetic reproducer is preferred.
