# Deez Retro — Phase 1 technical feasibility report

**Target:** native iPadOS emulator for Apple M4 iPad Pro · Sega Dreamcast + Sony PlayStation 2
**Date:** 2026-10-10
**Engines inspected:** Flycast `ed953fcb`, Play! `83700b2c`, PCSX2 `6bdd913a`
**Status:** feasibility established from source inspection. **Nothing has been compiled or run.**

---

## 1. Verdict in one page

**Dreamcast (Flycast): feasible, and closer than expected.** Flycast already contains
a complete, working iPadOS path — GLES3 renderer, CoreAudio `RemoteIO` backend,
`GameController` input including DualShock touchpad and haptics, an embeddable C++
API, and a full SH4 **interpreter** that runs with no JIT and no entitlements. The
work is not "port an emulator"; it is "compile an existing core as a library and
replace its UIKit frontend with SwiftUI." The dominant unknown is **interpreter
speed on M4**, which is unmeasured.

**PlayStation 2: not feasible in Phase 1, and probably not in Phase 2.** Both
candidate engines fail at a more fundamental level than Dreamcast:

- **Play!** has **no interpreter at all**. Every basic block of the Emotion Engine
  and both vector units is JIT-compiled. Its own README states the app *will crash*
  without JIT. There is no fallback to enable.
- **PCSX2** *does* have interpreters and they work on arm64 — but upstream ships an
  explicit warning that Apple Silicon support is **INCOMPLETE**, that there are
  **no EE/VU/IOP recompilers**, and that "games will run **VERY slow**", with "no
  date for completion yet" (`CMakeLists.txt:84-93`, quoted verbatim in §7).

**The one blocker that outranks all engineering: iPadOS does not permit JIT for
third-party apps.** On iOS 26 with M-series hardware (which includes M4), a plain
debugger attach is *no longer sufficient* — every executable region must be
prepared through a debug connection using a magic-breakpoint protocol, and the
regions must exist before the debugger detaches. This is a product-level constraint:
an App Store build can **never** hold the JIT entitlement, because Apple rejects it
in review. It is a fact about the platform, not a bug to fix.

**Recommendation:** proceed with Dreamcast-only, interpreter-first, as a
sideload/AltStore-class application. Treat PS2 as a separate, later, and much
larger investigation. Do not begin PS2 work until a Dreamcast title is running
on the physical iPad.

---

## 2. What was actually done, and the honest limitation

### Method

Three upstream repositories were shallow-cloned and pinned to exact commits
(`docs/PINS.md`), then read directly. Every engine claim in this report cites a
file and line in those checkouts. Platform claims cite Apple, StikJIT, or
Provenance primary documentation (`docs/BLOCKERS.md` carries the sources).

### Limitation — read this before trusting anything

The session ran on a **Windows** host. Verified absent: `cmake`, `clang`,
`clang++`, `ninja`, `make`, `pkg-config`, and any Apple SDK. No M4 iPad Pro was
available.

Therefore, per the brief's own rule — *"Do not claim an emulator works until it has
compiled and run on the physical iPad"* — **this report claims no working
emulation.** It establishes:

- what the engines contain, with citations ✓
- what iPadOS will and will not permit, from primary sources ✓
- what must be built, and in what order ✓

and it does **not** establish:

- that Flycast compiles for `arm64-apple-ios` at this SHA ✗
- that the interpreter is fast enough to be playable ✗
- that JIT acquisition works on iOS 26 / M4 ✗
- any frame rate, CPU load, audio quality, or thermal figure ✗

Those are the Phase 1 experiments, and they need a Mac and the device.

---

## 3. The platform constraint: iPadOS and JIT

This section is the reason the project is hard, so it comes first.

### 3.1 Third-party apps cannot JIT

iPadOS enforces W^X. A sandboxed app cannot map writable memory as executable.
Every ARM64 CPU recompiler in scope needs that.

Flycast's own iOS shell contains a routine copied from PPSSPP
(`shell/apple/emulator-ios/emulator/FlycastViewController.mm:379-446`) whose only
purpose is to obtain the `CS_DEBUGGED` process flag, described in its own comment as:

```c
#define CS_DEBUGGED 0x10000000 /* process is currently or has previously been
                                  debugged and allowed to run with invalid pages */
```

It then falls back to **AltKit** (AltStore) to get an external debugger attached.
Play! does the same thing twice over — `Source/ui_ios/DebuggerSimulator.cpp:10-14`
calls `ptrace(PT_TRACE_ME, …)` on itself, and `Source/ui_ios/AltServerJitService.mm`
talks to AltServer. Three independent projects converging on the same two hacks is
strong evidence that there is no fourth option.

