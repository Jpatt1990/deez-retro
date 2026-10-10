# patches/

Small, reviewable patches applied to the pinned Flycast checkout by
`scripts/fetch-engines.sh`.

This directory is currently **empty of patches**, because the one change Phase 1
needs is implemented on the *Deez Retro* side of the boundary rather than in the
engine:

| Concern | Where it is handled | Why not a patch |
|---|---|---|
| JIT state → `config::DynarecEnabled` | `Bridge/DeezRetroCore.mm` | Upstream's iOS shell *computes* JIT state and never uses it (see `docs/BLOCKERS.md` B-5). Fixing it in the bridge keeps the engine untouched and survives a Flycast upgrade. |
| Building `core/` as a library instead of an app | `docs/XCODE-BUILD-PLAN.md` step 2 | Additive CMake change; see below. |

## Patches expected to be needed

### `0001-flycast-ios-static-library.patch`

Flycast only declares `add_executable` for Apple targets
(`CMakeLists.txt:277-278`). A static/object library target is needed that excludes:

- `shell/apple/emulator-ios/**` — the UIKit frontend (~20 files, ~4,620 lines under
  `shell/apple`), which Deez Retro replaces with SwiftUI
- the `main()` translation unit

Prefer adding a target alongside Flycast's own source lists rather than restating
them, because `CMakeLists.txt:1568` uses
`file(GLOB_RECURSE SRC_FILES *.h *.cpp *.c *.cc *.mm)` and a hand-written list will
silently drift from upstream.

### `0002-flycast-ios-txm-jit-arena.patch` (only if Track B is pursued)

Required for iOS 26 TXM/SPTM on M-series hardware, including M4. Enables
`FEAT_NO_RWX_PAGES` for iOS — the dual RW/RX mapping already exists for ARM64 but
is gated to `__SWITCH__` (`core/build.h:62-64`) — and pre-reserves the JIT arena so
that the whole region exists before `JIT26Detach`. See `docs/BLOCKERS.md` B-2.

**Preallocate executable regions before detaching. A region introduced later cannot
be prepared by a script that has already detached.** This is the constraint that
turns "enable a JIT" into "restructure the code arena lifecycle."

## Rules

1. **Keep patches minimal and single-purpose.** They must be readable in full.
2. **Never restructure the engine.** Preserve the existing C/C++ implementation;
   the brief is explicit about this.
3. **Prefer the bridge over the patch.** If a behaviour can be corrected from Deez
   Retro's side of the API, do that instead — it costs nothing on engine upgrades.
4. **Re-verify on every pin bump.** Flycast has dropped iOS support upstream, so a
   patch that applies today may be unnecessary or contradictory tomorrow.
