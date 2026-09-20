#!/bin/bash
set -euo pipefail
MODE="${1:-simulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_ROOT="${XASH_BUILD_ROOT:-$ROOT/Build/OpenSourceEngine}"
XASH_SHA="4857b389e6ba32ddaa68582aedcbc950c138f46a"
SDL2_SHA="b90ac95029d801c5abc59472ba8e2200dff31e1e"
XASH="$CACHE_ROOT/xash3d-fwgs"
SDL="$CACHE_ROOT/SDL2"

mkdir -p "$CACHE_ROOT"

clone_pinned() {
  local url="$1" dir="$2" sha="$3"
  if [ ! -d "$dir/.git" ]; then
    git clone --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$sha"
  git -C "$dir" checkout --detach "$sha"
}

clone_pinned https://github.com/libsdl-org/SDL.git "$SDL" "$SDL2_SHA"
clone_pinned https://github.com/FWGS/xash3d-fwgs.git "$XASH" "$XASH_SHA"
git -C "$XASH" submodule update --init --recursive --depth=1

case "$MODE" in
  simulator)
    SDL_BUILD="$CACHE_ROOT/sdl-simulator"
    cmake -S "$SDL" -B "$SDL_BUILD" -G Xcode       -DCMAKE_SYSTEM_NAME=iOS       -DCMAKE_OSX_SYSROOT=iphonesimulator       -DCMAKE_OSX_ARCHITECTURES=arm64       -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0       -DSDL_FRAMEWORK=ON       -DSDL_TEST=OFF
    cmake --build "$SDL_BUILD" --config Release
    SDL_FRAMEWORK="$(find "$SDL_BUILD" -type d -name 'SDL2.framework' -print -quit)"
    [ -n "$SDL_FRAMEWORK" ] || { echo "SDL2.framework not found"; exit 3; }

    cd "$XASH"
    ./waf configure --ios-simulator --enable-bundled-deps --disable-werror --gamedir bo2ioscs --sdl2 "$SDL_FRAMEWORK"
    ./waf build -j2
    mkdir -p "$ROOT/Build/XashSimulator"
    cp -R build/* "$ROOT/Build/XashSimulator/" 2>/dev/null || true
    ;;
  device)
    SDL_BUILD="$CACHE_ROOT/sdl-device"
    cmake -S "$SDL" -B "$SDL_BUILD" -G Xcode       -DCMAKE_SYSTEM_NAME=iOS       -DCMAKE_OSX_SYSROOT=iphoneos       -DCMAKE_OSX_ARCHITECTURES=arm64       -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0       -DSDL_FRAMEWORK=ON       -DSDL_TEST=OFF
    cmake --build "$SDL_BUILD" --config Release
    SDL_FRAMEWORK="$(find "$SDL_BUILD" -type d -name 'SDL2.framework' -print -quit)"
    [ -n "$SDL_FRAMEWORK" ] || { echo "SDL2.framework not found"; exit 3; }

    cd "$XASH"
    ./waf configure --ios --enable-bundled-deps --disable-werror --gamedir bo2ioscs --sdl2 "$SDL_FRAMEWORK"
    ./waf build -j2
    mkdir -p "$ROOT/Build/XashDevice"
    cp -R build/* "$ROOT/Build/XashDevice/" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 {simulator|device}" >&2
    exit 2
    ;;
esac
