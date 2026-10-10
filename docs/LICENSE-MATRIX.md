# License matrix

All licences below were read directly from the pinned checkouts on 2026-10-10,
not from memory or from third-party summaries.

## Engine licences

| Engine | Console | Licence | Evidence |
|---|---|---|---|
| **Flycast** | Dreamcast | **GPL-2.0-or-later** | `LICENSE` is the verbatim GNU GPL v2 text. Per-file headers state "either version 2 of the License, or (at your option) any later version" (`core/emulator.h:9-10`) |
| **Play!** | PlayStation 2 | **BSD-2-Clause** | `License.txt`: "Copyright (c) 2006-2026, Jean-Philip Desjardins", two numbered clauses, standard warranty disclaimer |
| **PCSX2** | PlayStation 2 | **GPL-3.0-or-later** | `COPYING.GPLv3` is the only licence file (GNU GPL v3 text). SPDX scan of `pcsx2/`: 649 files `GPL-3.0+`, 13 `GPL-2.0+`, 12 `GPL-3.0`, 3 `MIT`, 1 `BSD-3-Clause` |

Note on precision: the entire `pcsx2/arm64/` subtree (the code an Apple Silicon
port would actually extend) is `GPL-3.0` **without** the `+`, while the bulk of
the tree is `GPL-3.0+`. Since `GPL-3.0` alone is not "or later", mixing the arm64
subtree into a GPL-4.0 work would not be permitted — irrelevant today, but it is
the kind of detail that decides relicensing questions later.

> **Correction worth flagging:** PCSX2 is widely described online as LGPL. It is
> not. At this SHA the only licence file is `COPYING.GPLv3`, and GPL-3.0+
> dominates the SPDX headers by a factor of ~50. Any Deez Retro plan that assumed
> "PCSX2 is LGPL, so we can link it freely" is wrong.

## The inversion that matters

The licensing situation is **inverted** relative to the technical one:

| | Dreamcast (Flycast) | PS2 (Play! / PCSX2) |
|---|---|---|
| Technical feasibility on iPadOS | **High** — complete iOS shell, GLES3 renderer, CoreAudio, GameController, interpreter fallback, embeddable API | **Low** — JIT-dependent, no ARM64 EE/VU recompiler in PCSX2, Qt-bound frontends |
| App Store licence viability | **Poor** — GPL-2.0 | **Good** for Play! (BSD-2); **Poor** for PCSX2 (GPL-3.0) |

So the console that is easiest to make work is the one that is hardest to ship
legally, and vice versa. This should shape sequencing more than any engineering
preference.

## Why GPL + App Store is a genuine problem

The Free Software Foundation's long-standing position is that GPL'd software
cannot be distributed through the App Store, because Apple's Terms of Service
impose restrictions the GPL forbids — notably DRM/FairPlay requirements and a
limit on the number of devices a user may install to. This is not a hypothetical
lawyer's worry; it is why VLC was pulled from the App Store in 2011 and why
GPL emulators are distributed via sideloading, AltStore, or Cydia rather than the
App Store.

It is worth noting that this is also *precisely why* the iOS emulator ecosystem
looks the way it does:

- Flycast's iOS shell is built for **AltStore** (`shell/apple/emulator-ios/AltKit/`,
  a full Swift package for AltServer discovery) and its entitlements contain only
  `get-task-allow` — an entitlement the App Store does not grant.
- Play!'s iOS shell likewise has `Source/ui_ios/AltServerJitService.mm` and
  `deps/AltKit`, gated on `PREFERENCE_ALTSTORE_JIT_ENABLED`.
- Provenance explicitly strips `com.apple.developer.kernel.allow-jit` from
  App Store builds because Apple rejects it in review.

Deez Retro should decide this **before** writing much code, because it determines
whether the target is "a sideloaded app for enthusiasts" (then GPL Flycast is
fine and JIT is available) or "an App Store product" (then Flycast's GPL is the
first problem, ahead of any technical one).

## Consequence for Deez Retro's own code

- **The app's own SwiftUI/bridge code** can be licensed however the project wants.
  It is separate from the engines.
