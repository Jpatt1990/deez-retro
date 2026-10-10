# Phase 2 build report — Dreamcast

**Scope:** Sega Dreamcast only. PlayStation 2 development suspended.
**Engine:** Flycast, pinned at `ed953fcbfdd1b8a7521d2966b13cc700c7e2d233`
**Date:** 2026-10-10
**Host:** Windows, MSVC 14.44.35207, Windows SDK 10.0.26100.0, CMake 3.31.6

> **Read the scope of the claims first.** This report contains real, reproducible
> compiler output. It does **not** contain any evidence that the emulator runs,
> renders, produces audio, or performs adequately on an M4 iPad. Those require a
> physical iPad. See §5.

---

## 1. What was actually achieved

| # | Build priority (from the brief) | Status |
|---|---|---|
| 1 | **Successful ARM64 compilation** | **Partial.** 858 translation units of the pinned Flycast core compiled and linked with **0 errors** in the interpreter-only configuration — but for **Windows x64**, not arm64-apple-ios. No Apple toolchain exists on this host. |
| 2 | App launches on the iPad | **Not attempted.** No Mac, no device. |
| 3 | Dreamcast software boots | **Not attempted.** |
| 4 | Measure performance on the M4 | **Not attempted.** See `docs/BENCHMARK-PLAN.md` for the method. |
| 5 | Optimise / investigate JIT | **Deferred by design.** Phase 2 is interpreter-first; there is nothing to optimise until (2) and (3) exist. |

**So: priority 1 is partially met, priorities 2–5 are not.** The value delivered
is that the engine, the patch, and the interpreter-only configuration are now
*proven to compile and link*, and the iOS-specific work is reduced to a
well-specified, reviewable change set rather than an open-ended port.

### Evidence

| Artifact | Location |
|---|---|
| Full build log (858 TUs, 0 errors, 192 warnings) | `docs/logs/2026-win-x64-interpreter-build.log` |
| CMake configure log | `docs/logs/2026-win-x64-interpreter-configure.log` |
| The interpreter-only proof (below) | `docs/logs/2026-feat-macro-proof.txt` |
| Build log for the failing no-renderer configuration | `docs/logs/2026-win-x64-no-renderer-error.log` |
| The engine patch | `patches/0001-flycast-core-library.patch` |

Final build result, verbatim from the log:

```
  flycast.vcxproj -> C:\Users\jpatt\deez-retro-work\build-win5\Release\flycast.exe
[status: completed, exit code: 0]
```

`flycast.exe` is 10.81 MB with a valid `MZ` header. 12 static libraries were
built along the way (`zlibstatic`, `zstd_static`, `chdr-static`, `libzip`,
`freetype`, `lzma`, `elf`, `juice-static`, `libusb-1.0`, …).

---

## 2. The interpreter-only claim, proven

The brief requires that no claim of success rest on assertion. "It is
interpreter-only and needs no JIT" is therefore not stated from documentation —
it is measured. `probe_feat.cpp` includes the engine's own `core/build.h` and
prints what the preprocessor resolved.

Compiled twice with the same compiler and flags, differing only by the macro that
`-DDEEZRETRO_NO_REC=ON` produces:

```
 A) default build (no TARGET_NO_REC)          B) interpreter-only (TARGET_NO_REC)
 ----------------------------------------     ----------------------------------------
 TARGET_NO_REC      : not defined             TARGET_NO_REC      : defined
 FEAT_SHREC         : DYNAREC_JIT             FEAT_SHREC         : DYNAREC_NONE
 FEAT_AREC          : DYNAREC_JIT             FEAT_AREC          : DYNAREC_NONE
 FEAT_DSPREC        : DYNAREC_JIT             FEAT_DSPREC        : DYNAREC_NONE
 VERDICT            : CONTAINS RECOMPILER(S)  VERDICT            : INTERPRETER-ONLY
                                                                 (no executable memory required)
```

This matters for iPadOS because all three `DYNAREC_NONE` values mean Flycast's
`core/rec-ARM64/rec_arm64.cpp` and the AICA ARM/DSP recompilers compile to empty
translation units (`#if FEAT_SHREC == DYNAREC_JIT …`). **No code path can call
`mmap(PROT_EXEC)` or `mprotect(…, PROT_EXEC)`**, so the build needs no JIT
entitlement, no debugger attach, no AltStore, and no Developer Mode.

