#!/bin/bash
set -euo pipefail
umask 077
: "${SPARKLE_TOOLS_DIR:?Missing Sparkle tools directory}"
: "${SPARKLE_PRIVATE_KEY:?Missing Sparkle signing key}"
: "${UPDATE_DMG:?Missing signed update DMG}"
: "${UPDATE_VERSION:?Missing update version}"
: "${UPDATE_ARCH:?Missing update architecture}"
: "${UPDATE_OUTPUT:?Missing appcast output path}"

case "$UPDATE_ARCH" in arm64|x86_64) ;; *) echo 'Invalid update architecture' >&2; exit 1 ;; esac
ts_feed_work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tokensnake-feed.XXXXXX")"
trap 'rm -rf "$ts_feed_work"' EXIT
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$ts_feed_work/private-key"
mkdir "$ts_feed_work/archives"
cp "$UPDATE_DMG" "$ts_feed_work/archives/"
python3 - "$ts_feed_work/archives/$(basename "${UPDATE_DMG%.dmg}").html" <<'PY'
import html,json,os,sys
from pathlib import Path
event=os.environ.get('GITHUB_EVENT_PATH')
release=json.loads(Path(event).read_text()).get('release',{}) if event else {}
notes=release.get('body') or 'TokenSnake '+os.environ['UPDATE_VERSION']+'：功能更新與修正。'
Path(sys.argv[1]).write_text('<pre>'+html.escape(notes)+'</pre>')
PY
"$SPARKLE_TOOLS_DIR/generate_appcast" --ed-key-file "$ts_feed_work/private-key" \
  --download-url-prefix "https://github.com/irons163/TokenSnake/releases/download/v$UPDATE_VERSION/" \
  --link 'https://github.com/irons163/TokenSnake' --embed-release-notes \
  --maximum-deltas 0 --maximum-versions 1 -o "$UPDATE_OUTPUT" "$ts_feed_work/archives"
ts_archive_signature="$("$SPARKLE_TOOLS_DIR/sign_update" --ed-key-file "$ts_feed_work/private-key" -p "$UPDATE_DMG")"
python3 - "$UPDATE_OUTPUT" "$ts_archive_signature" <<'PY'
import base64,sys,xml.etree.ElementTree as ET
namespace='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',namespace)
assert len(base64.b64decode(sys.argv[2],validate=True))==64
tree=ET.parse(sys.argv[1])
enclosures=tree.findall('channel/item/enclosure')
if len(enclosures)!=1: raise SystemExit('Expected one update archive')
enclosures[0].set('{'+namespace+'}edSignature',sys.argv[2])
tree.write(sys.argv[1],encoding='utf-8',xml_declaration=True)
PY
"$SPARKLE_TOOLS_DIR/sign_update" --ed-key-file "$ts_feed_work/private-key" "$UPDATE_OUTPUT"
"$SPARKLE_TOOLS_DIR/sign_update" --verify --ed-key-file "$ts_feed_work/private-key" "$UPDATE_OUTPUT"
python3 "$(dirname "$0")/verify-update-feed.py" "$UPDATE_OUTPUT" \
  --dmg "$UPDATE_DMG" --version "$UPDATE_VERSION" --arch "$UPDATE_ARCH"
