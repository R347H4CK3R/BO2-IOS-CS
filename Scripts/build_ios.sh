#!/bin/bash
set -euo pipefail
MODE="${1:-simulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p Build
command -v xcodegen >/dev/null || { echo "xcodegen is required"; exit 2; }

embed_generated_gamedata() {
  local app="$1"
  if [ -d "$ROOT/GeneratedGameData" ]; then
    rm -rf "$app/GeneratedGameData"
    mkdir -p "$app/GeneratedGameData"
    cp -R "$ROOT/GeneratedGameData/." "$app/GeneratedGameData/"
  fi
}

xcodegen generate
case "$MODE" in
  simulator)
    xcodebuild -project BO2IOSCS.xcodeproj -scheme BO2IOSCS -sdk iphonesimulator -configuration Debug -derivedDataPath Build/DerivedData build
    embed_generated_gamedata Build/DerivedData/Build/Products/Debug-iphonesimulator/BO2IOSCS.app
    rm -f Build/SimulatorBuild.zip
    ditto -c -k --sequesterRsrc --keepParent Build/DerivedData/Build/Products/Debug-iphonesimulator/BO2IOSCS.app Build/SimulatorBuild.zip
    ;;
  device)
    xcodebuild -project BO2IOSCS.xcodeproj -scheme BO2IOSCS -destination 'generic/platform=iOS' -configuration Release -derivedDataPath Build/DerivedDataDevice CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS=arm64 build
    embed_generated_gamedata Build/DerivedDataDevice/Build/Products/Release-iphoneos/BO2IOSCS.app
    ;;
  ipa)
    "$0" device
    rm -rf Build/Payload
    mkdir -p Build/Payload
    cp -R Build/DerivedDataDevice/Build/Products/Release-iphoneos/BO2IOSCS.app Build/Payload/
    (cd Build && zip -qry BO2IOSCS-unsigned.ipa Payload)
    ./Tools/validate_ipa.sh Build/BO2IOSCS-unsigned.ipa IPA_VALIDATION_REPORT.md
    ;;
  test)
    python3 -m unittest discover -s Tools/PS3AssetConverter -p 'test_*.py'
    ;;
  *) echo "usage: $0 {simulator|device|ipa|test}" >&2; exit 2 ;;
esac