That is the single most important property of the Phase 2 configuration, and it
is now empirically established rather than assumed.

---

## 3. The engine patch, verified to apply

`patches/0001-flycast-core-library.patch` is 39 insertions / 1 deletion against
Flycast's top-level `CMakeLists.txt`. It does four things:

1. Declares `DEEZRETRO_CORE_LIBRARY` and `DEEZRETRO_NO_REC` as options.
2. Builds a `STATIC` library instead of the bundled iPhoneOS app when
   `DEEZRETRO_CORE_LIBRARY=ON` (Flycast only ever calls `add_executable` for
   Apple targets — `CMakeLists.txt:277-278`).
3. Adds `$<$<BOOL:${DEEZRETRO_NO_REC}>:TARGET_NO_REC>` to the existing
   compile-definition list (`CMakeLists.txt:308-325`), so the interpreter
   configuration is a supported option rather than a hand-hacked compiler flag.
4. Wraps the bundled UIKit frontend (`shell/apple/emulator-ios/**`, AltKit, the
   storyboards, the IPA packaging target) in `if(NOT DEEZRETRO_CORE_LIBRARY)`.

**Verification performed:**

```
$ git -C engines/flycast checkout -- CMakeLists.txt     # back to pristine pin
$ git -C engines/flycast apply --check --verbose patches/0001-flycast-core-library.patch
Checking patch CMakeLists.txt...
$ echo $?
0
```

and, separately, the patched tree was configured and built end-to-end (§1),
which exercises all five edits including the CMake syntax of the iOS-only
branches.

---

## 4. Real problems found and fixed

Everything below was found by compiling or configuring, not by reading.

### 4.1 A bug I introduced in Phase 1: `-DUSE_OPENGL=OFF` breaks the iOS renderer

The Phase 1 `build-flycast-ios.sh` passed `-DUSE_OPENGL=OFF`. **That would have
produced an undefined-symbol link failure on iOS.** `core/wsi/CMakeLists.txt`
only compiles `gl_context.cpp` and `osx.cpp` inside `if(USE_OPENGL)`, and on iOS
`GLGraphicsContext::Create()` dispatches to `OSXGraphicsContext`
(`core/wsi/gl_context.cpp:105-106`). Fixed, and the script now documents why
`USE_OPENGL=ON` on iOS means GLES3 rather than desktop GL. See
`docs/PHASE2-IOS-INTEGRATION.md` §4.

### 4.2 Wrong `flycast_init` call in Phase 1

Phase 1's bridge called `flycast_init(1, argv)`. Upstream's iOS and Android
shells both call `flycast_init(0, nullptr)`
(`FlycastViewController.mm:218`, `Android.cpp:171`), because
`config::parseCommandLine()` is the embedded entry point. Fixed.

### 4.3 Wrong frame pump in Phase 1

Phase 1 called `emu.render()` per frame. The correct pump is
`mainui_rend_frame()` (`core/ui/mainui.cpp:38`), which internally calls
`emu.render()` *and* `os_DoEvents()`, `os_UpdateInputState()`, the ImGui overlay,
and the renderer-error recovery path. Fixed.

### 4.4 A Phase 1 claim that was simply wrong

Phase 1 said `core/emulator.cpp` contains `main()` and that excluding it would
need care. It does not. For Apple targets `main()` comes from
`shell/apple/emulator-ios/emulator/main.m` (`UIApplicationMain`), which the patch
excludes. **There is no duplicate-`main` problem.** Corrected in the integration
doc rather than left standing.

### 4.5 CMake 4.x cannot configure this dependency tree

`core/deps/libchdr/deps/zlib-1.3.1/CMakeLists.txt` declares
`cmake_minimum_required(VERSION 2.4.4...3.15.0)`. CMake 4 removed compatibility
with `< 3.5`, so the configure aborts. This dependency is added at
`CMakeLists.txt:585` whenever `WITH_SYSTEM_ZLIB` is not already set, which
happens whenever `find_package(ZLIB)` fails — and it did fail on this host:

```
-- Could NOT find ZLIB (missing: ZLIB_LIBRARY)
```

On iOS the top-level CMake pre-seeds `ZLIB_LIBRARY` to `-lz`
(`CMakeLists.txt:41`), so `find_package(ZLIB)` probably succeeds and the
dependency is probably skipped. **Probably is not good enough**, so the build
script now warns about CMake 4 and recommends pinning CMake 3.2x–3.3x. Verified
fix: CMake 3.31.6 configures the same tree successfully.

