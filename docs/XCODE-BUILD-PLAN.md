# Minimal Xcode build plan

**Prerequisites:** an Apple Silicon Mac with full Xcode (not just Command Line
Tools), CMake, XcodeGen, and a physical M4 iPad Pro with Developer Mode enabled.
None of that was available in this session; this plan is untested by definition.

The goal of this plan is narrow and deliberate: **get one Dreamcast disc booting
and rendering on the physical iPad, with the CPU execution mode visible on
screen.** No library UI, no save-state browser, no PS2. Those wait until the
engine is proven.

---

## Step 0 · Why not just build Flycast's iOS app?

Because Flycast already ships one, and taking it would be a dead end.

`shell/apple/emulator-ios/` is a complete UIKit app (storyboards, `.xib` pad
editors, iCade support) built by `CMakeLists.txt:1284-1345` as a
`MACOSX_BUNDLE` and packaged with `ldid` against
`flycast.entitlements` — which contains only `get-task-allow`. Its frontend is
Objective-C/UIKit and cannot host SwiftUI; its build target is an app, not a
library (`CMakeLists.txt:277-278` adds `add_executable` for all Apple targets).

Deez Retro needs `core/` as a linkable library and its own SwiftUI shell. So
Step 2 below is the real work.

---

## Step 1 · Reproduce the engine build first, alone

Before touching our app, prove the *engine* compiles for iOS arm64 in the
interpreter configuration. This isolates engine breakage from project breakage.

```bash
git clone https://github.com/flyinghead/flycast.git flycast
cd flycast
git checkout --detach ed953fcbfdd1b8a7521d2966b13cc700c7e2d233
git submodule update --init --recursive --depth 1     # 23 submodules

cmake -B build-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DUSE_VULKAN=OFF -DUSE_DX9=OFF -DUSE_DX11=OFF \
  -DUSE_BREAKPAD=OFF -DUSE_DISCORD=OFF -DUSE_OPENMP=OFF \
  -DCMAKE_C_FLAGS="-DTARGET_NO_REC" -DCMAKE_CXX_FLAGS="-DTARGET_NO_REC"

cmake --build build-ios --config Release --target flycast -j $(sysctl -n hw.ncpu)
```

**Gate:** this must produce a binary. If it does not, stop and fix the engine
build before writing any app code. `-DTARGET_NO_REC` is the interpreter switch:
Flycast derives all three dynarec flags from it (`core/build.h:50-54`) and it is
normally only auto-set for the simulator (`core/build.h:41-44`).

---

## Step 2 · Turn Flycast's core into a linkable library

Flycast offers no static-library target for Apple, so add one. Keep it additive —
do not restructure the engine.

In Flycast's `CMakeLists.txt`, alongside the existing `add_executable`, add an
object/static library over the same source list **minus**:

- `shell/apple/emulator-ios/**` (the UIKit frontend — see Step 0)
- the `main()` translation unit

Then link that library into DeezRetro and define `DEEZRETRO_HAVE_FLYCAST=1`, which
is the switch that activates the real code paths in `Bridge/DeezRetroCore.mm`.

This patch belongs in `patches/` as a small `.patch` file, not as a fork.

**Gate:** `nm -gU` on the library shows `_flycast_init`, `_flycast_term`,
`_dc_savestate`, `_dc_loadstate` — the symbols `Bridge/DeezRetroCore.mm` calls.

---

## Step 3 · Generate the app project

```bash
brew install xcodegen
cd deez-retro
xcodegen generate          # reads project.yml
open DeezRetro.xcodeproj
```

`project.yml` already declares the frameworks the engine actually needs, taken
from Flycast's own iOS link list (`CMakeLists.txt:226-230` and `:1352`):

| Framework | Needed by |
|---|---|
| `OpenGLES`, `GLKit` | Flycast's GLES3 renderer (`CMakeLists.txt:226-230`) |
| `AudioToolbox`, `AVFoundation` | CoreAudio backend, `kAudioUnitSubType_RemoteIO` on iOS |
| `GameController` | DualSense via `GCController` (`ios_gamepad.h`) |
| `Security` | `SecTask*` entitlement checks in `JIT/JITAcquisition.swift` |
| `Metal`, `MetalKit` | presentation layer only (engine still renders GLES3) |