### 3.2 iOS 26 + M-series adds a second, harder requirement

On **TXM/SPTM** hardware — which includes M4 — debugger attach alone is *not*
enough. Per StikJIT's integration guide (maintained by the StikDebug authors):

> Where TXM/SPTM is present, the debugger flag alone is not enough: each executable
> memory region must be prepared through the debug connection before the app executes
> code from it.

> **Preallocate executable regions before detaching.** A region introduced later
> cannot be prepared by a script that has already detached; reconnect and repeat the
> protocol if the engine must add one.

The host must call a magic breakpoint per region:

```c
__attribute__((noinline, optnone, naked))
void* JIT26PrepareRegion(void* address, size_t length) {
    __asm__("mov x16, #1\n" "brk #0xf00d\n" "ret\n");
}
```

**Why this bites specifically on M4.** Most JIT engines — Flycast included —
allocate code memory lazily and grow it as blocks are translated. TXM forbids
that: the arena must be reserved and prepared up front, and never extended
afterwards. This is a real engineering task, not a flag.

### 3.3 App Store builds can never have the entitlement

`com.apple.developer.kernel.allow-jit` is the iOS 26 native JIT entitlement.
Apple rejects it in App Store review. Provenance learned this the hard way and
recorded it in a changelog:

> **JIT entitlement removed from App Store builds** — `com.apple.developer.kernel.allow-jit`
> is not permitted in App Store submissions; removed from `Provenance.entitlements`,
> `Provenance-AppStore.entitlements`, and `Provenance-Mini.entitlements`. App Store users
> continue to use debugger-attach, TrollStore, StikDebug, AltJIT, or JitStreamer paths.

### 3.4 What this means for the product

JIT is not a build configuration; it is an **install and launch workflow**. On a
stock iPad the user must: enable Developer Mode, obtain and store a pairing file,
run a helper app (StikDebug from the App Store, or a built-in StikJIT extension),
mount a Developer Disk Image, and acquire JIT **before** the game starts.

This forces a two-track design, and makes `docs/BENCHMARK-PLAN.md` rows 1 vs 2 the
single most decision-relevant measurement in the project:

| | Track A — interpreter | Track B — dynarec |
|---|---|---|
| JIT needed | no | yes |
| Entitlements | none | `get-task-allow` + external helper |
| App Store distributable | yes (license permitting) | no |
| Speed | **unknown — the key experiment** | expected much faster, also unmeasured |

---

## 4. Engine capability matrix

No engine has all four of the things a comfortable iPadOS port needs. This table
is the core of the feasibility argument.

| Capability | **Flycast** (DC) | **Play!** (PS2) | **PCSX2** (PS2) |
|---|---|---|---|
| CPU **interpreter** fallback | **Yes** — `core/hw/sh4/interpr/` | **No** — JIT-only, crashes without JIT | **Yes** — all four CPUs (`Interpreter.cpp`, `R3000AInterpreter.cpp`, `VU0/1microInterp.cpp`) |
| ARM64 CPU **recompiler** | **Yes** — `core/rec-ARM64/rec_arm64.cpp` | **Yes** — `Jitter::CCodeGen_AArch64` | **No** — `pcsx2/arm64/` has 6 files, none a CPU recompiler |
| Existing **iOS shell** | Yes, but **dropped upstream** | Yes, ships via AltStore/Cydia | **None whatsoever** |
| **Metal** renderer | **No** | **No** | **Yes** — complete, default on macOS |
| **GLES3** renderer | **Yes** — used by its iOS shell | Yes (`GSH_OpenGLiOS.cpp`) | No (OpenGL not built on Apple) |
| Vulkan/MoltenVK on iOS | Yes in code, but iOS **forces it off** | Yes — bundled `MoltenVK.xcframework` | Yes — `dlopen` MoltenVK |
| JIT memory hygiene | RWX anonymous `mmap` on iOS; a W^X path exists but is off | **Strictly W^X** — `vm_protect` R\|X ↔ R\|W | **Permanently RWX** — never demoted |
| Core/frontend separation | `core/` + `shell/`, embeddable API | `PlayCore` static lib + `CPS2VM` | `PCSX2` lib + `Host::` (Qt-free) |
| Licence | GPL-2.0-or-later | **BSD-2-Clause** | GPL-3.0-or-later |
| Core size (excl. deps) | 533 files / ~176k lines | ~472 files / ~92k lines | 713 files / ~298k lines |

