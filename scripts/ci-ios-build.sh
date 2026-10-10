#!/usr/bin/env bash
#
# ci-ios-build.sh — build and verify the iPadOS artifacts.
#
# This holds the actual CI logic so that:
#   * it can be linted (shellcheck) and reasoned about outside a workflow runner
#   * the GitHub Actions file stays small and declarative
#   * a local Mac can run exactly what CI runs, with no divergence
#
# Usage:
#   scripts/ci-ios-build.sh core     arm64 iPadOS core library + verification
#   scripts/ci-ios-build.sh sim      simulator core library (arch-conditional check)
#   scripts/ci-ios-build.sh app      SwiftUI app, simulator + unsigned device
#   scripts/ci-ios-build.sh link <path-to-libflycast.a>   link engine into app
#
# Environment:
#   DEEZRETRO_WORK   scratch root (default: <repo>/build)
#   FLYCAST_SHA      pin to check out (default: the Phase 2 pin)
#   SKIP_FETCH=1     assume engines/ is already present and patched
#
# NOTHING here proves the emulator works. It proves the artifacts build.
# Runtime behaviour needs a physical iPad. See docs/PHASE2-BUILD-REPORT.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${DEEZRETRO_WORK:-$ROOT/build}"
FLYCAST_SHA="${FLYCAST_SHA:-ed953fcbfdd1b8a7521d2966b13cc700c7e2d233}"
SRC="$ROOT/engines/flycast"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

log()  { printf '\n=== %s ===\n' "$*"; }
fail() { printf '\n!!! %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# CMake must be 3.x, and this is not cosmetic.
#
# CMake 4 removed compatibility with cmake_minimum_required(VERSION < 3.5), and
# Flycast's bundled core/deps/libchdr/deps/zlib-1.3.1/CMakeLists.txt declares
# `cmake_minimum_required(VERSION 2.4.4...3.15.0)`. That dependency is added
# whenever WITH_SYSTEM_ZLIB is not already set (Flycast CMakeLists.txt:583).
# GitHub's macOS runners ship CMake 4.x, so the configure aborts.
#
# Reproduced locally: CMake 4.4.4 failed, CMake 3.31.6 succeeded.
# ---------------------------------------------------------------------------
CMAKE_VERSION="${CMAKE_VERSION:-3.31.6}"

ensure_cmake() {
  local v=""
  if command -v cmake >/dev/null 2>&1; then
    v="$(cmake --version | head -1 | sed -E 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/')"
  fi
  case "$v" in
    3.*)
      echo "cmake $v from PATH is acceptable (3.x)"
      return 0
      ;;
    "")
      echo "no cmake on PATH; installing $CMAKE_VERSION"
      ;;
    *)
      echo "cmake $v is too new (CMake 4 cannot configure this dependency tree); installing $CMAKE_VERSION"
      ;;
  esac

  local dir="$HOME/toolchain/cmake-${CMAKE_VERSION}-macos-universal/CMake.app/Contents/bin"
  if [ ! -x "$dir/cmake" ]; then
    local url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-macos-universal.tar.gz"
    echo "downloading $url"
    mkdir -p "$HOME/toolchain"
    curl -fsSL "$url" -o /tmp/cmake-pin.tar.gz
    tar -xzf /tmp/cmake-pin.tar.gz -C "$HOME/toolchain"
  fi
  [ -x "$dir/cmake" ] || fail "pinned cmake not found at $dir"
  export PATH="$dir:$PATH"
  echo "using $(cmake --version | head -1) from $dir"
}

