#!/usr/bin/env bash
#
# build-flycast-ios.sh — build Flycast's core as a static library for iPadOS arm64.
#
# Run on macOS with full Xcode and CMake >= 3.24.
#
# WHAT THIS PRODUCES
#   build/flycast-ios/Release-iphoneos/libflycast.a   (a linkable core library)
#
# WHY A LIBRARY AND NOT FLYCAST'S iOS APP
#   Flycast already contains a complete iOS app shell
#   (shell/apple/emulator-ios/) with AltKit, storyboards and a UIKit frontend.
#   Deez Retro replaces that frontend with SwiftUI, so we need the *core* as a
#   library. `patches/0001-flycast-core-library.patch` adds that target. See
#   docs/PHASE2-IOS-INTEGRATION.md for why only the frontend is excluded.
#
# WHAT THIS SCRIPT DOES NOT DO
#   It does not run the emulator and it proves nothing about performance. Its
#   only claim is "the core compiled for arm64 iPadOS". Verification on the
#   physical iPad is separate and mandatory (docs/BENCHMARK-PLAN.md).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/engines/flycast"
BUILD="$ROOT/build/flycast-ios"

# --- Preflight ----------------------------------------------------------------

if [ ! -d "$SRC/core" ]; then
  echo "Flycast sources missing. Run scripts/fetch-engines.sh first." >&2
  exit 1
fi

# Flycast's own bootstrap performs this same check
# (shell/apple/generate_xcode_project.command:178).
if [ ! -f "$SRC/core/deps/glslang/CMakeLists.txt" ]; then
  echo "Flycast submodules are not initialised (glslang missing)." >&2
  echo "Run: git -C \"$SRC\" submodule update --init --recursive --depth 1" >&2
  exit 1
fi

# The library target comes from our patch. Fail early with a clear message
# rather than with CMake's "unknown argument -DDEEZRETRO_CORE_LIBRARY".
if ! grep -q 'DEEZRETRO_CORE_LIBRARY' "$SRC/CMakeLists.txt"; then
  echo "Deez Retro patch not applied to Flycast." >&2
  echo "Run scripts/fetch-engines.sh (it applies patches/*.patch), or:" >&2
  echo "  git -C \"$SRC\" apply --3way \"$ROOT/patches/0001-flycast-core-library.patch\"" >&2
  exit 1
fi

command -v cmake     >/dev/null || { echo "cmake not found (brew install cmake)" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "full Xcode not found (not just Command Line Tools)" >&2; exit 1; }

# Flycast requires CMake >= 3.24. Warn about CMake 4.x separately, because of a
# distinct problem: CMake 4 removed compatibility with
# cmake_minimum_required(VERSION < 3.5), and one bundled dependency declares
# 2.4.4 - core/deps/libchdr/deps/zlib-1.3.1/CMakeLists.txt. Whether that
# dependency is configured on iOS depends on whether find_package(ZLIB) succeeds,
# which the iOS path usually makes succeed by pre-seeding ZLIB_LIBRARY=-lz
# (CMakeLists.txt:41). It is not guaranteed, so pin CMake 3.x for this build.
CMAKE_VER="$(cmake --version | head -1 | sed -E 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/')"
case "$CMAKE_VER" in
  4.*)
    echo "WARNING: CMake $CMAKE_VER detected." >&2
    echo "  A bundled dependency (libchdr/deps/zlib-1.3.1) declares" >&2
    echo "  cmake_minimum_required(VERSION 2.4.4...3.15.0). CMake 4 rejects the" >&2
    echo "  <3.5 range. If configuration fails with 'Compatibility with CMake < 3.5" >&2
    echo "  has been removed', use CMake 3.2x-3.3x instead." >&2
    ;;
esac

mkdir -p "$BUILD"

# --- Build mode ---------------------------------------------------------------
#
# DEEZRETRO_NO_JIT=1 (default) builds the interpreter-only configuration.
#
# Flycast derives all three dynarec flags from one macro. core/build.h:50-54:
#
#   #if defined(TARGET_NO_REC)
#   #define FEAT_SHREC  DYNAREC_NONE
#   #define FEAT_AREC   DYNAREC_NONE
#   #define FEAT_DSPREC DYNAREC_NONE
#   #endif
#
# and it auto-defines TARGET_NO_REC only for the iOS *simulator*
# (core/build.h:41-44). Our patch exposes it as -DDEEZRETRO_NO_REC=ON so a device
# build can select it without hand-hacking compiler flags.
if [ "${DEEZRETRO_NO_JIT:-1}" = "1" ]; then
  NO_JIT_OPT=(-DDEEZRETRO_NO_REC=ON)
  echo "==> interpreter-only core (TARGET_NO_REC): no JIT, no entitlements needed"
else
  NO_JIT_OPT=(-DDEEZRETRO_NO_REC=OFF)
  echo "==> dynarec core: requires JIT at runtime; see docs/BLOCKERS.md B-1/B-2"
fi

# --- Configure ----------------------------------------------------------------

# USE_OPENGL MUST STAY ON for iOS. It is not "desktop OpenGL": the iOS branch
# force-defines GLES/GLES3/HAVE_OPENGLES3 (CMakeLists.txt:313-315). And
# core/wsi/CMakeLists.txt only compiles gl_context.cpp and osx.cpp inside
# if(USE_OPENGL), while on iOS GLGraphicsContext::Create() dispatches to
# OSXGraphicsContext (core/wsi/gl_context.cpp:105-106). Turning it off therefore
# yields an undefined symbol on GLGraphicsContext::Create.
#
# (An earlier revision of this script passed -DUSE_OPENGL=OFF. That was a bug.)
cmake -S "$SRC" -B "$BUILD" \
  -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DDEEZRETRO_CORE_LIBRARY=ON \
  "${NO_JIT_OPT[@]}" \
  -DUSE_VULKAN=OFF \
  -DUSE_DX9=OFF \
  -DUSE_DX11=OFF \
  -DUSE_BREAKPAD=OFF \
  -DUSE_DISCORD=OFF \
  -DUSE_LUA=OFF \
  -DUSE_OPENMP=OFF \
  -DUSE_HOST_LIBZIP=OFF \
  -DUSE_HOST_LIBCHDR=OFF \
  -DUSE_LIBCDIO=OFF

# --- Build --------------------------------------------------------------------

cmake --build "$BUILD" --config Release --target flycast -j "$(sysctl -n hw.ncpu)"

# --- Collect ------------------------------------------------------------------

LIB="$(find "$BUILD" -name 'libflycast.a' -print -quit || true)"
echo
if [ -n "$LIB" ]; then
  echo "Built: $LIB"
  echo
  echo "Symbols the Deez Retro bridge calls - verify with:"
  echo "  nm -gU \"$LIB\" | c++filt | grep -E 'flycast_init|flycast_term|mainui_init|mainui_rend_frame'"
  echo
  echo "Then build a simulator-safe smoke test before touching the device."
else
  echo "No libflycast.a produced. Inspect the build output above." >&2
  exit 1
fi

cat <<'EOF'

NEXT STEPS
  1. Point the DeezRetro target at this library and set DEEZRETRO_HAVE_FLYCAST=1
     (project.yml -> GCC_PREPROCESSOR_DEFINITIONS).
  2. Build and run on the simulator first: it cannot exercise the dynarec
     (core/build.h forces TARGET_NO_REC there), but it does prove the link and
     the SwiftUI -> ObjC++ -> Flycast path.
  3. Then deploy to the physical iPad and load a homebrew .elf or a .gdi/.chd.
     Until that runs, nothing is proven. See docs/PHASE2-BUILD-REPORT.md.
EOF