Set `DEEZRETRO_HAVE_FLYCAST=0` for the very first build so the app compiles and
launches with no engine linked. It must report *"engine not linked"* — that is
the correct, honest state and it proves the SwiftUI → ObjC++ boundary works
before any C++ is involved.

**Gate 1:** app launches on the iPad and the bring-up screen reports
`Linked: no`.
**Gate 2:** flip to `DEEZRETRO_HAVE_FLYCAST=1`, rebuild, and it reports
`Linked: yes` / `Execution mode: interpreter (no JIT)`.

---

## Step 4 · First on-device run — interpreter, no JIT

This is the configuration that requires **no entitlements and no helper app**,
and it is the only configuration that could ever ship on the App Store.

1. Deploy via Xcode (Automatic signing, personal team is fine).
2. Confirm on the bring-up screen: `get-task-allow: yes`, `TXM/SPTM: yes`.
3. Drop a `.gdi`/`.chd`/`.cdi` into the app's Documents directory via Finder or
   Files (`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are set
   in `App/Info.plist`).
4. Call `loadGameAtPath:` then `run()`, and watch the execution mode and FPS.

**This step is the actual Phase 1 deliverable.** Everything before it is
plumbing.

---

## Step 5 · Enable the dynarec path

Only attempt this after Step 4 is stable, because it is where the platform
fights back (see `docs/BLOCKERS.md` B-1 and B-2).

1. Rebuild the engine without `-DTARGET_NO_REC`.
2. Launch the app. Because `JIT/JITAcquisition.swift` runs at app start, it will
   detect `CS_DEBUGGED` absent, detect TXM present, and hand off to StikDebug.
   Note that **opening the StikDebug URL is not success** — the code polls our own
   `CS_DEBUGGED` bit rather than trusting the URL open.
3. On M4, expect TXM to be present, which means debugger attach alone is
   insufficient and the per-region preparation protocol
   (`docs/BLOCKERS.md` B-2) is required. That is the `FEAT_NO_RWX_PAGES` +
   pre-reserved-arena patch, and it is the most likely thing to fail first.
4. Only when `DRCoreNotifyJITAcquired()` runs does
   `config::DynarecEnabled.override(true)` take effect, promoting the executor
   from interpreter to recompiler (`core/emulator.cpp:520-541`).

---

## Build settings that matter

| Setting | Value | Reason |
|---|---|---|
| `ARCHS` | `arm64` | M4 iPad Pro only; prevents accidental simulator dynarec testing |
| `CLANG_CXX_LANGUAGE_STANDARD` | `c++20` | Flycast sets `CMAKE_CXX_STANDARD 20` on its target (`CMakeLists.txt:284`) |
| `TARGETED_DEVICE_FAMILY` | `2` | iPad only |
| `SUPPORTS_MACCATALYST` | `NO` | Catalyst does not define `IOS`, so the JIT gate is not compiled in |
| `SWIFT_OBJC_BRIDGING_HEADER` | `Bridge/DeezRetro-Bridging-Header.h` | Swift ↔ ObjC |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` | engine build scripts write outside the build dir |

## Entitlements

Ships **without** `com.apple.developer.kernel.allow-jit` — Apple rejects it in
review (`docs/BLOCKERS.md` B-1). If a sideload-only variant is ever built, give it
a *separate* entitlements file so the App Store build cannot accidentally acquire it.

## Known unknowns at build time

- Flycast's `core/emulator.cpp` contains `main()`; the library target must exclude
  it or link the app with a duplicate-symbol error.
- `intl/` and `resources/` are pulled in via `resources/resources.cmake` and
  `file(GLOB_RECURSE SRC_FILES *.h *.cpp *.c *.cc *.mm)` (`CMakeLists.txt:1568`).
  A from-scratch source list will drift from upstream — prefer reusing Flycast's
  own lists with exclusions.
- Deployment target is set to 17.0 here, while Flycast's own iOS path targets
  12.0 (`CMakeLists.txt:32`). Raising it is intentional: the JIT helper path needs
  17.4+.
