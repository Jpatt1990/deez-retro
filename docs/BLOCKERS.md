# Blocker register — Deez Retro Phase 1

Each blocker is stated with the evidence that establishes it, its impact, the
proposed solution, and whether it is **verified** or **hypothesis**.

Severity: **S1** = stops the product · **S2** = forces a product decision ·
**S3** = engineering work, tractable.

---

## B-1 · iPadOS does not permit JIT for third-party apps — **S2**

**Verified.** This is the defining constraint of the whole project.

iPadOS enforces W^X: a normal sandboxed app cannot map writable memory as
executable. Every ARM64 CPU recompiler in scope needs exactly that.

Flycast's own iOS shell documents the consequence. It carries a JIT-detection
routine copied from PPSSPP (`shell/apple/emulator-ios/emulator/FlycastViewController.mm:379-446`,
credited to Henrik Rydgård) whose entire purpose is to obtain the
`CS_DEBUGGED` process flag, because that is what unlocks executable pages:

```c
#define CS_DEBUGGED 0x10000000  /* process is currently or has previously been
                                   debugged and allowed to run with invalid pages */
```

The same file then falls back to **AltKit** (AltStore) to get an external
debugger attached:

```objc
if (checkTryDebug()) { iosJitStatus = "OK"; iosJitAuthorized = true; return; }
NSLog(@"Starting AltKit discovery");
[[ALTServerManager sharedManager] autoconnectWithCompletionHandler:…];
```

Two important nuances, both verified:

1. **The old self-ptrace trick is not reliable any more.** iOS 18.4 broke the
   "pretend to be a debugger by forking and `PT_ATTACHEXC`-ing the parent"
   approach for sideloaded apps.
2. **App Store builds can never carry the native entitlement.**
   `com.apple.developer.kernel.allow-jit` is the iOS 26 native JIT entitlement,
   and Apple rejects it in App Store review. Provenance's own changelog states
   this outright after adding it:

   > **JIT entitlement removed from App Store builds** — `com.apple.developer.kernel.allow-jit`
   > is not permitted in App Store submissions; removed from `Provenance.entitlements`,
   > `Provenance-AppStore.entitlements`, and `Provenance-Mini.entitlements`. App Store users
   > continue to use debugger-attach, TrollStore, StikDebug, AltJIT, or JitStreamer paths.

**Impact.** JIT is not a build flag; it is an *install and launch workflow*. On a
non-jailbroken iPad, the user must enable Developer Mode, hold a pairing file,
have an external helper installed, and start JIT **before** the game launches.
An emulator that silently runs at 20% speed when the user forgets this is a bad
product; one that refuses to launch and explains why is a tolerable one.

**Proposed solution.** Two-track design, decided by measurement (see
`docs/BENCHMARK-PLAN.md` rows 1 vs 2):

- **Track A — no JIT, interpreter.** Ship-capable, no workflow burden, no
  entitlements. Flycast supports this properly: `core/build.h:50-54` forces all
  three dynarecs off under `TARGET_NO_REC`, and `core/emulator.cpp:520-541`
  selects between `Get_Sh4Recompiler()` and `Get_Sh4Interpreter()` at runtime via
  `config::DynarecEnabled`. **Whether it is fast enough on an M4 is unmeasured —
  this is the Phase 1 experiment that matters most.**
- **Track B — JIT via external helper.** Adopt the documented
  StikDebug/StikJIT path (`JIT/JITAcquisition.swift`). Not App Store distributable.

---

## B-2 · iOS 26 TXM/SPTM requires a breakpoint protocol per executable region — **S3, but subtle**

**Verified from primary source** (StikJIT `INTEGRATION.md`, maintained by the
StikDebug authors):

> On a device where TXM/SPTM is not present, attaching and detaching the debugger
> is enough to enable JIT. Where TXM/SPTM is present, the debugger flag alone is not
> enough: each executable memory region must be prepared through the debug connection
> before the app executes code from it.

and:

> **Preallocate executable regions before detaching.** A region introduced later
> cannot be prepared by a script that has already detached; reconnect and repeat
> the protocol if the engine must add one.

M4 iPad Pro is M-series hardware, so **TXM/SPTM presence is expected**. This is
the single most under-appreciated blocker: it is not "get JIT and you're done."