# ---------------------------------------------------------------------------
# Shared: fetch the pinned engine and apply our patches.
# ---------------------------------------------------------------------------
fetch_engine() {
  log "fetch pinned Flycast $FLYCAST_SHA"
  if [ ! -d "$SRC/core" ]; then
    mkdir -p "$ROOT/engines"
    git clone https://github.com/flyinghead/flycast.git "$SRC"
  fi
  git -C "$SRC" fetch --depth 1 origin "$FLYCAST_SHA" 2>/dev/null || git -C "$SRC" fetch origin
  git -C "$SRC" checkout --detach "$FLYCAST_SHA"
  git -C "$SRC" submodule update --init --recursive --depth 1
  echo "Flycast at $(git -C "$SRC" rev-parse HEAD)"

  log "apply Deez Retro patches"
  shopt -s nullglob
  for p in "$ROOT"/patches/*.patch; do
    echo "  applying $(basename "$p")"
    git -C "$SRC" apply --verbose "$p"
  done
  grep -q DEEZRETRO_CORE_LIBRARY "$SRC/CMakeLists.txt" \
    || fail "patch did not reach CMakeLists.txt"
  echo "  patch verified present"
}

# ---------------------------------------------------------------------------
# Configure flags. Kept in one place so core/sim/link cannot drift.
#
# USE_OPENGL is deliberately NOT set to OFF. On iOS it does not mean desktop GL:
# the platform branch force-defines GLES/GLES3/HAVE_OPENGLES3
# (Flycast CMakeLists.txt:313-315). And core/wsi/CMakeLists.txt only compiles
# gl_context.cpp / osx.cpp inside if(USE_OPENGL), while on iOS
# GLGraphicsContext::Create() dispatches to OSXGraphicsContext
# (core/wsi/gl_context.cpp:105-106). Turning it off breaks the iOS link.
# ---------------------------------------------------------------------------
common_flags() {
  cat <<'EOF'
-DDEEZRETRO_CORE_LIBRARY=ON
-DDEEZRETRO_NO_REC=ON
-DUSE_VULKAN=OFF
-DUSE_DX9=OFF
-DUSE_DX11=OFF
-DUSE_BREAKPAD=OFF
-DUSE_DISCORD=OFF
-DUSE_LUA=OFF
-DUSE_OPENMP=OFF
-DUSE_HOST_LIBZIP=OFF
-DUSE_HOST_LIBCHDR=OFF
-DUSE_LIBCDIO=OFF
EOF
}

# ---------------------------------------------------------------------------
# core: the ARM64 milestone.
# ---------------------------------------------------------------------------
cmd_core() {
  ensure_cmake
  [ "${SKIP_FETCH:-0}" = "1" ] || fetch_engine

  local bld="$WORK/flycast-ios"
  log "configure: arm64 iPadOS, interpreter-only, core library"
  # shellcheck disable=SC2046
  cmake -S "$SRC" -B "$bld" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
    $(common_flags) 2>&1 | tee "$WORK/configure.log"

  log "build core library (the ARM64 gate)"
  cmake --build "$bld" --config Release --target flycast -j "$NCPU" 2>&1 \
    | tee "$WORK/build.log"

  cmd_verify
}

cmd_verify() {
  log "verify architecture and symbols"
  local lib
  lib="$(find "$WORK/flycast-ios" -name 'libflycast.a' -print -quit)"
  [ -n "$lib" ] || { find "$WORK/flycast-ios" -name '*.a' | head -20; fail "no libflycast.a produced"; }
  echo "library: $lib"
  lipo -info "$lib"
  file "$lib"
  lipo -info "$lib" | grep -q arm64 || fail "library is not arm64"
  echo "object members: $(ar t "$lib" | wc -l | tr -d ' ')"

  echo "--- symbols Bridge/DeezRetroCore.mm calls ---"
  local missing=0
  for sym in flycast_init flycast_term mainui_init mainui_rend_frame \
             dc_savestate dc_loadstate dc_savestateAllowed; do
    if nm "$lib" 2>/dev/null | grep -qE "[[:space:]]_?${sym}\$"; then
      echo "  OK      $sym"
    else
      echo "  MISSING $sym"
      missing=$((missing + 1))
    fi
  done

  log "confirm interpreter-only took effect"
  # core/build.h maps TARGET_NO_REC -> FEAT_SHREC/AREC/DSPREC == DYNAREC_NONE, so
  # the recompilers compile to empty translation units. This is the property that
  # removes the iPadOS JIT requirement, so it is asserted, not assumed.
  if nm "$lib" 2>/dev/null | grep -qiE 'Get_Sh4Recompiler|rec_arm64|Sh4Recompiler'; then
    fail "recompiler symbols present - TARGET_NO_REC did not take effect"
  fi
  echo "  no recompiler symbols: interpreter-only confirmed"
  if nm "$lib" 2>/dev/null | grep -qiE 'Sh4Interpreter|Sh4Interp'; then
    echo "  interpreter symbols present"
  else
    echo "  NOTE: no interpreter symbols matched; check the symbol filter"
  fi

  [ "$missing" -eq 0 ] || fail "$missing required symbol(s) absent"
  echo
  echo "CORE VERIFICATION PASSED: arm64 iPadOS interpreter-only libflycast.a"
}

# ---------------------------------------------------------------------------
# sim: simulator core. Catches arch-conditional breakage the device build hides.
# ---------------------------------------------------------------------------
cmd_sim() {
  ensure_cmake
  [ "${SKIP_FETCH:-0}" = "1" ] || fetch_engine
  local bld="$WORK/flycast-sim"
  log "configure: arm64 iOS simulator, interpreter-only"
  # shellcheck disable=SC2046
  cmake -S "$SRC" -B "$bld" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    $(common_flags) 2>&1 | tee "$WORK/configure-sim.log"
  log "build simulator core"
  cmake --build "$bld" --config Release --target flycast -j "$NCPU" 2>&1 \
    | tee "$WORK/build-sim.log"
  echo "simulator core built"
}

# ---------------------------------------------------------------------------
# app: the SwiftUI app, engine NOT linked (DEEZRETRO_HAVE_FLYCAST=0).
# ---------------------------------------------------------------------------
cmd_app() {
  log "generate the Xcode project"
  ( cd "$ROOT" && xcodegen generate )
  xcodebuild -project "$ROOT/DeezRetro.xcodeproj" -list

  log "build app for iOS Simulator"
  xcodebuild -project "$ROOT/DeezRetro.xcodeproj" -scheme DeezRetro \
    -sdk iphonesimulator -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$WORK/app-simulator.log"

  log "build app for arm64 device (unsigned)"
  xcodebuild -project "$ROOT/DeezRetro.xcodeproj" -scheme DeezRetro \
    -sdk iphoneos -configuration Release \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    build 2>&1 | tee "$WORK/app-device.log"

  log "verify app architecture"
  local app
  app="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name 'DeezRetro.app' \
          -path '*Release-iphoneos*' -print -quit || true)"
  if [ -z "$app" ]; then
    echo "NOTE: device .app not found in DerivedData; skipping arch check"
    return 0
  fi
  echo "app: $app"
  lipo -info "$app/DeezRetro"
  lipo -info "$app/DeezRetro" | grep -q arm64 || fail "app is not arm64"
  echo "APP VERIFICATION PASSED"
}

# ---------------------------------------------------------------------------
# link: engine linked into the app. Beyond the stated milestone; expected to
# surface the first real integration errors, which is the point.
# ---------------------------------------------------------------------------
cmd_link() {
  local lib="${1:-}"
  [ -n "$lib" ] || fail "usage: ci-ios-build.sh link <path-to-libflycast.a>"
  [ -f "$lib" ] || fail "no such library: $lib"
  lipo -info "$lib"

  log "generate the Xcode project"
  ( cd "$ROOT" && xcodegen generate )

  log "build app with the engine linked"
  # $(inherited) is Xcode build-setting syntax, not shell syntax, so the value
  # must stay single-quoted to stop the shell expanding it.
  # shellcheck disable=SC2016
  xcodebuild -project "$ROOT/DeezRetro.xcodeproj" -scheme DeezRetro \
    -sdk iphoneos -configuration Release \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    GCC_PREPROCESSOR_DEFINITIONS='$(inherited) DEEZRETRO_HAVE_FLYCAST=1 GL_SILENCE_DEPRECATION=1 GLES_SILENCE_DEPRECATION=1' \
    DEEZRETRO_CORE_LIB="$lib" \
    build 2>&1 | tee "$WORK/app-linked.log"
  echo "LINK PASSED: engine linked into the app"
}

case "${1:-}" in
  core) cmd_core ;;
  sim)  cmd_sim ;;
  app)  cmd_app ;;
  link) shift; cmd_link "${1:-}" ;;
  *)
    cat >&2 <<EOF
usage: $(basename "$0") <command>

  core   build + verify the arm64 iPadOS interpreter-only core library
  sim    build the simulator core
  app    build the SwiftUI app (simulator + unsigned device)
  link <libflycast.a>   link the engine into the app

env: DEEZRETRO_WORK, FLYCAST_SHA, SKIP_FETCH=1
EOF
    exit 2
    ;;
esac