### 4.6 The engine cannot be configured with zero renderer backends

Disabling every renderer (`USE_OPENGL`, `USE_DX9`, `USE_DX11`, `USE_VULKAN`,
`USE_GLES` all off) fails to compile:

```
core/hw/pvr/Renderer_if.cpp(458,2): error C2059: syntax error: '}'
```

The `switch` in `rend_create_renderer()` has per-renderer cases guarded
individually by `#ifdef USE_OPENGL` / `USE_DX9` / `USE_DX11`, but the closing
brace at line 458 sits outside those guards. **At least one renderer must be
enabled.** This does not affect iOS, where `USE_OPENGL=ON` is mandatory anyway
(§4.1), but it is a real constraint on the engine and it is recorded in
`docs/logs/2026-win-x64-no-renderer-error.log`.

### 4.7 A Windows-only gap that is *not* an iOS problem

`core/deps/tinygettext/src/unix_file_system.cpp` includes `<dirent.h>`, which
MSVC does not have. Flycast bundles a shim at `core/deps/dirent/dirent.h` and adds
it to the *flycast* target's include path (`CMakeLists.txt:793`) but not to the
`tinygettext` target, so the bundled build fails on Windows. Adding the shim to
the include path resolved it and the build then completed.

**On iOS this does not arise**: `dirent.h` is a real POSIX header there. It is
recorded because it cost real debugging time and will recur for anyone building
the engine on Windows.

---

## 5. What is NOT verified — and must not be claimed

Stated plainly, because the brief is explicit: *"Do not claim successful
compilation, gameplay, or performance without actual build logs and device
testing."*

| Claim | Status |
|---|---|
| Flycast compiles for **arm64-apple-ios** | ❌ **Not verified.** The 858-TU build was Windows x64. The iOS configuration has never been through a compiler. |
| The app launches on an iPad | ❌ Not attempted. No Mac, no device. |
| Dreamcast software boots | ❌ Not attempted. |
| Graphics / audio / controller input work | ❌ Not attempted. The wiring is source-derived, not tested. |
| Any frame rate, CPU load, thermal or audio figure | ❌ No measurement exists. |
| The interpreter is fast enough to be playable | ❌ **Unknown, and it is the project's biggest open risk.** |
| The SwiftUI → ObjC++ → Flycast chain links | ❌ Not verified. `project.yml` has never been through XcodeGen. |

The Windows build proves the *source* is healthy and the *configuration* is
correct. It says nothing about iOS.

---

## 6. How to get the iOS build logs

Two routes, both cheap.

### Route A — a Mac (preferred)

```bash
scripts/fetch-engines.sh                 # pins Flycast, fetches 23 submodules, applies the patch
bash scripts/build-flycast-ios.sh        # arm64 iPadOS, interpreter-only, produces libflycast.a

brew install xcodegen
xcodegen generate
open DeezRetro.xcodeproj                 # then build/run
```

`build-flycast-ios.sh` gates on the patch being present, on submodules being
initialised, and on full Xcode (not just Command Line Tools), and warns about
CMake 4. It ends by printing the exact `nm` command to confirm the symbols the
bridge needs.

### Route B — GitHub Actions, no Mac required

`.github/workflows/ios-core-build.yml` builds the same core library on a
`macos-15` runner and uploads `configure.log`, `build.log` and `libflycast.a` as
artifacts. It also:

- verifies `libflycast.a` exists, reports its architecture with `lipo -info`,
- checks that `flycast_init`, `flycast_term`, `mainui_init`, `mainui_rend_frame`,
  `dc_savestate` and `dc_loadstate` are present,
- **asserts the interpreter-only configuration took effect** by confirming no
  recompiler symbols are in the archive,
- builds the app for both the simulator and (unsigned) for device.

**This is the fastest way to convert §5's first row from ❌ to ✅.** Push the
repository and dispatch the workflow; the log is the evidence.

---

## 7. Remaining blockers