- **Linking GPL-2.0 Flycast into the app** means the combined work must be
  distributed under GPL-2.0. That is compatible with sideloading/AltStore; it is
  what Flycast itself already does.
- **Mixing Flycast (GPL-2.0) with Play! (BSD-2) or PCSX2 (GPL-3.0)** in one binary
  needs care. GPL-2.0-only code is *not* compatible with GPL-3.0 code. Since
  Flycast is GPL-2.0-**or-later**, it can be taken to GPL-3.0 and combined with
  PCSX2. Combining Flycast with BSD-2 Play! is also fine (permissive code can be
  absorbed into a GPL work).
- **Practical recommendation:** keep each engine in its own process or at minimum
  its own clearly-bounded module, document the combined-work licence, and make the
  source available. Do not assume a proprietary Deez Retro binary is possible
  while Flycast is statically linked.

## Third-party dependency surface

### Flycast (23 git submodules)

`core/deps/`: SDL, libchdr, luabridge, breakpad, Vulkan-Headers,
VulkanMemoryAllocator, glslang, oboe, Syphon, Spout, discord-rpc, libadrenotools,
rcheevos, googletest, asio, xbyak, libjuice, websocketpp, DreamPicoPort-API,
tinygettext, freetype, gamesdk.

A scan of non-`deps` sources with SPDX headers found 32 files under
`Apache-2.0 WITH LLVM-exception`, 6 `BSD-2-Clause`, 4 dual
`(WTFPL OR CC0-1.0) AND Apache-2.0`, 2 `GPL-2.0-only`, 1 `Apache-2.0`, and one
`(GPL-3.0 OR CC-BY-NC-ND-4.0)`. **The `CC-BY-NC-ND-4.0` option is non-commercial
and no-derivatives** — it is offered as an alternative to GPL-3.0, so the GPL
branch can be taken, but it is worth locating that file before any commercial
distribution. For an iPadOS build, only the `libchdr`, `rcheevos`, `tinygettext`,
`freetype`, `xxHash`, `glm`, `luabridge`, `asio`, `websocketpp` and `libzip`
submodules matter; the Vulkan/SDL/breakpad ones are inert because iOS forces
`USE_VULKAN=OFF` and Apple defaults `USE_HOST_SDL=OFF`.

### Play!

Six submodules: `deps/Dependencies`, `deps/Framework`, `deps/CodeGen`,
`deps/Nuanceur`, `deps/libchdr`, `deps/AltKit`. `deps/CodeGen` is the **Jitter**
library that provides `Jitter::CreateCodeGen()` — i.e. the actual native code
generator, including the AArch64 backend used by Play!'s own AOT tool
(`tools/PsfPlayer/Source/ui_aot/Main_Aot.cpp:11` includes
`Jitter_CodeGen_AArch64.h`). The engine's correctness and its ARM64 viability
therefore live in a separate repository that must be audited on its own terms.

### PCSX2

`3rdparty/` holds 28 directories and 1,079 files, including `vixl` (ARM64
assembler), `xbyak` (x86 assembler), `zydis` (x86 disassembler), `vulkan`,
`cubeb`, `imgui`, `fmt`, `rapidjson`, `zstd`-adjacent `lzma`, `libzip`, `libchdr`,
`rcheevos`, `soundtouch`, `cpuinfo`, `googletest`. The emulation core itself is
1,015 files across `pcsx2/`, `pcsx2-qt/` and `common/`. Qt6 is **not** vendored —
it is an external requirement, and `pcsx2-qt/` is the desktop frontend.

## Summary

| Question | Answer |
|---|---|
| Can we ship Flycast in the App Store? | Very likely no, because GPL-2.0 conflicts with App Store ToS. Sideload/AltStore: yes. |
| Can we ship Play! in the App Store? | Licence-wise yes (BSD-2). Technically it needs JIT, which the App Store cannot grant. |
| Is PCSX2 LGPL as commonly stated? | No — GPL-3.0-or-later at this SHA. |
| Does Deez Retro's own code have to be GPL? | Yes, if it statically links Flycast. |
