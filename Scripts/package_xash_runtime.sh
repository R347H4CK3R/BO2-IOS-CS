#!/bin/bash
set -euo pipefail

MODE="${1:-device}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XASH="$ROOT/Build/OpenSourceEngine/xash3d-fwgs"

case "$MODE" in
  device)
    ENGINE_BUILD="$ROOT/Build/XashDevice"
    SDL_FRAMEWORK="$ENGINE_BUILD/SDL2.framework"
    OUT="$ROOT/Build/XashRuntime"
    APP="$OUT/Payload/BO2IOSCS.app"
    ;;
  simulator)
    ENGINE_BUILD="$ROOT/Build/XashSimulator"
    SDL_FRAMEWORK="$ENGINE_BUILD/SDL2.framework"
    OUT="$ROOT/Build/XashSimulatorRuntime"
    APP="$OUT/BO2IOSCS.app"
    ;;
  *)
    echo "usage: $0 {device|simulator}" >&2
    exit 2
    ;;
esac

[ -d "$XASH" ] || { echo "Xash source tree missing: $XASH"; exit 2; }
[ -d "$SDL_FRAMEWORK" ] || { echo "SDL2.framework missing: $SDL_FRAMEWORK"; exit 3; }

rm -rf "$OUT"
mkdir -p "$APP"

(
  cd "$XASH"
  ./waf install --destdir="$APP"
)

cp -R "$SDL_FRAMEWORK" "$APP/SDL2.framework"
mkdir -p "$APP/bo2ioscs"
cp -R "$ROOT/GameData/XashBootstrap/bo2ioscs/." "$APP/bo2ioscs/"
# Integrate project-owned/generated GameData directly into the primary Xash package.
# Proprietary source dumps remain excluded; only committed safe data and optional
# locally generated runtime data are copied.
mkdir -p "$APP/bo2ioscs/GameData"
cp -R "$ROOT/GameData/." "$APP/bo2ioscs/GameData/"
if [ -d "$ROOT/GeneratedGameData" ]; then
  cp -R "$ROOT/GeneratedGameData/." "$APP/bo2ioscs/GameData/"
fi

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>xash</string>
  <key>CFBundleIdentifier</key><string>com.r347h4ck3r.bo2ioscs.xash</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDisplayName</key><string>BO2 iOS CS Xash</string>
  <key>CFBundleName</key><string>BO2IOSCSXash</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>NSMicrophoneUsageDescription</key><string>Voice input may be used by the game runtime.</string>
  <key>UIApplicationSupportsIndirectInputEvents</key><true/>
  <key>UIFileSharingEnabled</key><true/>
  <key>UIRequiredDeviceCapabilities</key>
  <array><string>arm64</string></array>
  <key>UIRequiresFullScreen</key><true/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>
PLIST

[ -f "$APP/xash" ] || {
  echo "Installed Xash executable missing"
  find "$APP" -maxdepth 5 -print
  exit 4
}

file "$APP/xash"
file "$APP/SDL2.framework/SDL2"

while IFS= read -r dylib; do
  codesign --force --sign - --timestamp=none "$dylib"
done < <(find "$APP" -type f -name '*.dylib' -print)

codesign --force --sign - --timestamp=none "$APP/SDL2.framework"
codesign --force --sign - --timestamp=none "$APP/xash"
codesign --force --sign - --timestamp=none "$APP"

if [ "$MODE" = "device" ]; then
  (
    cd "$OUT"
    zip -qry BO2IOSCS-Xash-integrated.ipa Payload
  )

  IPA="$OUT/BO2IOSCS-Xash-integrated.ipa"
  [ -s "$IPA" ] || { echo "Xash bootstrap IPA was not produced"; exit 5; }

  zipinfo -1 "$IPA" > "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/xash' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/gameinfo.txt' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/GameData/validation_map.json' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/GameData/TestData/readable_asset_manifest.json' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/SDL2.framework/SDL2' "$OUT/IPA_CONTENTS.txt"

  cat > "$OUT/XASH_RUNTIME_REPORT.md" <<REPORT
# Xash runtime package

- engine: Xash3D FWGS
- engine commit: 4857b389e6ba32ddaa68582aedcbc950c138f46a
- architecture: arm64 iOS device
- executable: Payload/BO2IOSCS.app/xash
- game directory: bo2ioscs
- proprietary assets included: no
- signing: ad-hoc (intended for later sideload/re-sign workflow)
- gameplay content: project GameData and the safe readable-asset manifest are integrated into the Xash app bundle
- converted BO2 content: included only when legally generated/decrypted or structurally readable inputs are supplied
REPORT

  echo "Created $IPA"
else
  cat > "$OUT/XASH_SIMULATOR_RUNTIME_REPORT.md" <<REPORT
# Xash simulator runtime app

- engine: Xash3D FWGS
- engine commit: 4857b389e6ba32ddaa68582aedcbc950c138f46a
- architecture: arm64 iOS Simulator
- app: BO2IOSCS.app
- automated launch environment: BO2IOSCS_AUTOTEST=1
- proprietary assets included: no
REPORT

  echo "Created $APP"
fi
