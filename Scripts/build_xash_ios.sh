#!/bin/bash
set -euo pipefail

MODE="${1:-simulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_ROOT="${XASH_BUILD_ROOT:-$ROOT/Build/OpenSourceEngine}"
XASH_SHA="4857b389e6ba32ddaa68582aedcbc950c138f46a"
SDL2_SHA="b90ac95029d801c5abc59472ba8e2200dff31e1e"
HLSDK_SHA="fe0248bb6de2e61bbb4ece0221e90dc6c4c9dc7b"
XASH="$CACHE_ROOT/xash3d-fwgs"
SDL="$CACHE_ROOT/SDL2"
HLSDK="$CACHE_ROOT/hlsdk-portable"

mkdir -p "$CACHE_ROOT"

clone_pinned() {
  local url="$1" dir="$2" sha="$3"
  if [ ! -d "$dir/.git" ]; then
    git clone --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$sha"
  git -C "$dir" checkout --detach "$sha"
  git -C "$dir" reset --hard "$sha"
}

build_sdl_framework() {
  local sdk="$1"
  local destination="$2"
  local out="$3"

  rm -rf "$out"
  mkdir -p "$out"

  xcodebuild \
    -project "$SDL/Xcode/SDL/SDL.xcodeproj" \
    -target "Framework-iOS" \
    -configuration Release \
    -sdk "$sdk" \
    -destination "$destination" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    IPHONEOS_DEPLOYMENT_TARGET=17.0 \
    CONFIGURATION_BUILD_DIR="$out" \
    CODE_SIGNING_ALLOWED=NO \
    build >&2

  local framework="$out/SDL2.framework"
  [ -d "$framework" ] || {
    echo "SDL2.framework not found in $out"
    find "$out" -maxdepth 3 -print || true
    exit 3
  }
  echo "$framework"
}

clone_pinned https://github.com/libsdl-org/SDL.git "$SDL" "$SDL2_SHA"
clone_pinned https://github.com/FWGS/xash3d-fwgs.git "$XASH" "$XASH_SHA"
clone_pinned https://github.com/FWGS/hlsdk-portable.git "$HLSDK" "$HLSDK_SHA"
git -C "$XASH" submodule update --init --recursive --depth=1
git -C "$HLSDK" submodule update --init --recursive --depth=1

# iOS starts Xash in its writable Documents directory. Our standalone game data
# is bundled read-only inside the .app, so make the engine mount that bundle as
# its read-only root instead of searching Documents for bo2ioscs/gfx.wad.
python3 - "$XASH/engine/platform/ios/launchdialog.m" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = 'void IOS_LaunchDialog( void )\n{\n'
replacement = '''void IOS_LaunchDialog( void )\n{\n\tNSString *bundleRoot = [[NSBundle mainBundle] bundlePath];\n\tif( bundleRoot )\n\t{\n\t\tsetenv( "XASH3D_RODIR", [bundleRoot fileSystemRepresentation], 1 );\n\t\tsetenv( "XASH3D_GAME", "bo2ioscs", 1 );\n\t\tNSLog( @"BO2IOSCS bundle game root: %@", bundleRoot );\n\t}\n'''
if needle not in s:
    raise SystemExit("Xash iOS launchdialog root patch anchor not found")
p.write_text(s.replace(needle, replacement, 1))
PY

# Preserve normal Xash iOS behavior, but add a project-only automation path
# for Simulator CI so the native UIAlert launch dialog does not block simctl.
python3 - "$XASH/engine/platform/ios/launchdialog.m" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = """void IOS_LaunchDialog( void )
{
"""
replacement = """void IOS_LaunchDialog( void )
{
	const char *autotest = getenv( "BO2IOSCS_AUTOTEST" );
	if( !autotest || autotest[0] == '1' )
	{
		const char *testargs[] = { "xash", "-dev", "2", "-log", "-console", "-game", "bo2ioscs", "-nosound", "+exec", "bo2ioscs_runtime.cfg" };
		const int count = (int)( sizeof( testargs ) / sizeof( testargs[0] ) );

		[[NSFileManager defaultManager]
			changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];

		szArgc = count;
		szArgv = calloc( count + 1, sizeof( char * ) );
		for( int i = 0; i < count; ++i )
			szArgv[i] = strdup( testargs[i] );
		szArgv[count] = 0;
		NSLog( @"BO2IOSCS_AUTOTEST launch path enabled" );
		return;
	}
"""
if needle not in text:
    raise SystemExit("Xash iOS launchdialog patch anchor not found")
