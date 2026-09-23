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
[ -f "$APP/bo2ioscs/gameinfo.txt" ] || fail "gameinfo missing"
[ -f "$APP/bo2ioscs/gfx.wad" ] || fail "standalone gfx.wad missing"
python3 - "$APP/bo2ioscs/gfx.wad" <<'PY' || fail "standalone gfx.wad is invalid"
import struct, sys
from pathlib import Path
b = Path(sys.argv[1]).read_bytes()
assert len(b) >= 12 and b[:4] == b"WAD3"
count, directory = struct.unpack("<ii", b[4:12])
assert count >= 0 and 12 <= directory <= len(b)
PY
[ -f "$APP/bo2ioscs/autoexec.cfg" ] || fail "generated runtime config missing"
grep -q 'BO2IOSCS_GAMEDATA_CONFIG_LOADED' "$APP/bo2ioscs/autoexec.cfg" || fail "runtime config marker missing"
[ -f "$APP/bo2ioscs/GameData/validation_map.json" ] || fail "normalized map missing"
[ -f "$APP/bo2ioscs/GameData/TestData/readable_asset_manifest.json" ] || fail "readable asset manifest missing"
[ -f "$APP/bo2ioscs/bo2ioscs_runtime.cfg" ] || fail "generated runtime metadata config missing"
grep -q "^echo BO2IOSCS_RUNTIME_METADATA_LOADED$" "$APP/bo2ioscs/bo2ioscs_runtime.cfg" || fail "runtime metadata execution marker missing"

EXEC_TYPE="$(file "$APP/xash")"
# `file` describes thin binaries as "Mach-O 64-bit executable arm64" and may
# describe universal binaries differently. Validate the actual Mach-O slices
# with lipo instead of depending on word order in human-readable `file` output.
ARCHS="$(lipo -archs "$APP/xash" 2>/dev/null || true)"
echo "$ARCHS" | tr ' ' '\n' | grep -qx 'arm64' || fail "xash has no ARM64 Mach-O slice: $EXEC_TYPE"

find "$APP" -name '*.dylib' -type f -print > "$TMP/dylibs.txt"
grep -q 'libref_gles1.dylib' "$TMP/dylibs.txt" || fail "GLES1 renderer missing"
grep -q 'libref_gles3compat.dylib' "$TMP/dylibs.txt" || fail "GLES3 compatibility renderer missing"

if find "$APP" -type f | grep -Eiq '\.(ff|ipak|sabs|self)$|EBOOT\.BIN|PS3_GAME'; then
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
- architecture slices: $ARCHS
- bundled dylibs: $DYLIB_COUNT
- SDL2 framework: present
- gameinfo: present
- generated GameData runtime config: present
- normalized GameData map: present
- readable asset manifest: present
- generated runtime metadata config: present
- proprietary PS3 source-like files: absent
- app bytes (approx): $APP_BYTES
EOF

echo "PASS"
