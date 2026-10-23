#!/bin/bash
set -euo pipefail
ts_developer_dir="$(python3 - <<'PY'
import plistlib
import re
from pathlib import Path

choices = []
for app in Path('/Applications').glob('Xcode*.app'):
    try:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version = str(info['CFBundleShortVersionString'])
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version):
            continue
        numbers = tuple(map(int, version.split('.')))
        if numbers[0] >= 26:
            choices.append((numbers, str(app.resolve() / 'Contents/Developer')))
    except (OSError, KeyError, ValueError):
        continue
if not choices:
    raise SystemExit('Xcode 26 or newer is required; no supported stable installation found')
print(max(choices)[1])
PY
)"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DEVELOPER_DIR=%s\n' "$ts_developer_dir" >> "$GITHUB_ENV"
fi
DEVELOPER_DIR="$ts_developer_dir" xcodebuild -version
printf 'Selected %s\n' "$ts_developer_dir"