Reading the table: **Flycast is the only engine with a usable no-JIT path *and* an
existing iOS shell.** That is why Dreamcast goes first, and it is a technical
conclusion, not a preference.

---

## 5. Flycast / Dreamcast — the feasible one

### 5.1 It already has an iPadOS path

`CMakeLists.txt:31-33` accepts `CMAKE_SYSTEM_NAME=iOS` with an arm64-only
deployment target. The shell at `shell/apple/emulator-ios/` provides:

- **Renderer:** GLES3, via `EAGLContext`. iOS is hard-wired to it —
  `GLES`/`GLES3`/`HAVE_OPENGLES3` are force-defined (`CMakeLists.txt:313-315`) and
  Vulkan is force-disabled (`CMakeLists.txt:110-112`).
- **Audio:** `core/audio/audiobackend_coreaudio.cpp` uses `AudioUnit` with
  `kAudioUnitSubType_RemoteIO` on iOS (line 89) — the correct iOS output unit.
- **Input:** `ios_gamepad.h` uses `GameController` and already maps
  `GCInputDualShockTouchpadButton` (line 306) and `GCInputXboxPaddle*`, plus haptics
  via `CHHapticEngine` (line 313). **The DualSense requirement is largely met at the
  engine level** and needs on-device confirmation only.
- **File access:** `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, and
  exported UTIs for `.chd/.gdi/.cue/.cdi` (`plist.in:41-130`).

### 5.2 The no-JIT path genuinely exists

`core/build.h:50-54`:

```c
#if defined(TARGET_NO_REC)
#define FEAT_SHREC DYNAREC_NONE
#define FEAT_AREC  DYNAREC_NONE
#define FEAT_DSPREC DYNAREC_NONE
#endif
```

and `core/emulator.cpp:520-541` selects the executor at runtime:

```c
#if FEAT_SHREC != DYNAREC_NONE
    if(config::DynarecEnabled) return recompiler;
#endif
    return interpreter;