path.write_text(text.replace(needle, replacement, 1))
PY

# This bootstrap does not use voice capture. Do not request microphone access and
# keep the app audio session ambient so opening it does not duck the user's music.
python3 - "$XASH/engine/platform/ios/launchdialog.m" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace('[[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){}];',
'''AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryAmbient error:nil];
	[session setActive:YES error:nil];''')
p.write_text(s)
PY

build_hlsdk() {
  local sdk="$1"
  local platform="$2"
  local out="$3"
  local gamelibs="$4"
  rm -rf "$out" "$gamelibs"
  mkdir -p "$out" "$gamelibs/cl_dlls" "$gamelibs/dlls"

  cmake -S "$HLSDK" -B "$out" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -D64BIT=ON \
    -DGOLDSOURCE_SUPPORT=OFF \
    -DBUILD_CLIENT=ON \
    -DBUILD_SERVER=ON
  cmake --build "$out" --parallel 2

  local client server
  client="$(find "$out" -type f -name 'client_ios_arm64.dylib' -print -quit)"
  server="$(find "$out" -type f \( -name 'hl_ios_arm64.dylib' -o -name 'server_ios_arm64.dylib' \) -print -quit)"
  [ -n "$client" ] || { echo "HLSDK iOS client library was not produced"; find "$out" -name '*.dylib' -print; exit 6; }
  [ -n "$server" ] || { echo "HLSDK iOS server library was not produced"; find "$out" -name '*.dylib' -print; exit 7; }
  cp "$client" "$gamelibs/cl_dlls/client_ios_arm64.dylib"
  cp "$server" "$gamelibs/dlls/server_ios_arm64.dylib"
  file "$gamelibs/cl_dlls/client_ios_arm64.dylib"
  file "$gamelibs/dlls/server_ios_arm64.dylib"
}

case "$MODE" in
  simulator)
    SDL_FRAMEWORK="$(build_sdl_framework iphonesimulator 'generic/platform=iOS Simulator' "$CACHE_ROOT/sdl-simulator-framework")"

    cd "$XASH"
    rm -rf build
    ./waf configure \
      --ios-simulator \
      --enable-bundled-deps \
      --disable-werror \
      --gamedir bo2ioscs \
      --sdl2 "$SDL_FRAMEWORK"
    ./waf build -j2

    mkdir -p "$ROOT/Build/XashSimulator"
    cp -R build/* "$ROOT/Build/XashSimulator/"
    cp -R "$SDL_FRAMEWORK" "$ROOT/Build/XashSimulator/"
    build_hlsdk iphonesimulator simulator "$CACHE_ROOT/hlsdk-simulator" "$ROOT/Build/XashSimulator/GameLibs"
    ;;

  device)
    SDL_FRAMEWORK="$(build_sdl_framework iphoneos 'generic/platform=iOS' "$CACHE_ROOT/sdl-device-framework")"

    cd "$XASH"
    rm -rf build
    ./waf configure \
      --ios \
      --enable-bundled-deps \
      --disable-werror \
      --gamedir bo2ioscs \
      --sdl2 "$SDL_FRAMEWORK"
    ./waf build -j2

    mkdir -p "$ROOT/Build/XashDevice"
    cp -R build/* "$ROOT/Build/XashDevice/"
    cp -R "$SDL_FRAMEWORK" "$ROOT/Build/XashDevice/"
    build_hlsdk iphoneos device "$CACHE_ROOT/hlsdk-device" "$ROOT/Build/XashDevice/GameLibs"
    ;;

  *)
    echo "usage: $0 {simulator|device}" >&2
    exit 2
    ;;
esac
