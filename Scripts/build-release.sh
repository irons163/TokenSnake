#!/bin/bash
set -euo pipefail

tokensnake_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$tokensnake_root"
command -v xcodegen >/dev/null
xcodegen generate
xcodebuild build \
  -project TokenSnake.xcodeproj \
  -scheme TokenSnake \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -quiet

/usr/bin/ditto build/DerivedData/Build/Products/Release/TokenSnake.app build/TokenSnake.app
/usr/bin/codesign --verify --deep --strict build/TokenSnake.app
tokensnake_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/TokenSnake.app/Contents/Info.plist)
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/TokenSnake.app "build/TokenSnake-${tokensnake_version}-macOS.zip"
printf 'App: %s/build/TokenSnake.app\nZIP: %s/build/TokenSnake-%s-macOS.zip\n' "$tokensnake_root" "$tokensnake_root" "$tokensnake_version"