| ID | Blocker | Severity | Notes |
|---|---|---|---|
| B2-1 | **No Apple toolchain or device on this host.** Nothing has been built for iOS. | **S1** | Mitigated by Route B above; cannot be resolved locally. |
| B2-2 | **Interpreter speed on M4 is unknown.** No Dreamcast title has ever run under this configuration anywhere. | **S1** | Must be measured first on the device; decides whether Track B (JIT) is needed. |
| B2-3 | CMake 4.x cannot configure Flycast's bundled `zlib-1.3.1` (`cmake_minimum_required(VERSION 2.4.4…3.15.0)`). | S3 | Pin CMake 3.2x–3.3x, or pass `-DWITH_SYSTEM_ZLIB=ON`. |
| B2-4 | Flycast needs ≥1 renderer backend; a no-renderer config fails at `Renderer_if.cpp:458`. | S3 | Irrelevant on iOS: `USE_OPENGL=ON` is mandatory. |
| B2-5 | The iOS core-library target has never been configured, so `libflycast.a` does not exist yet. | S3 | Route A or B. The patch is verified; only the run is missing. |
| B2-6 | `project.yml` has never been through XcodeGen; the SwiftUI app has never been compiled. | S3 | Expect ordinary first-build Swift/ObjC interop fixes. |
| B2-7 | `hostfs::saveScreenshot`, `os_PrecomposedString`, `darw_printf`, `os_DoEvents` and three static input maps must be supplied by `Bridge/DeezRetroShell.mm`. | S3 | Written and documented; correctness unverified until it links. |
| B2-8 | Touch input (touch-as-mouse) is not wired, because the plain-`GLKView` host skips Flycast's `EmulatorView`/`TouchMouse`. | S3 | Controller input is wired via `ios_gamepad.h`; touch is a follow-up. |
| B2-9 | Microphone is not wired: `AVAudioSession` always uses the playback-only category. | S3 | One boolean in `configureAudioSession`. |
| B2-10 | Upstream Flycast has dropped iOS support (no iOS job in `.github/workflows/`). | S2 | Pinned SHA + patch set; unchanged from Phase 1 (B-4). |
| B2-11 | GPL-2.0 means an App Store build is legally problematic even though the interpreter configuration would be technically shippable. | S2 | Product decision, unchanged from Phase 1. |

---

## 8. Files changed or added in Phase 2

| Path | Change |
|---|---|
| `patches/0001-flycast-core-library.patch` | **New.** Verified to apply against the pin. |
| `scripts/build-flycast-ios.sh` | **Rewritten.** Fixes the `USE_OPENGL` bug, uses `-DDEEZRETRO_NO_REC=ON`, adds preflight gates and a CMake 4 warning. |
| `Bridge/DeezRetroCore.h` | **Rewritten.** Adds `DREngineState`, `builtWithoutRecompiler`, and `renderFrame`. |
| `Bridge/DeezRetroCore.mm` | **Rewritten.** Correct bring-up sequence, `mainui_rend_frame()` frame pump, audio session, controller/keyboard/mouse observers, enforced `unloadGame()`-before-`loadGame()`. |
| `Bridge/DeezRetroShell.mm` | **New.** Supplies the 7 symbols the core needs from the excluded iOS shell. |
| `App/EmulatorHostView.swift` | **New.** `UIViewRepresentable` over a plain `GLKView` + `CADisplayLink` + `GLKViewDelegate`. |
| `App/GameLibrary.swift` | **New.** Documents-directory discovery, document-picker import, `.gdi`/`.cue` multi-file warning. |
| `App/BringUpView.swift` | **Rewritten.** Engine state, CPU mode, renderer, live FPS, library list, launch, stop. |
| `project.yml` | **Updated.** Header search paths, `DEEZRETRO_HAVE_FLYCAST`, GLES deprecation silencers, explicit framework list. |
| `docs/PHASE2-IOS-INTEGRATION.md` | **New.** The 7-symbol contract, bring-up sequence, renderer/audio/input requirements. |
| `.github/workflows/ios-core-build.yml` | **New.** Real iOS build logs without a Mac. |
| `docs/logs/` | **New.** Raw build and configure logs, and the `FEAT_*` proof. |

Phase 1 documents, scripts, and pinned SHAs were preserved. Corrections to Phase 1
claims are recorded in §4 rather than silently edited away.

---

## 9. Recommended next step

**Run Route B.** It is a push and a workflow dispatch, needs no hardware, and
converts the largest open item (§5) into an actual compiler log. Expect the first
run to surface a small number of ordinary iOS build errors in the engine — the
interpreter configuration is the simplest one Flycast can produce, so the failure
surface should be narrow, but "should" is not "is".

Then, and only then, pursue priority 2: deploy to the iPad and get the app to
launch reporting `Linked: yes` / `interpreter (no JIT)`.
