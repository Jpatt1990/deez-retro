# Deez Retro 🥜

A native iPadOS emulator for the Apple M4 iPad Pro. Sega Dreamcast and Sony
PlayStation 2 only.

**Current phase: Phase 2 — Dreamcast build. PlayStation 2 is suspended.**

> **Read `docs/PHASE2-BUILD-REPORT.md` first.** It states exactly what has and has
> not been verified.

---

## Where things stand

| | Status |
|---|---|
| **Dreamcast (Flycast)** | Engine inspected; core library patch written and verified; interpreter-only configuration **proven at the compiler level**; the pinned engine **compiles and links with 0 errors** (858 translation units) — but for **Windows x64, not iOS**. |
| **iOS / arm64 build** | ❌ **Never compiled.** No Apple toolchain on the authoring host. See §6 of the build report for the two routes to real iOS logs — one of which needs no Mac. |
| **App launches on iPad** | ❌ Not attempted. No device. |
| **Dreamcast software boots** | ❌ Not attempted. |
| **M4 performance** | ❌ No measurement exists. |
| **PlayStation 2** | Suspended. See `docs/PHASE1-FEASIBILITY.md` §7. |

**Nothing here claims the emulator works.** A build counts as working only once
it has compiled, run and been benchmarked on the physical iPad.

### What *was* proven

`TARGET_NO_REC` really does produce a configuration that needs no JIT. Compiled
twice with the same compiler, differing only by that macro:

```
default build                    interpreter-only (DEEZRETRO_NO_REC=ON)
FEAT_SHREC  : DYNAREC_JIT        FEAT_SHREC  : DYNAREC_NONE
FEAT_AREC   : DYNAREC_JIT        FEAT_AREC   : DYNAREC_NONE
FEAT_DSPREC : DYNAREC_JIT        FEAT_DSPREC : DYNAREC_NONE
                                 -> no executable memory required anywhere
```

Full output and build logs: `docs/logs/`.

---

## Getting it running

Needs a Mac with **full Xcode** (not just Command Line Tools) and CMake 3.2x–3.3x.

```bash
scripts/fetch-engines.sh            # pins Flycast at ed953fcb, fetches 23 submodules, applies the patch
bash scripts/build-flycast-ios.sh   # arm64 iPadOS, interpreter-only -> libflycast.a

brew install xcodegen
xcodegen generate
open DeezRetro.xcodeproj
```

`DEEZRETRO_HAVE_FLYCAST` starts at `0` so the app builds and launches before the
engine is linked, reporting *"engine not linked"* — the honest state. Flip it to
`1` once the library exists.

**No Mac available?** `.github/workflows/ios-core-build.yml` builds the same core
library on a macOS runner and uploads the logs and `libflycast.a` as artifacts. It
also asserts the interpreter-only configuration took effect. Push and dispatch.

Then: deploy to the iPad, load a homebrew `.elf` or a `.gdi`/`.chd`, and watch the
harness report CPU mode and FPS.

---

## Map

| Path | What it is |
|---|---|
| `docs/PHASE2-BUILD-REPORT.md` | **The Phase 2 deliverable.** Real logs, real fixes, honest gaps. |
| `docs/PHASE2-IOS-INTEGRATION.md` | The Flycast↔iPadOS contract: the 7-symbol requirement, the bring-up sequence, renderer/audio/input. |
| `docs/PHASE1-FEASIBILITY.md` | Phase 1 feasibility study (still the reference for engine comparison and the iPadOS JIT situation). |
| `docs/BLOCKERS.md` | Phase 1 blocker register B-1…B-9. |
| `docs/BENCHMARK-PLAN.md` | M4 measurement method. Not executed. |
| `docs/LICENSE-MATRIX.md` | Flycast GPL-2.0, Play! BSD-2, PCSX2 GPL-3.0, and the App Store problem. |
| `docs/PINS.md` | Pinned commits + Flycast's submodule map. |
| `docs/logs/` | Raw build/configure logs and the `FEAT_*` proof. |
| `patches/0001-flycast-core-library.patch` | Makes Flycast build a linkable core library and exposes `TARGET_NO_REC`. Verified with `git apply --check`. |
| `App/` | SwiftUI host: bring-up harness, GL view, game library. Deliberately not a product UI. |
| `Bridge/` | Objective-C++ — the only place that touches C++. |
| `JIT/` | iPadOS JIT acquisition (Track B; unused by the interpreter-only build). |
| `Tests/` | Tests that assert the app never claims an engine is linked or JIT is ready when it isn't. |

---

## Architecture

```
SwiftUI (App/)
   │  ObjC-only interface — no C++ crosses this line
   ▼
Objective-C++ bridge (Bridge/DeezRetroCore.mm)
   │  flycast_init(0,nullptr) · mainui_init · mainui_rend_frame
   │  emu.loadGame · emu.start · dc_savestate/dc_loadstate
   │  ios_gamepad.h (DualSense incl. touchpad + haptics)
   ▼
Flycast core (engines/flycast/core/)   ← unmodified apart from the 39-line patch
   ▲
Bridge/DeezRetroShell.mm supplies the 7 symbols the core expects from the
iOS shell that we exclude (darw_printf, os_DoEvents, os_PrecomposedString,
hostfs::saveScreenshot, and 3 static input maps).
```

The brief's rule holds: no engine is rewritten in Swift, and the engine is not
forked. The single patch is 39 insertions, it is documented line by line, and it
keeps the engine's own code intact.

## Licence

Flycast is **GPL-2.0-or-later**. Statically linking it makes the combined work
GPL-2.0, which is not compatible with App Store distribution. See
`docs/LICENSE-MATRIX.md` before deciding the distribution model — it is a product
decision that outranks any engineering choice here.
