#!/bin/bash
set -euo pipefail

IPA="${1:?usage: validate_xash_ipa.sh <ipa> [report]}"
REPORT="${2:-XASH_IPA_VALIDATION_REPORT.md}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$IPA" -d "$TMP"
APP="$TMP/Payload/BO2IOSCS.app"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -d "$APP" ] || fail "BO2IOSCS.app missing"
[ -f "$APP/xash" ] || fail "xash executable missing"
[ -f "$APP/Info.plist" ] || fail "Info.plist missing"
[ -f "$APP/SDL2.framework/SDL2" ] || fail "SDL2.framework missing"
[ -f "$APP/bo2ioscs/gameinfo.txt" ] || fail "bootstrap gameinfo missing"

EXEC_TYPE="$(file "$APP/xash")"
echo "$EXEC_TYPE" | grep -q "Mach-O 64-bit arm64 executable" || fail "xash is not an ARM64 Mach-O executable"

find "$APP" -name '*.dylib' -type f -print > "$TMP/dylibs.txt"
grep -q 'libref_gles1.dylib' "$TMP/dylibs.txt" || fail "GLES1 renderer missing"
grep -q 'libref_gles3compat.dylib' "$TMP/dylibs.txt" || fail "GLES3 compatibility renderer missing"

if find "$APP" -type f | grep -Eiq '\.(ff|ipak|sabs|self|bin)$|EBOOT\.BIN|PS3_GAME'; then
  fail "proprietary/PS3 source-like file unexpectedly present"
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
[ "$BUNDLE_ID" = "com.r347h4ck3r.bo2ioscs.xash" ] || fail "unexpected bundle id: $BUNDLE_ID"
[ "$EXEC_NAME" = "xash" ] || fail "unexpected executable name: $EXEC_NAME"

DYLIB_COUNT="$(wc -l < "$TMP/dylibs.txt" | tr -d ' ')"
APP_BYTES="$(du -sk "$APP" | awk '{print $1 * 1024}')"

cat > "$REPORT" <<EOF
# Xash IPA validation

- status: PASS
- bundle id: $BUNDLE_ID
- executable: $EXEC_NAME
- architecture: arm64
- bundled dylibs: $DYLIB_COUNT
- SDL2 framework: present
- bootstrap gameinfo: present
- proprietary PS3 source-like files: absent
- app bytes (approx): $APP_BYTES
EOF

echo "PASS"
