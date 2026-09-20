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
mapfile -t apps < <(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app')
[ "${#apps[@]}" -eq 1 ] || { echo "- FAIL: expected exactly one .app" >> "$REPORT"; exit 1; }
APP="${apps[0]}"
PLIST="$APP/Info.plist"
EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
EXE="$APP/$EXE_NAME"
ARCHS="$(lipo -archs "$EXE" 2>/dev/null || true)"
echo "- Bundle ID: $BUNDLE_ID" >> "$REPORT"
echo "- Architectures: $ARCHS" >> "$REPORT"
[[ "$ARCHS" == *arm64* ]] || { echo "- FAIL: arm64 missing" >> "$REPORT"; fail=1; }
[[ "$ARCHS" != *x86_64* ]] || { echo "- FAIL: x86_64 present" >> "$REPORT"; fail=1; }
[ -f "$APP/test_map.json" ] || { echo "- FAIL: test_map.json missing" >> "$REPORT"; fail=1; }
if otool -L "$EXE" | grep -qi steam; then echo "- FAIL: Steam dependency" >> "$REPORT"; fail=1; else echo "- PASS: no Steam dependency" >> "$REPORT"; fi
if strings "$EXE" | grep -E '/Users/[^/]+' >/dev/null; then echo "- FAIL: developer-machine path found" >> "$REPORT"; fail=1; else echo "- PASS: no absolute developer-machine paths" >> "$REPORT"; fi
codesign -dv "$APP" >/dev/null 2>&1 && echo "- Signature: present" >> "$REPORT" || echo "- Signature: unsigned" >> "$REPORT"
[ "$fail" -eq 0 ] && echo "- RESULT: PASS" >> "$REPORT" || echo "- RESULT: FAIL" >> "$REPORT"
exit "$fail"
