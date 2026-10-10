# Benchmark plan — M4 iPad Pro

## Status: NOT EXECUTED

No benchmark has been run. This machine is a **Windows** host with no Apple
toolchain (`cmake`, `clang`, `ninja`, and Xcode are all absent — verified), so it
cannot compile for iPadOS, cannot sign, and cannot deploy. The M4 iPad Pro was
not available to this session.

Everything below is the **method** to be executed once a Mac with full Xcode and
the physical iPad are in hand. No number in this document is a measurement.

> Brief constraint, honoured literally: *"Do not claim an emulator works until it
> has compiled and run on the physical iPad."* Nothing here claims that.

## Targets

| Metric | Target | Why |
|---|---|---|
| Dreamcast gameplay | 60 fps sustained (NTSC) / 50 fps (PAL) | Dreamcast renders at 60 Hz; anything less is frame-skipping |
| Frame time p99 | ≤ 16.6 ms | avoids audio/video desync |
| Audio | no underruns over a 10-minute run | audio glitches are the first sign of a CPU-starved core |
| Thermal | no sustained-clock collapse over 30 min | M4 iPad Pro is fanless; throttling is the real risk |
| Peak memory | under the iPadOS jetsam limit for the device | Dreamcast + dynarec arenas are allocation-heavy |

## Build matrix

Each row must be measured separately. The A/B between rows 1 and 2 is the single
most important result of Phase 1, because it decides whether JIT is a hard
requirement for Dreamcast or a nice-to-have.

| # | Configuration | Build flags | JIT needed |
|---|---|---|---|
| 1 | Interpreter, no JIT | `-DTARGET_NO_REC` | no |
| 2 | SH4 dynarec via StikDebug-acquired JIT | default (`FEAT_SHREC=DYNAREC_JIT`) | yes |
| 3 | SH4 dynarec + `FEAT_NO_RWX_PAGES` | `-DFEAT_NO_RWX_PAGES` | yes |
| 4 | Row 2/3 at 2× internal resolution | renderer setting | yes |

Row 3 exists because Flycast's W^X-safe JIT path (`prepare_jit_block`, which
maps an RX region and a separate RW alias over the same file-backed pages) is
implemented for ARM64 but currently only enabled for Nintendo Switch — see
`core/build.h:62-64`. It is the natural place to hang the iOS 26 TXM
region-preparation protocol described in `docs/BLOCKERS.md` B-2.

## Test content

Use fixed, reproducible content so runs are comparable:

- **CPU-bound:** *Sonic Adventure* — Emerald Coast, heavy SH4 load, stable scene.
- **GPU-bound:** *Shenmue* — Dobuita at day, heavy PowerVR2/TA load.
- **Audio-bound:** *Jet Set Radio* — continuous AICA streaming.
- **Boot/loader:** *Crazy Taxi* — measures GD-ROM load throughput.

Also record a cold-boot time-to-first-frame and a save-state round trip
(write + read + verify checksum) for each title.

## Instrumentation

The bring-up screen already exposes the minimum: execution mode, renderer, and a
rolling 1-second FPS computed from Flycast's own vblank event
(`DeezRetroCore.mm` → `EventManager::listen(Event::VBlank, …)`).

For real numbers, add:

1. **Frame time histogram, not just FPS.** Mean FPS hides stutter. Sample per-frame
   intervals and report p50/p95/p99.
2. **Core split.** Flycast runs CPU and renderer on separate threads
   (`emu.start()` starts the execution thread). Measure SH4 interpreter/dynarec
   time separately from render time. `ENABLE_DC_PROFILER=ON` gives the target-machine
   (SH4) profiler; `ENABLE_FC_PROFILER=ON` profiles the host app.
3. **Audio underrun counter.** The CoreAudio backend (`core/audio/audiobackend_coreaudio.cpp`,
   `kAudioUnitSubType_RemoteIO` on iOS) should count callbacks where the buffer
   was not filled in time.
4. **Thermal/power.** `os_proc_available_memory()` for headroom, plus
   `ProcessInfo.processInfo.thermalState` sampling every 10 s, and a note of when
   it first leaves `.nominal`.
5. **Energy.** Xcode's Energy Log, over a fixed 15-minute scripted run.

## Procedure

1. Build row 1 (interpreter). This is expected to work with no JIT and no
   entitlements — it is the fallback that must be proven first, because it is the
   only configuration that can ship on the App Store at all.
2. Deploy to the iPad via Xcode. Record whether `statusForEngine:` reports
   `interpreter (no JIT)` — it must.
3. Run each test title for 10 minutes with the bring-up screen's counters visible.
   Capture the frame-time histogram.
4. Repeat for row 2, this time going through JIT acquisition
   (`JIT/JITAcquisition.swift`). Record whether `CS_DEBUGGED` appears and whether
   `DRCoreNotifyJITAcquired()` flips the reported mode to `dynarec (JIT)`.
5. Repeat for rows 3 and 4.
6. 30-minute thermal soak on the best-performing row.

## Reporting rules

- Report the **build SHA and config row** with every number.
- Distinguish *measured* from *expected*. Nothing is "expected 60 fps"; it is
  either measured or unmeasured.
- If the interpreter cannot reach playable speed — which is the likely outcome and
  the reason this is the top risk — that is a **finding**, not a failure to hide.
  It converts "iPadOS emulator" into "iPadOS emulator that requires a sideloading
  workflow", which is a product decision for the user, not an engineering one.

## Known measurement hazards

- **Simulator numbers are meaningless.** The iOS simulator forces `TARGET_NO_REC`
  (`core/build.h:41-44`), so a simulator build can never exercise the dynarec. Any
  simulator benchmark measures x86-64-on-macOS interpreter performance and says
  nothing about the M4.
- **Debug builds are meaningless.** Flycast's CMake sets `CMAKE_CXX_FLAGS_DEBUG` to
  `-O3` on some paths but Release is the only configuration worth measuring. Use
  `Release` (`-DCMAKE_BUILD_TYPE=Release`).
- **Low Power Mode changes results.** Pin it off and record the setting.
- **First-run shader/pipeline compilation** inflates the first seconds. Discard the
  first 30 s of every run.
