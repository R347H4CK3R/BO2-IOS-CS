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

# Host_InitCommon does not merely require a file named gfx.wad: it checks for
# the virtual resource gfx/conchars. Generate a project-owned WAD3 containing
# that exact 256x64 raw console-font lump so standalone Xash can initialize
# without copying Valve/Half-Life data.
python3 - "$APP/bo2ioscs/gfx.wad" <<'PY'
import struct, sys
from pathlib import Path

out = Path(sys.argv[1])
pixels = bytearray(256 * 64)

# Minimal visible 8x8-cell diagnostic glyph sheet. The exact artwork is
# project-owned; Xash's legacy conchars loader expects exactly 16384 bytes.
for ch in range(256):
    ox = (ch & 31) * 8
    oy = (ch >> 5) * 8
    for y in range(1, 7):
        for x in range(1, 7):
            if ((x + y + ch) & 3) == 0:
                pixels[(oy + y) * 256 + ox + x] = 254

data_offset = 12
directory_offset = data_offset + len(pixels)
name = b"conchars" + b"\0" * 8
entry = struct.pack("<iiiBBH16s", data_offset, len(pixels), len(pixels), 68, 0, 0, name)
blob = b"WAD3" + struct.pack("<ii", 1, directory_offset) + bytes(pixels) + entry
out.write_bytes(blob)

b = out.read_bytes()
assert b[:4] == b"WAD3"
assert struct.unpack("<i", b[4:8])[0] == 1
assert b[directory_offset + 16:directory_offset + 24].rstrip(b"\0") == b"conchars"
PY
# Integrate project-owned/generated GameData directly into the primary Xash package.
# Proprietary source dumps remain excluded; only committed safe data and optional
# locally generated runtime data are copied.
mkdir -p "$APP/bo2ioscs/GameData"
cp -R "$ROOT/GameData/." "$APP/bo2ioscs/GameData/"
if [ -d "$ROOT/GeneratedGameData" ]; then
  cp -R "$ROOT/GeneratedGameData/." "$APP/bo2ioscs/GameData/"
fi

# Compile normalized project metadata into a tiny Xash config that is executed
# by the native runtime. This consumes only safe JSON metadata already accepted
# by the project and never decrypts or interprets encrypted BO2 fastfiles.
python3 - "$APP/bo2ioscs/GameData/validation_map.json"           "$APP/bo2ioscs/GameData/TestData/readable_asset_manifest.json"           "$APP/bo2ioscs/bo2ioscs_runtime.cfg" <<'PY'
import json, re, sys
from pathlib import Path

map_path, manifest_path, cfg_path = map(Path, sys.argv[1:])
m = json.loads(map_path.read_text())
manifest = json.loads(manifest_path.read_text())

if m.get("format") != "bo2ioscs-normalized-map-v1":
    raise SystemExit("unsupported normalized map format")
if manifest.get("schema") != "bo2ioscs-readable-asset-manifest-v1":
    raise SystemExit("unsupported readable asset manifest")
records = manifest.get("records")
if not isinstance(records, list) or not records:
    raise SystemExit("readable asset manifest is empty")
if any(str(r.get("original_path", "")).lower().endswith(".ff") for r in records):
    raise SystemExit("encrypted fastfile record is not permitted in runtime manifest")

name = re.sub(r"[^A-Za-z0-9_-]", "_", str(m.get("name", "unknown")))[:64]
cfg_path.write_text(
    "echo BO2IOSCS_RUNTIME_METADATA_LOADED\n"
    f"echo BO2IOSCS_NORMALIZED_MAP_{name}\n"
    f"echo BO2IOSCS_READABLE_ASSET_COUNT_{len(records)}\n"
)
PY

# Generate a project-owned Xash startup config from normalized safe metadata so CI
# can prove the engine consumes GameData rather than merely carrying it in the bundle.
python3 - "$APP/bo2ioscs/GameData/validation_map.json"           "$APP/bo2ioscs/GameData/TestData/readable_asset_manifest.json"           "$APP/bo2ioscs/autoexec.cfg" <<'PY'
import json, sys
from pathlib import Path

map_path, manifest_path, out_path = map(Path, sys.argv[1:])
m = json.loads(map_path.read_text())
manifest = json.loads(manifest_path.read_text())
name = str(m.get("name", "unknown")).replace('"', "")
records = manifest.get("records", [])
safe_records = [r for r in records if not str(r.get("original_path", "")).lower().endswith(".ff")]
if len(safe_records) != len(records):
    raise SystemExit("unsafe fastfile record present in readable asset manifest")
Path(out_path).write_text(
    'echo "BO2IOSCS_GAMEDATA_CONFIG_LOADED"\n'
    f'set bo2ioscs_map_name "{name}"\n'
    f'set bo2ioscs_readable_asset_count "{len(safe_records)}"\n'
)
PY

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
  [ -s "$IPA" ] || { echo "Integrated Xash IPA was not produced"; exit 5; }

  zipinfo -1 "$IPA" > "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/xash' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/gameinfo.txt' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/autoexec.cfg' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/GameData/validation_map.json' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/GameData/TestData/readable_asset_manifest.json' "$OUT/IPA_CONTENTS.txt"
  grep -qx 'Payload/BO2IOSCS.app/bo2ioscs/bo2ioscs_runtime.cfg' "$OUT/IPA_CONTENTS.txt"
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
- runtime metadata config: generated and executed by Xash at startup
- runtime config: autoexec.cfg is generated from normalized map/manifest metadata and executed by Xash at startup
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