The host-side protocol is a magic breakpoint, with arguments in `x0`/`x1`:

```c
__attribute__((noinline, optnone, naked))
void* JIT26PrepareRegion(void* address, size_t length) {
    __asm__("mov x16, #1\n" "brk #0xf00d\n" "ret\n");
}
__attribute__((noinline, optnone, naked))
void JIT26Detach(void) {
    __asm__("mov x16, #0\n" "brk #0xf00d\n" "ret\n");
}
```

**Why this collides with Flycast.** Flycast's POSIX virtual-memory layer allocates
code pages lazily and flips protection per block. `core/linux/posix_vmem.cpp:74-87`
shows the W^X-aware path:

```c
bool region_set_exec(void *start, size_t len) {
    int protFlags = PROT_READ | PROT_EXEC;
#ifndef TARGET_IPHONE
    protFlags |= PROT_WRITE;   // iPhone: never RWX
#endif
    if (mprotect((u8*)start - inpage, len + inpage, protFlags)) { … return false; }
}
```

and `prepare_jit_block` (`posix_vmem.cpp:250-282`) first *tries* to convert the
whole reserved area to exec, then falls back to a fresh RWX `mmap`. On iOS
`TARGET_MAC` is **not** defined (it is only set for `APPLE AND NOT IOS`,
`CMakeLists.txt:304-306`), so the iOS build takes the anonymous
`PROT_READ|PROT_WRITE|PROT_EXEC` branch — which TXM will not honour for a
non-debugged process, and which cannot be region-prepared because the regions do
not exist yet at acquisition time.

**Proposed solution.** A small, reviewable patch to Flycast's iOS path, carried in
`patches/`:

1. Enable `FEAT_NO_RWX_PAGES` for iOS. It already exists and is implemented for
   ARM64 (`core/build.h:92-97` restricts it to X64/ARM64) but is only turned on for
   `__SWITCH__` (`core/build.h:62-64`). It gives the exact dual-mapping shape TXM
   wants: one RX region plus a separate RW alias over the same file-backed pages
   (`posix_vmem.cpp:289-310`, via `allocate_shared_filemem`).
2. Reserve the **entire** JIT arena up front, before `JIT26Detach`, and call
   `JIT26PrepareRegion` once for the whole arena. Never grow it later.
3. Keep `JITWriteProtect` a no-op on iPhone as it already is
   (`core/types.h:58-69` guards the `pthread_jit_write_protect_np` call out with
   `#ifndef TARGET_IPHONE`) and rely on the RW alias for writing.

This is the reason `docs/BENCHMARK-PLAN.md` row 3 exists.

---

## B-3 · Flycast has no Metal renderer, and iOS forces Vulkan off — **S3**

**Verified.** Flycast's renderers are:

```
core/rend/dx9  dx11  gl4  gles  norend  vulkan
```

There is **no `metal` directory**. And iOS explicitly disables Vulkan:

```cmake
if(IOS AND NOT LIBRETRO)
    set(USE_VULKAN OFF CACHE BOOL "Force vulkan off" FORCE)   # CMakeLists.txt:110-112
endif()
```

iOS is instead hard-wired to OpenGL ES 3:

```cmake
$<$<BOOL:${IOS}>:GLES>            # CMakeLists.txt:313-315
$<$<BOOL:${IOS}>:GLES3>
```

and links `OpenGLES` + `GLKit` (`CMakeLists.txt:226-230`). The view layer uses
`EAGLContext` (`FlycastViewController.mm`). OpenGL ES is **deprecated** on iOS but
still functional; it is the path of least resistance and is what Flycast's iOS
shell already uses.

**Impact.** Not a blocker for Phase 1 — GLES3 works and is the fastest route to a
running PoC. It is a durability risk: if Apple removes OpenGL ES, the engine loses
its only iOS renderer, and a Metal backend would then have to be written against
Flycast's renderer abstraction (no small job).

