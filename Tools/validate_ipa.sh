#!/bin/bash
set -euo pipefail
IPA="${1:-Build/BO2IOSCS-unsigned.ipa}"
REPORT="${2:-IPA_VALIDATION_REPORT.md}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
echo "# IPA Validation Report" > "$REPORT"
unzip -t "$IPA" >/dev/null || { echo "- FAIL: invalid zip" >> "$REPORT"; exit 1; }
echo "- PASS: valid zip" >> "$REPORT"
unzip -q "$IPA" -d "$TMP"
APP_COUNT="$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')"
[ "$APP_COUNT" -eq 1 ] || { echo "- FAIL: expected exactly one .app, found $APP_COUNT" >> "$REPORT"; exit 1; }
APP="$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || { echo "- FAIL: Info.plist missing" >> "$REPORT"; exit 1; }
EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST" 2>/dev/null || echo unknown)
EXE="$APP/$EXE_NAME"
[ -f "$EXE" ] || { echo "- FAIL: executable missing" >> "$REPORT"; exit 1; }
ARCHS="$(lipo -archs "$EXE" 2>/dev/null || true)"
echo "- Bundle ID: $BUNDLE_ID" >> "$REPORT"
echo "- Executable: $EXE_NAME" >> "$REPORT"
echo "- Minimum OS: $MIN_OS" >> "$REPORT"
echo "- Architectures: $ARCHS" >> "$REPORT"
[[ "$ARCHS" == *arm64* ]] || { echo "- FAIL: arm64 missing" >> "$REPORT"; fail=1; }
[[ "$ARCHS" != *x86_64* ]] || { echo "- FAIL: x86_64 present" >> "$REPORT"; fail=1; }
[ -f "$APP/test_map.json" ] || { echo "- FAIL: test_map.json missing" >> "$REPORT"; fail=1; }
DEPS="$(otool -L "$EXE" 2>/dev/null || true)"
if echo "$DEPS" | grep -qi steam; then echo "- FAIL: Steam dependency" >> "$REPORT"; fail=1; else echo "- PASS: no Steam dependency" >> "$REPORT"; fi
if strings "$EXE" | grep -E '/Users/[^/]+' >/dev/null; then echo "- FAIL: developer-machine path found" >> "$REPORT"; fail=1; else echo "- PASS: no absolute developer-machine paths" >> "$REPORT"; fi
codesign -dv "$APP" >/dev/null 2>&1 && echo "- Signature: present" >> "$REPORT" || echo "- Signature: unsigned (expected for CI)" >> "$REPORT"
[ "$fail" -eq 0 ] && echo "- RESULT: PASS" >> "$REPORT" || echo "- RESULT: FAIL" >> "$REPORT"
exit "$fail"