```

A complete SH4 interpreter exists at `core/hw/sh4/interpr/sh4_interpreter.cpp`
(`Run()`, `Step()`, `ExecuteOpcode()`). So an interpreter-only build needs **zero
JIT and zero entitlements** — the only configuration that could ever be App Store
distributable.

Note that `TARGET_NO_REC` is auto-defined **only for the iOS simulator**
(`core/build.h:41-44`), and there is no CMake option for it, so a device build must
set the macro itself. `scripts/build-flycast-ios.sh` does exactly that.

### 5.3 The work is real but bounded

It is *not* drop-in. Four concrete tasks:

1. **Produce a linkable library.** Flycast only builds an app for Apple targets
   (`CMakeLists.txt:277-278` adds `add_executable`). Its iOS frontend
   (`shell/apple/emulator-ios/`, ~20 files, ~4,620 lines under `shell/apple`) must be
   excluded and a static/object library target added. This is the main PoC task.
2. **Wire JIT state into the engine.** The upstream iOS shell computes
   `iosJitAuthorized` and uses it *only* for status text — nothing in `shell/apple/`
   touches `config::DynarecEnabled`. So a JIT-denied device still tries the
   recompiler and fails in executable-memory allocation instead of degrading
   cleanly. Deez Retro fixes this at the bridge
   (`DRCoreNotifyJITAcquired()` → `config::DynarecEnabled.override(true)`), not by
   patching the engine.
3. **Fix the iOS JIT allocator for TXM** (§3.2) — enable `FEAT_NO_RWX_PAGES`
   (already implemented for ARM64, currently Switch-only, `core/build.h:62-64`) and
   pre-reserve the arena so it can be region-prepared before detach.
4. **Accept the upstream risk.** `README.md:61-63` states iOS support has been
   *dropped*: "Due to persistent harassment from an iOS user, support for this
   platform has been dropped." There is no iOS job in `.github/workflows/`
   (`android`, `bsd`, `c-cpp`, `switch`, `uwp` only). Hence the pinned SHA plus a
   patch set.

### 5.4 What is not known

- **Interpreter speed on M4.** No number exists in this report because none was
  measured. This is the project's single most important open question.
- Whether the 23 submodules build cleanly for iOS (`glslang` is inert because Vulkan
  is off; `breakpad`, `SDL`, `Syphon`, `Spout` are excluded by default flags).
- OpenMP: `USE_OPENMP` defaults ON but is unavailable on iPadOS. Its performance
  significance is **unknown**; Phase 1 builds with it off.

---

## 6. Play! / PS2

Full detail in `docs/appendix-A-play-engine-inspection.md`.

**The decisive fact: Play! has no interpreter.** Exhaustive search for `interpret`
across the repository returns 946 matches, *all* of them `reinterpret_cast`. There
is no `CMIPSInterpreter`, no interpreter file. `CGenericMipsExecutor::Execute` has
exactly one execution path, calling JIT-generated code:

```cpp
// Source/BasicBlock.cpp:331-333
void CBasicBlock::Execute() { m_function(&m_context); ... }
```

Every basic block — EE, VU0, VU1, macro and micro mode — is compiled through
`Jitter::CreateCodeGen()` (`Source/BasicBlock.cpp:90`). Play!'s own README is
blunt:

> **If you try to play a game without JIT enabled, you will experience a crash when
> you launch the game.**

and the app reinforces it with an alert (`Source/ui_ios/CoverViewController.mm:194`):
*"JIT doesn't seem to be available at the moment. If JIT is not available, the
emulator will crash. Do you wish to continue?"*

**Good news, which makes Play! the more interesting PS2 option:**

- **BSD-2-Clause** (`License.txt`) — permissive, no App Store conflict.
- A real **AArch64 backend exists** (`Jitter::CCodeGen_AArch64` +
  `AArch64Assembler.cpp` in `deps/CodeGen`), already exercised natively on Apple
  Silicon through universal macOS builds.
- The **iOS executable-memory path is already W^X-clean**: iOS uses
  `MEMFUNC_USE_MACHVM` with `MEMFUNC_MACHVM_STRICT_PROTECTION`, a single
  `vm_allocate` mapping that alternates `R|X` ↔ `R|W` via `vm_protect` and is
  **never simultaneously RWX**. That removes a whole class of hardening objection.
- **`PlayCore` is a proper static library** (`Source/CMakeLists.txt:567-576`) with a
  clean injectable API (`CPS2VM` in `Source/PS2VM.h`: `Resume`/`Pause`,
  `CreateGSHandler`, `CreatePadHandler`, `CreateSoundHandler`, `SaveState`/`LoadState`,
  `OnNewFrame`). The iOS CMake project already enables Swift
  (`project(PlayUI LANGUAGES C Swift)`), so a SwiftUI frontend is realistic.
- An **iOS frontend already ships** (`Source/ui_ios/`, 36 files), packaged as IPA and
  Cydia `.deb` with ad-hoc signing (`codesign -s "-"`) — i.e. deliberately outside
  the App Store.

**The one unproven avenue worth naming:** `AOT_USE_CACHE` compiles basic blocks
offline into object files and at runtime only resolves precompiled function
pointers (`Source/BasicBlock.cpp:150-174`), with an `CPU_ARCH_ARM64` object-file
target in `tools/PsfPlayer/Source/ui_aot/Main_Aot.cpp:264`. That is architecturally
the only no-JIT route. It is **off by default**, annotated "for PsfPlayer only", not
wired for iOS, and **its coverage of the full EE+VU workload is unverified.** It is
a research question, not a solution — and it would also not fix block chaining,
because `LinkBlock` patches raw pointers *into already-executable code*
(`Source/BasicBlock.cpp:399-434`).

**Verdict: not feasible for Phase 1.** Play! is the better PS2 long-term bet — BSD
licence, ARM64 dynarec already present, W^X-clean allocator, library-grade API — but
it cannot run at all without JIT, so it inherits every platform blocker in §3 at
maximum severity.

---

## 7. PCSX2 / PS2

Full detail in `docs/appendix-B-pcsx2-engine-inspection.md`.

**Upstream has already answered the question.** `CMakeLists.txt:84-93`, verbatim:

```
*************** UNSUPPORTED CONFIGURATION ***************
Apple Silicon support in PCSX2 is INCOMPLETE. There are
currently no EE/VU/IOP recompilers, and games will run
VERY slow. There is no date for completion yet, you
should set -DCMAKE_OSX_ARCHITECTURES=x86_64 for now,
unless you want to work on the recompilers.
*********************************************************
```

Corroborated in code: all EE/IOP/VU JIT is in the x86-only `pcsx2/x86/` tree (23
files, including `iR5900.cpp` at 2,366 lines and sixteen `microVU*.inl` translation
units), selected only under `ARCH_X86`. `pcsx2/arm64/` contains exactly six files —
`AsmHelpers.{cpp,h}`, `RecStubs.cpp`, `Vif_Dynarec.cpp`, `Vif_UnpackNEON.{cpp,h}` —
and `RecStubs.cpp` is explicit:

```cpp
// pcsx2/arm64/RecStubs.cpp:11-21
void vtlb_DynBackpatchLoadStore(...) { pxFailRel("Not implemented."); }
bool SaveStateBase::vuJITFreeze() {
    Console.Warning("recompiler state is stubbed in arm64!");
```

The runtime selection is a hard `#ifdef _M_X86` fence (`pcsx2/VMManager.cpp:2751-2763`)
that falls back to interpreters for all four CPUs. So **PCSX2 on arm64 runs as a
pure interpreter**, which upstream itself calls "VERY slow."

**Two surprises worth recording, because they cut both ways:**

1. **PCSX2's Metal renderer is complete and first-class** — `pcsx2/GS/Renderers/Metal/`
   holds eight `.metal` shaders (`tfx.metal` alone is 61 KB), `GSDeviceMTL.mm` (2,822
   lines), `GSTextureMTL.mm`, and `GSMTLDeviceInfo.mm`, and macOS *prefers* it
   (`GS/GSUtil.cpp:282-284`). So for PS2, graphics is not the blocker — the opposite
   of Dreamcast, where Metal does not exist and GLES3 (deprecated) is the only option.
2. **PCSX2's JIT memory is permanently RWX.** The code region is mapped through
   `PageAccess_Any()` → `PROT_READ|PROT_WRITE|PROT_EXEC` (`common/HostSys.h:47-51`,
   `common/Linux/LnxHostSys.cpp:28-40`) with `MAP_JIT` on Apple, and **nothing ever
   demotes it to RX**. vixl's `SetExecutable()`/`SetWritable()` exist in `3rdparty/`
   but are never called. That is a harder iPadOS problem than Play!'s W^X-clean
   design — iOS would refuse the mapping outright.

**Other iOS-specific walls:** no iOS code of any kind exists (zero `UIKit`/
`TARGET_OS_IPHONE` matches in `pcsx2/` and `pcsx2-qt/`); the Metal *presentation*
path includes `<AppKit/AppKit.h>`; the core uses `shm_open`/`shm_unlink` for guest RAM
(not available on iOS), `dlopen` of bundled MoltenVK/shaderc/FFMPEG, and
`NSTask`+`/bin/sh`. The `pcsx2-qt` frontend requires Qt6::Widgets **and
KDDockWidgets-qt6**, neither of which has an iOS story, so it cannot be compiled for
iPadOS at all.

**Mitigating factor:** the core is cleanly separable. `PCSX2` links no Qt; the
boundary is `pcsx2/Host.h` (~90 free functions, implemented twice — `Host.cpp` for
the core and `QtHost.cpp` for Qt); and `pcsx2-gsrunner` proves a second, Qt-free
frontend works, including a windowless `-surfaceless` mode. A SwiftUI host shim is
therefore architecturally viable — the blocker is the missing recompiler, not the
API shape.

**Verdict: not feasible.** Two independent, hard problems — (a) no ARM64 CPU
recompiler plus a permanent-RWX allocator, and (b) GPLv3+ copyleft, a desktop-only
frontend stack, and iOS-forbidden syscalls. Writing a new aarch64 recompiler
backend is an ≥8k-line project *before* the fastmem/signal-handler backpatcher, and
it would still depend on iOS granting JIT.

---

## 8. Graphics backend analysis (deliverable item 4)

The brief asks for "Metal-compatible graphics." The findings require separating two
different things, because conflating them would be misleading:

| Layer | What Deez Retro should use | Why |
|---|---|---|
| **App presentation** | Metal / MetalKit | It is the modern iOS surface API; trivially available |
| **Engine rendering (Dreamcast)** | **OpenGL ES 3** | Flycast has no Metal backend; iOS forces Vulkan off; GLES3 is what its iOS shell already uses |
| **Engine rendering (PS2, if ever)** | Metal | Already complete in PCSX2 |

So the honest statement is: *Deez Retro presents through Metal, and the Dreamcast
engine renders through OpenGL ES 3.*

**Why not Vulkan for Dreamcast?** Flycast's Vulkan backend is real, and MoltenVK is
a known quantity to this codebase — upstream's own macOS bootstrap downloads it
(`shell/apple/generate_xcode_project.command:8-96`). But that path is
**macOS-only** (`find_molten_vk` filters for `*/macOS/*`, line 67) and Flycast
hard-disables Vulkan on iOS (`CMakeLists.txt:110-112`). Re-enabling it for iOS means
producing an iOS MoltenVK slice and validating a backend the project has never run
on this platform.

**Why this is a durability risk, not a Phase 1 blocker.** Apple has deprecated
OpenGL ES since iOS 12 but has not removed it. If it ever is removed, Dreamcast
loses its only iOS renderer, and the fix would be to route through MoltenVK + the
existing Vulkan backend — **not** to write a Metal backend against Flycast's
renderer abstraction (dx9/dx11/gl4/gles/norend/vulkan — note there is no `metal`
directory).

**Correction to an assumption in the brief:** "Metal-compatible graphics" should not
be read as "the engine renders through Metal in Phase 1." It cannot, for Dreamcast.

---

## 9. Licences and dependencies (deliverable item 2)

Summary only; the full analysis is `docs/LICENSE-MATRIX.md`.

| Engine | Licence | Evidence |
|---|---|---|
| Flycast | **GPL-2.0-or-later** | `LICENSE` = GNU GPL v2 text; headers say "either version 2 … or any later version" |
| Play! | **BSD-2-Clause** | `License.txt`, two clauses |
| PCSX2 | **GPL-3.0-or-later** | `COPYING.GPLv3` only licence file; ~300 `GPL-3.0+` SPDX headers |

**PCSX2 is not LGPL**, despite being widely described that way online. At this SHA
the only licence file is `COPYING.GPLv3` and GPL-3.0+ dominates SPDX headers roughly
50:1. Any plan premised on "PCSX2 is LGPL so we can link it freely" is wrong.

**The inversion that matters more than any engineering finding:**

| | Dreamcast (Flycast) | PS2 (Play! / PCSX2) |
|---|---|---|
| Technical feasibility on iPadOS | **High** | **Low** |
| App Store licence viability | **Poor** (GPL-2.0) | **Good** for Play! (BSD-2) |

The console that is easiest to make work is the hardest to ship legally, and vice
versa. This should be decided before much code is written. A GPL-2.0 statically
linked app is a sideload/AltStore product; that is exactly how Flycast, Play!, and
Provenance all already ship on iOS, and it is consistent with the fact that all
three need `get-task-allow` — an entitlement the App Store does not grant.

---

## 10. Benchmarking (deliverable item 6)

**Not executed.** The method, targets, build matrix, instrumentation, and
measurement hazards are in `docs/BENCHMARK-PLAN.md`.

The key design of that plan is an A/B between **interpreter (row 1)** and **dynarec
(row 2)** builds. That single comparison decides whether JIT is a hard requirement
for Dreamcast or an optional accelerant — which in turn decides whether Deez Retro
can be a normal app or must be a sideload-class app.

Two hazards worth stating up front, because they invalidate whole classes of
measurement:

- **Simulator numbers are meaningless.** The iOS simulator forces `TARGET_NO_REC`
  (`core/build.h:41-44`), so a simulator build can never exercise the dynarec. It
  measures x86-64-on-macOS interpreter performance and says nothing about M4.
- **Debug builds are meaningless.** Release only.

---

## 11. Blocker register (deliverable item 8)

Full detail, with evidence and proposed solutions, in `docs/BLOCKERS.md`.

| ID | Blocker | Severity | Status |
|---|---|---|---|
| B-1 | iPadOS forbids JIT for third-party apps; App Store builds can never hold the entitlement | **S2** | Verified |
| B-2 | iOS 26 TXM/SPTM needs per-region preparation; regions must pre-exist detach | S3 | Verified |
| B-3 | Flycast has no Metal renderer; iOS forces Vulkan off; GLES3 only, deprecated | S3 | Verified |
| B-4 | Upstream Flycast **dropped iOS support**; no iOS CI | **S2** | Verified |
| B-5 | Flycast's iOS shell computes JIT state but never uses it | S3 | Verified |
| B-6 | Flycast's iOS shell is an app, not a library — must be excluded | S3 | Verified |
| B-7 | OpenMP unavailable on iPadOS; magnitude unknown | S3 | Verified |
| B-8 | PS2 engines are JIT-dependent; no ARM64 EE/VU recompiler in PCSX2; no interpreter at all in Play! | **S2** | Verified |
| B-9 | **No Mac or iPad in this session; nothing compiled or run** | **S1** | Verified |

**Proposed solutions in brief.** B-1: two-track design, interpreter-first. B-2:
enable `FEAT_NO_RWX_PAGES`, pre-reserve the JIT arena, call `JIT26PrepareRegion`
once, keep `JITWriteProtect` a no-op on iPhone as it already is. B-3: ship GLES3;
route any future Metal need through MoltenVK + existing Vulkan rather than writing a
new backend. B-4: pin + patch + own the iOS build in CI, and keep the bridge thin
(~300 lines) so the frontend survives an engine swap. B-5/B-6: already solved in
`Bridge/DeezRetroCore.mm` and `scripts/build-flycast-ios.sh`. B-8: defer PS2.
B-9: get a Mac and the device.

---

## 12. Project structure

```
deez-retro/
├── App/                      SwiftUI host (deliberately minimal — bring-up harness, not a product UI)
│   ├── DeezRetroApp.swift
│   ├── BringUpView.swift     surfaces JIT state, execution mode, renderer, live FPS
│   └── Info.plist            UIFileSharing, exported disc-image UTIs, stikdebug query scheme
├── Bridge/                   Objective-C++ — the only place that touches C++
│   ├── DeezRetroCore.h       ObjC-only interface so Swift never imports C++
│   ├── DeezRetroCore.mm      calls flycast_init / emu.loadGame / emu.start / dc_savestate …
│   └── DeezRetro-Bridging-Header.h
├── JIT/
│   └── JITAcquisition.swift  get-task-allow probe, TXM detection, CS_DEBUGGED polling, StikDebug handoff
├── engines/                  ← not committed; materialised at pinned SHAs
│   └── README.md             integration strategy + the exact API we consume
├── patches/                  ← small, reviewable patches to Flycast
├── scripts/
│   ├── fetch-engines.sh      pins all three SHAs; recursive submodules for Flycast only
│   └── build-flycast-ios.sh  arm64-apple-ios build; DEEZRETRO_NO_JIT=1 for interpreter
├── docs/
│   ├── PHASE1-FEASIBILITY.md          ← this document
│   ├── BLOCKERS.md                    full blocker register
│   ├── XCODE-BUILD-PLAN.md            ordered bring-up procedure
│   ├── BENCHMARK-PLAN.md              method for the M4 measurements
│   ├── LICENSE-MATRIX.md              licence analysis + App Store implications
│   ├── PINS.md                        exact upstream commits + submodule map
│   ├── appendix-A-play-engine-inspection.md
│   └── appendix-B-pcsx2-engine-inspection.md
└── project.yml               XcodeGen spec (source of truth for the Xcode project)
```

**Design decisions worth noting:**

- **`Bridge/` is the only Objective-C++ boundary**, exactly as the architecture
  calls for. The header is deliberately C/ObjC-only so Swift consumes it through a
  bridging header without ever importing C++.
- **The bridge is guarded by `DEEZRETRO_HAVE_FLYCAST`**, so the project builds and
  launches *before* the engine is linked, reporting "engine not linked" — the honest
  state, not a fake success.
- **`project.yml` instead of a checked-in `.xcodeproj`**, because the pbxproj blob is
  unreviewable and the project pins engine submodules that must be regenerated.
- **`engines/` is not committed.** Three engines plus 23 Flycast submodules is not a
  repository; `fetch-engines.sh` materialises them at exact SHAs.
- **No library UI, no save-state browser, no PS2 code.** The brief is explicit that
  the UI waits until the engines are proven. The app that exists is a bring-up
  harness whose job is to make the three unknowns visible on the device.

---

## 13. Minimal Xcode build plan (deliverable item 3)

Full procedure in `docs/XCODE-BUILD-PLAN.md`. The shape:

| Step | Action | Gate |
|---|---|---|
| 1 | Build Flycast alone for iOS arm64 with `-DTARGET_NO_REC` | produces a binary |
| 2 | Add a static/object library target excluding `shell/apple/emulator-ios/**` and `main()` | `nm` shows `_flycast_init`, `_flycast_term`, `_dc_savestate` |
| 3 | `xcodegen generate`; build with `DEEZRETRO_HAVE_FLYCAST=0` | app launches, reports "Linked: no" |
| 4 | Flip to `=1`, rebuild | reports "Linked: yes / interpreter (no JIT)" |
| 5 | Load a disc and run — **interpreter, no JIT, no entitlements** | **this is the Phase 1 deliverable** |
| 6 | Rebuild without `-DTARGET_NO_REC`; acquire JIT; apply the TXM arena patch | mode flips to "dynarec (JIT)" |

Step 5 is the one that matters. It needs no helper app, no Developer Mode, and no
entitlements, which makes it the cheapest possible proof that the whole SwiftUI →
ObjC++ → Flycast chain works on real hardware.

---

## 14. PS2 integration investigation (deliverable item 7)

**Conclusion: PS2 should not be attempted in Phase 1, and the two candidates should
not be treated as equivalent.**

| Question | Play! | PCSX2 |
|---|---|---|
| Can it run without JIT? | **No** — no interpreter exists; crashes | Yes — interpreters work on arm64 |
| Is that acceptable? | n/a | **No** — upstream: "games will run **VERY slow**", no completion date |
| ARM64 CPU recompiler? | Yes (`Jitter::CCodeGen_AArch64`) | **No** — `RecStubs.cpp` stubs it; x86-only tree |
| iOS code today? | Yes, ships via AltStore/Cydia | **None at all** |
| Renderer for iOS? | GLES3 + MoltenVK | Metal (complete) — but AppKit presentation |
| Licence | BSD-2 — clean | GPL-3.0+ — copyleft |
| Core size | ~92k lines | ~298k lines |
| Frontend separation | `PlayCore` static lib, injectable API | `PCSX2` lib + `Host::`, proven by `pcsx2-gsrunner` |

**If PS2 is pursued later, Play! is the better bet** — permissive licence, ARM64
dynarec already written and shipping on Apple Silicon, an already-W^X-clean
allocator, a mature iOS frontend to learn from, and a library-grade API. Its single,
total blocker is the absence of an interpreter.

**The three research questions to answer before any PS2 commitment:**

1. Does `AOT_USE_CACHE` genuinely cover the full EE + VU0 + VU1 workload, and can it
   be made to work without runtime code generation? (Off by default; "for PsfPlayer
   only"; **unverified**.)
2. How fast is PCSX2's arm64 interpreter in practice? No benchmark exists in the
   repository, so any number would be speculation. Measure it.
3. Is the iOS 26 JIT path viable for a *long-running* emulator at all — i.e. can the
   TXM region-preparation protocol tolerate an engine that wants to grow its code
   arena mid-game? This constrains Flycast too.

---

## 15. What Phase 1 does not establish

Stated plainly, because the brief's rule is explicit:

- **No emulator works.** Nothing has been compiled, signed, deployed, or run.
- **No performance figures.** No CPU, GPU, audio, frame-rate, or thermal numbers
  exist. They are unmeasured, not estimated.
- **No confirmation that JIT can be acquired on iOS 26 / M4.** The protocol is
  documented; it has not been exercised.
- **No confirmation that Flycast builds for `arm64-apple-ios` at this SHA.** The iOS
  path exists and upstream dropped support for it; a first real build may well need
  patches beyond the ones described here.
- **No verification of the DualSense path.** The engine-side mapping exists
  (`ios_gamepad.h`) but has not been tested on hardware.

The moment a Mac with Xcode and the M4 iPad are available,
`docs/XCODE-BUILD-PLAN.md` step 5 converts this document from a plan into evidence.

---

## 16. Recommended next steps

1. **Decide the distribution model first.** Sideload/AltStore (then GPL Flycast and
   JIT are both fine) versus App Store (then the licence and the JIT entitlement are
   both problems, and the honest answer may be "Dreamcast cannot ship"). Everything
   else follows from this.
2. **On a Mac: execute `docs/XCODE-BUILD-PLAN.md` steps 1–3** to prove the engine
   compiles and the SwiftUI → ObjC++ boundary works.
3. **Execute step 5 — interpreter-only on the M4.** This is the real Phase 1 gate.
4. **Then run `docs/BENCHMARK-PLAN.md` rows 1 and 2** and compare. Only then is it
   known whether JIT is mandatory.
5. **Do not start PS2 work** until a Dreamcast title runs on the device.

---

## Appendix — evidence index

| Claim area | Files read |
|---|---|
| Flycast iOS/JIT/renderer | `CMakeLists.txt`, `core/build.h`, `core/types.h`, `core/emulator.{h,cpp}`, `core/cfg/option.h`, `core/linux/posix_vmem.cpp`, `core/hw/sh4/interpr/sh4_interpreter.cpp`, `shell/apple/generate_xcode_project.command`, `shell/apple/emulator-ios/**`, `README.md` |
| Flycast audio/input | `core/audio/audiobackend_coreaudio.cpp`, `shell/apple/emulator-ios/emulator/ios_gamepad.h` |
| Play! | see `docs/appendix-A-play-engine-inspection.md` |
| PCSX2 | see `docs/appendix-B-pcsx2-engine-inspection.md` |
| iPadOS JIT | Apple developer documentation; StikJIT `INTEGRATION.md`; DolphiniOS JIT help; Provenance commit `52f8ed7` |