**Proposed solution.** Do not write a Metal backend in Phase 1. Ship GLES3. If
Metal becomes necessary, prefer routing through **MoltenVK** and re-enabling
Flycast's existing Vulkan backend rather than writing a new one — Vulkan is a
first-class Flycast renderer, whereas Metal is nothing. Note that upstream's own
macOS bootstrap downloads MoltenVK (`shell/apple/generate_xcode_project.command:8-96`),
so the shim is already a known quantity to this codebase, though that script's
MoltenVK build is macOS-only and an iOS slice would need building separately.

**Correction to the brief's assumption.** The brief asks for
"Metal-compatible graphics." For Phase 1 the honest answer is: the app presents
through Metal (MetalKit host layer, as scaffolded in `project.yml`), but the
*engine* renders through OpenGL ES 3. Conflating those would be misleading.

---

## B-4 · Upstream Flycast has dropped iOS support — **S2 (project risk)**

**Verified.** `README.md:61-63`:

> ### iOS
> Due to persistent harassment from an iOS user, support for this platform has been dropped.

Corroborating evidence: there is **no iOS job** in `.github/workflows/`
(only `android.yml`, `bsd.yml`, `c-cpp.yml`, `switch.yml`, `uwp.yml`, plus two
Crowdin jobs). So the iOS path is untested by upstream CI and can regress at any
commit.

**Impact.** The single engine this project depends on can break for iPadOS
without warning, and upstream will not accept fixes for it. This is a
maintenance-cost and schedule-risk issue, not a technical one — but it is the
kind that kills a project 18 months in.

**Proposed solution.**

1. Pin the SHA (done — `docs/PINS.md`) and carry patches in `patches/`.
2. Own the iOS build in CI: a GitHub Actions job that builds the pinned SHA for
   `arm64-apple-ios` on every change to the patch set.
3. Decide explicitly whether Deez Retro ever upstreams anything. Given the
   README, plan for "no" and budget accordingly.
