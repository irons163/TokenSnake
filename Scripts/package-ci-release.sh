#!/bin/bash
set -euo pipefail
umask 077

ts_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ts_root"
ts_arch="${TOKENSNAKE_ARCH:-arm64}"
ts_mode="${TOKENSNAKE_SIGNING_MODE:-ad-hoc}"
case "$ts_arch" in
  arm64) ts_label=apple-silicon ;;
  x86_64) ts_label=intel ;;
  *) echo 'TOKENSNAKE_ARCH must be arm64 or x86_64' >&2; exit 1 ;;
esac
case "$ts_mode" in ad-hoc|developer-id) ;; *) echo 'Invalid signing mode' >&2; exit 1 ;; esac

if [[ "$ts_mode" == developer-id ]]; then
  for ts_name in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_TEAM_ID \
    APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY_BASE64; do
    if [[ -z "${!ts_name:-}" ]]; then echo "Missing required secret: $ts_name" >&2; exit 1; fi
  done
  [[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid APPLE_TEAM_ID' >&2; exit 1; }
fi

xcodegen generate
ts_version="${TOKENSNAKE_RELEASE_VERSION:-$(python3 Scripts/release_metadata.py --field version)}"
ts_prerelease=false
if [[ "$ts_version" == *-* ]]; then ts_prerelease=true; fi
python3 Scripts/release_metadata.py --tag "v$ts_version" --prerelease "$ts_prerelease" >/dev/null
ts_work="$ts_root/build/ci-release/$ts_arch"
ts_dist="$ts_root/dist"
ts_private="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tokensnake-signing.XXXXXX")"
ts_keychain="$ts_private/build.keychain-db"
ts_search_list="$ts_private/keychain-search-list.json"
cleanup() {
  if [[ -f "$ts_search_list" ]]; then
    python3 - "$ts_search_list" <<'PY' || echo 'Warning: could not restore the original keychain search list' >&2
import json,subprocess,sys
from pathlib import Path
paths=json.loads(Path(sys.argv[1]).read_text())
subprocess.run(['security','list-keychains','-d','user','-s',*paths],check=True)
PY
  fi
  if [[ -f "$ts_keychain" ]]; then security delete-keychain "$ts_keychain" >/dev/null 2>&1 || true; fi
  rm -rf "$ts_private"
}
trap cleanup EXIT
rm -rf "$ts_work"
mkdir -p "$ts_work/staging" "$ts_dist"

if [[ "$ts_mode" == developer-id ]]; then
  echo 'Preparing temporary signing keychain'
  python3 - "$ts_private" <<'PY'
import base64
import os
import sys
from pathlib import Path
for name, secret in [('certificate.p12', 'APPLE_CERTIFICATE_P12_BASE64'), ('notary.p8', 'APPLE_API_PRIVATE_KEY_BASE64')]:
    data = base64.b64decode(''.join(os.environ[secret].split()), validate=True)
    with (Path(sys.argv[1]) / name).open('xb') as output:
        output.write(data)
PY
  python3 - "$ts_search_list" <<'PY'
import json,shlex,subprocess,sys
from pathlib import Path
paths=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
Path(sys.argv[1]).write_text(json.dumps(paths))
PY
  ts_keychain_password="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 32)}"
  security create-keychain -p "$ts_keychain_password" "$ts_keychain"
  security set-keychain-settings -lut 21600 "$ts_keychain"
  security unlock-keychain -p "$ts_keychain_password" "$ts_keychain"
  security import "$ts_private/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security -t cert -f pkcs12 -k "$ts_keychain" >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$ts_keychain_password" "$ts_keychain" >/dev/null
  # codesign needs the identity's keychain on the search list even with --keychain.
  # Preserve the user's existing entries and restore them on every exit path.
  python3 - "$ts_search_list" "$ts_keychain" <<'PY'
import json,subprocess,sys
from pathlib import Path
paths=json.loads(Path(sys.argv[1]).read_text())
subprocess.run(['security','list-keychains','-d','user','-s',sys.argv[2],*paths],check=True)
PY
  ts_identity="$(security find-identity -v -p codesigning "$ts_keychain" | python3 -c '
import os,re,sys
pattern = r"\s+\d+\)\s+([A-Fa-f0-9]{40})\s+\"Developer ID Application: .* \(" + re.escape(os.environ["APPLE_TEAM_ID"]) + r"\)\""
matches = re.findall(pattern, sys.stdin.read())
if len(matches) != 1: raise SystemExit("Expected one valid Developer ID Application identity matching APPLE_TEAM_ID")
print(matches[0])
')"
fi

# Signing material stays in the private directory; app bundles need normal install permissions.
umask 022
printf 'Archiving %s\n' "$ts_arch"
xcodebuild archive -project TokenSnake.xcodeproj -scheme TokenSnake -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ts_work/TokenSnake.xcarchive" \
  -derivedDataPath "$ts_work/DerivedData" ARCHS="$ts_arch" ONLY_ACTIVE_ARCH=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym CODE_SIGNING_ALLOWED=NO -quiet

ts_app="$ts_work/TokenSnake.xcarchive/Products/Applications/TokenSnake.app"
ts_binary="$ts_app/Contents/MacOS/TokenSnake"
ts_dsym="$ts_work/TokenSnake.xcarchive/dSYMs/TokenSnake.app.dSYM"
[[ "$(lipo -archs "$ts_binary")" == "$ts_arch" ]] || { echo 'Unexpected binary architecture' >&2; exit 1; }
[[ -d "$ts_dsym" ]] || { echo 'Archive is missing dSYM' >&2; exit 1; }
ts_binary_uuids="$(dwarfdump --uuid "$ts_binary" | awk '{print $2}' | sort)"
ts_dsym_uuids="$(dwarfdump --uuid "$ts_dsym" | awk '{print $2}' | sort)"
[[ -n "$ts_binary_uuids" && "$ts_binary_uuids" == "$ts_dsym_uuids" ]] || { echo 'dSYM UUID mismatch' >&2; exit 1; }

notarize() {
  local ts_target="$1" ts_log="$2"
  xcrun notarytool submit "$ts_target" --key "$ts_private/notary.p8" \
    --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
    --wait --timeout 20m --output-format json > "$ts_log"
  python3 - "$ts_log" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not Accepted; inspect the submission in App Store Connect')
PY
}

if [[ "$ts_mode" == developer-id ]]; then
  echo 'Signing and notarizing application'
  codesign --force --keychain "$ts_keychain" --sign "$ts_identity" --timestamp --options runtime \
    --entitlements TokenSnake/TokenSnake.entitlements "$ts_app"
  ditto -c -k --sequesterRsrc --keepParent "$ts_app" "$ts_work/notary-app.zip"
  notarize "$ts_work/notary-app.zip" "$ts_work/notary-app.json"
  xcrun stapler staple "$ts_app"
  xcrun stapler validate "$ts_app"
  spctl --assess --type execute "$ts_app"
else
  codesign --force --sign - --options runtime "$ts_app"
fi
codesign --verify --deep --strict "$ts_app"

ts_stem="TokenSnake-$ts_version-$ts_label"
echo 'Creating distribution packages'
ditto "$ts_app" "$ts_work/staging/TokenSnake.app"
ln -s /Applications "$ts_work/staging/Applications"
hdiutil create -volname TokenSnake -srcfolder "$ts_work/staging" -format UDZO -ov "$ts_dist/$ts_stem.dmg"
if [[ "$ts_mode" == developer-id ]]; then
  echo 'Signing and notarizing disk image'
  codesign --force --keychain "$ts_keychain" --sign "$ts_identity" --timestamp "$ts_dist/$ts_stem.dmg"
  notarize "$ts_dist/$ts_stem.dmg" "$ts_work/notary-dmg.json"
  xcrun stapler staple "$ts_dist/$ts_stem.dmg"
  xcrun stapler validate "$ts_dist/$ts_stem.dmg"
fi
ditto -c -k --sequesterRsrc --keepParent "$ts_app" "$ts_dist/$ts_stem.zip"
ditto -c -k --sequesterRsrc --keepParent "$ts_dsym" "$ts_dist/$ts_stem.dSYM.zip"
python3 - "$ts_dist/$ts_stem.build.json" "$ts_version" "$ts_arch" "$ts_mode" "$ts_app/Contents/Info.plist" <<'PY'
import json,plistlib,subprocess,sys
from pathlib import Path
path,version,arch,mode,plist=sys.argv[1:]
info=plistlib.loads(Path(plist).read_bytes())
result={'version':version,'marketingVersion':info['CFBundleShortVersionString'],
        'buildNumber':info['CFBundleVersion'],'architecture':arch,'signingMode':mode,
        'notarized':mode=='developer-id','commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()}
Path(path).write_text(json.dumps(result,indent=2)+'\n')
PY
(
  cd "$ts_dist"
  shasum -a 256 "$ts_stem.dmg" "$ts_stem.zip" "$ts_stem.dSYM.zip" "$ts_stem.build.json" > "$ts_stem.sha256"
)
printf 'Packaged %s (%s, %s)\n' "$ts_version" "$ts_arch" "$ts_mode"
