#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XASH="$ROOT/Build/OpenSourceEngine/xash3d-fwgs"
SDL_FRAMEWORK="$ROOT/Build/XashDevice/SDL2.framework"
OUT="$ROOT/Build/XashRuntime"
APP="$OUT/Payload/BO2IOSCS.app"

[ -d "$XASH" ] || { echo "Xash source tree missing: $XASH"; exit 2; }
[ -d "$SDL_FRAMEWORK" ] || { echo "SDL2.framework missing: $SDL_FRAMEWORK"; exit 3; }

rm -rf "$OUT"
mkdir -p "$APP"

# Install the pinned Xash build through its own iOS install rules.
(
  cd "$XASH"
  ./waf install --destdir="$APP"
)

# Bundle SDL exactly as the engine's native iOS packaging path expects.
cp -R "$SDL_FRAMEWORK" "$APP/SDL2.framework"

# Project-owned bootstrap data only. No proprietary source data enters CI.
cp -R "$ROOT/GameData/XashBootstrap/bo2ioscs" "$APP/bo2ioscs"

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

# Sanity-check expected native runtime products from the install step.
[ -f "$APP/xash" ] || {
  echo "Installed Xash executable missing"
  find "$APP" -maxdepth 4 -print
  exit 4
}
file "$APP/xash"
file "$APP/SDL2.framework/SDL2"

# Ad-hoc sign nested Mach-O code for installability in sideload/re-sign workflows.
while IFS= read -r dylib; do
  codesign --force --sign - --timestamp=none "$dylib"
done < <(find "$APP" -type f -name '*.dylib' -print)

codesign --force --sign - --timestamp=none "$APP/SDL2.framework"
codesign --force --sign - --timestamp=none "$APP/xash"
codesign --force --sign - --timestamp=none "$APP"

(
  cd "$OUT"
  zip -qry BO2IOSCS-Xash-bootstrap.ipa Payload
)

IPA="$OUT/BO2IOSCS-Xash-bootstrap.ipa"
[ -s "$IPA" ] || { echo "Xash bootstrap IPA was not produced"; exit 5; }

unzip -l "$IPA" | grep -q 'Payload/BO2IOSCS.app/xash'
unzip -l "$IPA" | grep -q 'Payload/BO2IOSCS.app/bo2ioscs/gameinfo.txt'
unzip -l "$IPA" | grep -q 'Payload/BO2IOSCS.app/SDL2.framework/SDL2'

cat > "$OUT/XASH_RUNTIME_REPORT.md" <<REPORT
# Xash runtime package

- engine: Xash3D FWGS
- engine commit: 4857b389e6ba32ddaa68582aedcbc950c138f46a
- architecture: arm64 iOS device
- executable: Payload/BO2IOSCS.app/xash
- game directory: bo2ioscs
- proprietary assets included: no
- signing: ad-hoc (intended for later sideload/re-sign workflow)
- gameplay content: bootstrap metadata only; no converted BO2 map/game DLL is present yet
REPORT

echo "Created $IPA"