4. Keep the engine boundary thin and honest (`Bridge/DeezRetroCore.mm` is ~300
   lines against Flycast's embeddable API). If Flycast ever becomes untenable,
   the frontend and the whole app shell survive a swap to another Dreamcast
   core — only the bridge is rewritten.

---

## B-5 · The iOS shell's JIT state is displayed but never used — **S3**

**Verified.** `FlycastViewController.mm` computes `iosJitAuthorized` and
`iosJitStatus`, and uses them *only* for UI status text:

```
FlycastViewController.mm:51   static bool iosJitAuthorized;
FlycastViewController.mm:774  if (!iosJitAuthorized && getTimeMs() - lastCheckTime > 10000)
FlycastViewController.mm:779  return iosJitStatus.c_str();
```

Nothing in `shell/apple/` touches `config::DynarecEnabled`. But
`core/emulator.cpp:520-541` picks the executor purely from that option:

```cpp
#if FEAT_SHREC != DYNAREC_NONE
    if(config::DynarecEnabled) return recompiler;
#endif
    return interpreter;
```

So with JIT unavailable, a `DYNAREC_JIT` build still tries the recompiler, and
the failure surfaces later as an executable-memory allocation failure rather than
a clean fallback.

**Impact.** On a JIT-denied device the app behaves badly instead of degrading.
The user-visible symptom is a crash or a silent hang at game start, which is
exactly the confusing failure mode that makes emulator ports look broken.

**Proposed solution.** Already implemented in the Deez Retro bridge, not as an
engine patch: `DRCoreNotifyJITAcquired()` calls
`config::DynarecEnabled.override(true)` only after JIT is genuinely authorized, and
`startEngine:` reports `interpreter (no JIT)` otherwise. See
`Bridge/DeezRetroCore.mm`. Additionally ship a **`TARGET_NO_REC` interpreter build**
for first bring-up so there is no recompiler to fail in the first place.

---

## B-6 · Flycast's iOS frontend is not reusable for a SwiftUI app — **S3**

**Verified.** `shell/apple/emulator-ios/emulator/` is a ~20-file UIKit app:
`AppDelegate.mm`, `FlycastViewController.mm`, storyboards, `.xib` pad editors, and
iCade keyboard support. `CMakeLists.txt:1284-1345` builds it as a `MACOSX_BUNDLE`
Xcode target complete with `Xcode` attributes and an `ldid`-based packaging step:

```
CMakeLists.txt:1371  COMMAND ldid -S…/flycast.entitlements …/Payload/Flycast.app/Flycast
```

Its entitlements are minimal and revealing
(`shell/apple/emulator-ios/emulator/flycast.entitlements`):

```xml
<key>application-identifier</key><string>com.flyinghead.Flycast</string>
<key>get-task-allow</key><true/>
```

i.e. **only** `get-task-allow` — the entitlement that makes the debugger/JIT trick
possible, which is precisely what an App Store build cannot have.

**Impact.** We must not inherit that target. We need the core as a library.

**Proposed solution.** Compile Flycast's `core/` into a static library that omits
`shell/apple/emulator-ios/*` and the `main()` in `core/emulator.cpp`, then link it
into DeezRetro. `scripts/build-flycast-ios.sh` documents this and is explicit that
producing a linkable library target is *remaining work* — Flycast currently only
offers `add_executable` for the Apple path (`CMakeLists.txt:277-278`). This is the
main concrete build task of the PoC.

---

## B-7 · OpenMP is unavailable on iPadOS — **S3**

**Verified.** `USE_OPENMP` defaults ON (`CMakeLists.txt:90`) and
`find_package(OpenMP)` is attempted with a Homebrew `libomp` hint
(`CMakeLists.txt:434-453`). That hint is macOS-only; on iOS there is no system
OpenMP runtime, so the feature will silently not be found.

**Impact.** Any Flycast work parallelised with OpenMP runs serially. It is not
clear how much of the Dreamcast path uses OpenMP — that needs checking during
bring-up, and the honest position is that the magnitude is **unknown**.

**Proposed solution.** Build with `-DUSE_OPENMP=OFF` (as
`scripts/build-flycast-ios.sh` does) and treat any resulting performance gap as a
measured finding. If OpenMP turns out to matter, a statically-linked `libomp`
built for `arm64-apple-ios` is the fix, not a rewrite.

---

## B-8 · PlayStation 2 is a different order of problem — **S2**

Covered in depth in `docs/PHASE1-FEASIBILITY.md` section 7. Summary of the
structural argument: the PS2 has an Emotion Engine plus two vector units, and the
in-scope emulators (Play!, PCSX2) rely on JIT recompilation for anything close to
playable speed. That makes them dependent on every blocker above being solved,
*and* dependent on an ARM64 recompiler path existing for EE and VU. A
Dreamcast-first sequence is therefore not a preference, it is the only sequencing
that produces a working product.

---

## Summary table

| ID | Blocker | Severity | Status |
|---|---|---|---|
| B-1 | iPadOS forbids JIT for third-party apps; App Store builds can never hold the entitlement | S2 | Verified |
| B-2 | iOS 26 TXM/SPTM needs per-region preparation; regions must pre-exist detach | S3 | Verified (protocol documented) |
| B-3 | No Metal renderer; iOS forces Vulkan off; GLES3 only, and deprecated | S3 | Verified |
| B-4 | Upstream dropped iOS support; no iOS CI | S2 | Verified |
| B-5 | iOS shell's JIT state never reaches `config::DynarecEnabled` | S3 | Verified |
| B-6 | iOS shell is an unrunnable-frontend-for-us app, not a library | S3 | Verified |
| B-7 | OpenMP unavailable on iPadOS; magnitude unknown | S3 | Verified (impact unmeasured) |
| B-8 | PS2 engines are JIT-dependent and lack a proven ARM64 recompiler path | S2 | See report §7 |
| B-9 | No Mac or iPad in this session; nothing has been compiled or run | S1 | Verified |

## B-9 — the one that binds everything

This session ran on a **Windows** host. Verified absent: `cmake`, `clang`,
`clang++`, `ninja`, `make`, `pkg-config`, and any Apple SDK. A physical M4 iPad
Pro was not available.

Therefore: **no part of Deez Retro has been compiled, signed, deployed, or
benchmarked.** Every statement in this repository about engine behaviour is
derived from reading pinned source. Every statement about iPadOS capability is
derived from Apple/StikJIT/Provenance primary documentation. The moment a Mac
with Xcode and the iPad are available, `docs/XCODE-BUILD-PLAN.md` is the ordered
procedure to turn this from a plan into evidence.
