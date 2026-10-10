# PCSX2 Source-Level Technical Profile — iPadOS/M4 Port Feasibility

**Repository inspected (read-only):** `C:\Users\jpatt\deez-retro-work\upstream\pcsx2`
**Commit:** `6bdd913a67ae701101780ddc4d693acfb892fe2f` (branch `master`, dated Sat Oct 10 01:13:18 2026 +0200)
**Subject:** "GS/HW: Try to use barriers first if depth buffer isn't safe to read on shuffles."

**Search method note:** all findings below come from the `read` / `grep` / `glob` tools plus `pwsh` directory listings. No shell `cat`/`grep` was used. Where something was absent I state the exact query used.

---

## 1. LICENSE

### 1.1 The project license is **GPL-3.0-or-later — NOT LGPL.**

| Evidence | Path | Lines |
|---|---|---|
| Full GPLv3 text at repo root | `COPYING.GPLv3` | 1–674; line 1–2: `GNU GENERAL PUBLIC LICENSE` / `Version 3, 29 June 2007` |
| No top-level `LICENSE` file | `glob LICENSE*` at repo root | **no top-level `LICENSE` found** (only `3rdparty/**/LICENSE*` and `bin/resources/icons/flags/LICENSE`) |
| SPDX headers in core sources | `pcsx2/*.h` | 328 matches for `SPDX-License-Identifier`; the dominant value is `GPL-3.0+` |

Verbatim SPDX examples:

```
pcsx2/R5900.h:2            // SPDX-License-Identifier: GPL-3.0+
pcsx2/VMManager.h:2        // SPDX-License-Identifier: GPL-3.0+
pcsx2/Memory.h:2           // SPDX-License-Identifier: GPL-3.0+
pcsx2/arm64/AsmHelpers.h:2 // SPDX-License-Identifier: GPL-3.0
pcsx2/GS/Renderers/Metal/GSDeviceMTL.h:2 // SPDX-License-Identifier: GPL-3.0+
```

Header line 1 in every case is `// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team`.
The repo also ships `pcsx2/Docs/GPL.txt` and `pcsx2/Docs/License.txt`.

**Answer to "Is it LGPL-3.0-or-later?" — No.** The core is `GPL-3.0+` (GPL v3 or later). `COPYING.GPLv3` is the verbatim GPLv3, not LGPL. This is copyleft and materially harder to satisfy in an App Store context than LGPL would be. (Speculation, flagged: GPLv3 + Apple App Store distribution terms are widely held to be incompatible; I did not find any source-level exception, linking exception, or App Store exception clause anywhere in the tree.)

### 1.2 License heterogeneity inside the core

A minority of core files carry other identifiers (found via `grep SPDX-License-Identifier` over `pcsx2/**/*.h`):

| License | Example files |
|---|---|
| `GPL-3.0+` | ~300 files (the overwhelming majority) |
| `GPL-3.0` (no `+`) | `pcsx2/arm64/*.{h,cpp}`, `pcsx2/GS/GSVector4_arm64.h`, `pcsx2/GS/GSVector4i_arm64.h`, `pcsx2/GS/Renderers/SW/GSDrawScanlineCodeGenerator.arm64.h`, `pcsx2/GS/Renderers/SW/GSSetupPrimCodeGenerator.arm64.h` |
| `GPL-2.0+` | `pcsx2/DebugTools/Breakpoints.h:2`, `pcsx2/DebugTools/MipsStackWalk.h:2`, `pcsx2/Mdec.h:2`, `pcsx2/IPU/mpeg2_vlc.h:2`, `pcsx2/USB/qemu-usb/USBinternal.h:2`, `pcsx2/USB/qemu-usb/hid.h:2`, `pcsx2/USB/qemu-usb/desc.h:2` |
| `MIT` | `pcsx2/USB/qemu-usb/qusb.h:2` |
| `BSD-3-Clause` | `pcsx2/USB/qemu-usb/queue.h:1` |

Note the entire `pcsx2/arm64/` tree and the arm64 GS SIMD headers are `GPL-3.0` (not `+`) — i.e. exactly the files a port would build on are GPLv3-only.

### 1.3 Bundled third-party dependencies (`3rdparty/`)

27 vendored directories. Licenses resolved by `pwsh` scanning each directory for `LICENSE*`/`LICENCE*`/`COPYING*`/`COPYRIGHT`:

| Directory | License file | License |
|---|---|---|
| `ccc` | **no license file found**; `ccc/README.md` only says it was copied from `github.com/chaoticgd/ccc` | **UNCERTAIN — no license text in tree** |
| `cpuinfo` | `LICENSE` | BSD-2-Clause style ("All rights reserved" + redistribution clauses) |
| `cubeb` | `LICENSE` | ISC ("Permission to use, copy, modify, and distribute … with or without fee") |
| `d3d12memalloc` | `LICENSE.txt` | MIT |
| `demangler` | `DemanglerLicenseGPL.txt`, `DemanglerLicenseLGPL.txt` | **GPL-2.0+/LGPL-2.1+ dual (libiberty)** — note this is the only LGPL component |
| `discord-rpc` | `LICENSE` | MIT |
| `fast_float` | `LICENSE-MIT`, `LICENSE-APACHE`, `LICENSE-BOOST` | MIT / Apache-2.0 / BSL-1.0 tri-licensed |
| `fmt` | `LICENSE` | MIT |
| `freesurround` | `GPL.txt` | **GPL-2.0** |
| `glad` | **no license file found** | **UNCERTAIN — MIT per upstream, not stated in tree** |
| `googletest` | `LICENSE` | BSD-3-Clause |
| `imgui` | `LICENSE.txt` | MIT |
| `libchdr` | `LICENSE.txt` | BSD-3-Clause |
| `libzip` | `LICENSE` | BSD-3-Clause |
| `lzma` | `LICENSE.txt` | **Public domain** ("LZMA SDK is placed in the public domain") |
| `promptfont` | `LICENSE.txt` | (present; not read in detail) |
| `rainterface` | `LICENSE` | (present; Windows-x86 only — see §2) |
| `rapidjson` | `license.txt` | MIT (with a JSON-license carve-out for `bin/jsonchecker/`) |
| `rcheevos` | `LICENSE` | MIT |
| `simpleini` | `LICENCE.txt` (British spelling) | MIT |
| `soundtouch` | `COPYING.TXT` | **LGPL-2.1** |
| `vixl` | `LICENCE` (British spelling) | 3-clause BSD ("Copyright 2015, VIXL authors / All rights reserved") |
| `vulkan` | `LICENSE.md` + `include/LICENSE.txt` | Apache-2.0 OR MIT |
| `winpixeventruntime` | **no license file found** (binary-only: `.dll`/`.lib`) | **UNCERTAIN** |
| `winwil` | `LICENSE` | MIT (Microsoft) |
| `xbyak` | `xbyak/COPYRIGHT` | BSD-3-Clause ("Copyright (c) 2007 MITSUNARI Shigeo") |
| `zydis` | `LICENSE` | MIT |

`3rdparty/include` has no license file (it is a stub/aggregate dir).

**Port-relevant point:** the LGPL components (`soundtouch`, `demangler`) are dynamically-linkable in principle, but the *core* is GPLv3+, so the overall combined work is GPLv3+ regardless.

---

## 2. BUILD SYSTEM

### 2.1 Exact top-level build files

| File | Purpose |
|---|---|
| `CMakeLists.txt` | root project file (93 lines) |
| `CMakePresets.json` | Clang/Ninja presets (`clang-base`, `ninja-multi`, `clang-debug`, `clang-devel`, `clang-release`) |
| `cmake/BuildParameters.cmake` | arch detection, options, compiler flags (346 lines) |
| `cmake/SearchForStuff.cmake` | **all external dependency discovery** (144 lines) |
| `cmake/FindFFMPEG.cmake`, `FindLZ4.cmake`, `FindZstd.cmake`, `FindWebP.cmake`, `FindShaderc.cmake`, `FindPCAP.cmake`, `FindLibbacktrace.cmake`, `FindVtune.cmake` | find-modules |
| `cmake/Pcsx2Utils.cmake`, `CheckLib.cmake`, `ShaderToCpp.cmake`, `CopyBaseTranslations.cmake` | helpers |
| `pcsx2/CMakeLists.txt` | core library (1484 lines) |
| `pcsx2-qt/CMakeLists.txt` | Qt6 GUI executable |
| `pcsx2-gsrunner/CMakeLists.txt` | headless-ish runner executable |
| `common/CMakeLists.txt` | shared utility library |
| `updater/CMakeLists.txt` | Windows-only |
| `PCSX2_qt.slnx`, `pcsx2/pcsx2.vcxproj`, `3rdparty/**/*.vcxproj` | MSVC project files |

### 2.2 CMake minimum version

```
CMakeLists.txt:3       cmake_minimum_required(VERSION 3.16...3.25)
CMakePresets.json:4-6  "cmakeMinimumRequired": { "major": 3, "minor": 19, "patch": 0 }
```
So: **3.16 minimum (declared compatible-up-to 3.25); presets require 3.19.**

```
CMakeLists.txt:14      project(Pcsx2 C CXX)
CMakeLists.txt:9-11    in-tree builds are rejected (FATAL_ERROR)
BuildParameters.cmake:147-148   set(CMAKE_CXX_STANDARD 20) / CMAKE_CXX_STANDARD_REQUIRED ON
```
**C++20 is required.** Build types: `Debug|Devel|MinSizeRel|RelWithDebInfo|Release` (default `Devel`).

### 2.3 Required external dependencies — the full list

From `cmake/SearchForStuff.cmake` (all `REQUIRED` unless noted):

**Unconditional, all platforms** (lines 4–25):
```
 4  find_package(Git)
 7  find_package(Threads REQUIRED)
14  find_package(PNG 1.6.40 REQUIRED)
15  find_package(JPEG REQUIRED)
16  find_package(ZLIB REQUIRED)
17  find_package(Zstd 1.5.5 REQUIRED)
18  find_package(LZ4 REQUIRED)
19  find_package(WebP REQUIRED)
20  find_package(SDL3 3.2.6 REQUIRED)
21  find_package(Freetype 2.10 REQUIRED)
22  find_package(plutovg 1.1.0 REQUIRED)
23  find_package(plutosvg 0.0.7 REQUIRED)
24  find_package(ryml REQUIRED)
25  find_package(FFMPEG 7.1 COMPONENTS avcodec avformat avutil swresample swscale REQUIRED)
```

**Conditional on Vulkan** (lines 30–32):
```
31  find_package(Shaderc REQUIRED)
```

**Windows only** (lines 26–28, 35–39): `DirectX-Headers 1.618.1`, plus `3rdparty/D3D12MemAlloc`, `3rdparty/winpixeventruntime`, `3rdparty/winwil`, `find_package(Vtune)` *(optional)*.

**Non-Windows** (lines 41–43):
```
41  find_package(CURL REQUIRED)
42  find_package(PCAP REQUIRED)
43  find_package(Vtune)          # optional
```

**Linux only** (lines 48–72): `Fontconfig`, `libudev`, `X11` (+XRandR fatal if missing), `ECM`+`Wayland(Egl)`, `Libbacktrace`, `PkgConfig`, `dbus-1`.

**Qt GUI only** (lines 106–117), gated on `ENABLE_QT_UI` (default `ON` at `BuildParameters.cmake:10`):
```
107  find_package(Qt6 6.10 COMPONENTS CoreTools Core GuiTools Gui WidgetsTools Widgets LinguistTools REQUIRED)
111  find_package(Qt6 COMPONENTS CorePrivate GuiPrivate WidgetsPrivate REQUIRED)   # non-Win, non-Apple
116  find_package(KDDockWidgets-qt6 2.3.0 REQUIRED)                               # debugger docking
```

**Vendored via `add_subdirectory`** (lines 78–138): `fast_float`, `lzma`, `libchdr`, `soundtouch`, `simpleini`, `imgui`, `cpuinfo`, `libzip`, `rcheevos`, `rapidjson`, `discord-rpc`, `freesurround`, `glad` (if OpenGL), `vulkan` (if Vulkan), `cubeb`, `demangler`, `ccc`, `zydis` (x86) **or** `vixl` (arm64), `fmt`.

**Component count:** roughly **20 mandatory third-party packages** (`Threads, PNG, JPEG, ZLIB, Zstd, LZ4, WebP, SDL3, Freetype, plutovg, plutosvg, ryml, FFMPEG(×5 components), CURL, PCAP` and, when Vulkan is on, `Shaderc`, plus the bundled dirs), and **3 more for the GUI** (`Qt6 Core/Gui/Widgets/LinguistTools`, `Qt6 private modules`, `KDDockWidgets-qt6`).

### 2.4 The biggest dependency obstacle to iPadOS

**Two obstacles, in different categories — do not conflate them:**

**(a) The GUI stack — Qt6 + KDDockWidgets — is a hard, non-portable obstacle to reusing the shipped frontend.**
- `Qt6::Widgets` (desktop widget toolkit) and `KDAB::kddockwidgets` (a desktop docking-window framework) are linked only by `pcsx2-qt`:
  ```
  pcsx2-qt/CMakeLists.txt:298-305
  298  target_link_libraries(pcsx2-qt PRIVATE
  299      PCSX2_FLAGS
  300      PCSX2
  301      Qt6::Core
  302      Qt6::Gui
  303      Qt6::Widgets
  304      KDAB::kddockwidgets
  305  )
  ```
  The entire frontend is `.ui` XML + `QWidget` + `AUTOUIC`/`AUTOMOC` (188 files, 44,278 lines; e.g. `pcsx2-qt/CMakeLists.txt:3-5` sets `CMAKE_AUTOMOC/AUTORCC/AUTOUIC ON`). Qt6 for iOS ships no QtWidgets, and KDDockWidgets has no iOS port. **The shipped `pcsx2-qt` frontend cannot be compiled for iPadOS. This is a rewrite, not a port.**
- Good news: the GUI is not linked into the core (see §6). `PCSX2` itself has no Qt dependency.

**(b) The real technical obstacle is not a dependency at all — it is the missing arm64 recompilers plus the JIT/W^X requirement.** See §3, §4, §9. Even with a perfect SwiftUI frontend, PCSX2 on arm64 has no EE/VU/IOP recompilers today.

**(c) Secondary dependency obstacles for an iOS build** (each independently blocking):
- `find_package(PCAP REQUIRED)` — libpcap is unavailable on iOS; DEV9 networking assumes it (`pcsx2/DEV9/pcap_io.cpp`).
- `FFMPEG 7.1` + `Shaderc` + `MoltenVK` are loaded via `dlopen` at runtime (`common/DynamicLibrary.cpp:96`, `pcsx2/GS/Renderers/Vulkan/VKLoader.cpp:56,62`) — `dlopen` of non-system dylibs is prohibited on iOS.
- `freetype`/`plutovg`/`plutosvg`/`ryml` must be cross-compiled (no vendor iOS binaries).
- `SDL3 3.2.6` is *not* a blocker — SDL3 has a maintained iOS backend, and it's the input/audio layer used by the core (`pcsx2/Input/SDLInputSource.cpp`, `pcsx2/Host/SDLAudioStream.cpp`).

---

## 3. CPU CORE / JIT

### 3.1 Where the Emotion Engine recompilers live

**All EE/JIT code is under `pcsx2/x86/` — an x86-only directory.**

EE (R5900) recompiler, registered in `pcsx2/CMakeLists.txt:992-1018` as `pcsx2x86Sources`:

```
pcsx2/CMakeLists.txt:993-1018
 993  set(pcsx2x86Sources
 994      x86/BaseblockEx.cpp
 995      x86/iCOP0.cpp
 996      x86/iCore.cpp
 997      x86/iFPU.cpp
 998      x86/iFPUd.cpp
 999      x86/iMMI.cpp
1000      x86/iR3000A.cpp
1001      x86/iR3000Atables.cpp
1002      x86/iR5900Analysis.cpp
1003      x86/iR5900Misc.cpp
1004      x86/ix86-32/iCore.cpp
1005      x86/ix86-32/iR5900.cpp
1006-1015  x86/ix86-32/iR5900{Arit,AritImm,Branch,Jump,LoadStore,Move,MultDiv,Shift,Templates}.cpp
1015      x86/ix86-32/recVTLB.cpp
1016      x86/Vif_Dynarec.cpp
1017      x86/Vif_UnpackSSE.cpp
1018  )
```

Key entry points in the EE recompiler:
```
pcsx2/x86/ix86-32/iR5900.cpp:561  static void recReserveRAM()
pcsx2/x86/ix86-32/iR5900.cpp:625  static void recReserve()
pcsx2/x86/ix86-32/iR5900.cpp:627      recPtr = SysMemory::GetEERec();
pcsx2/x86/ix86-32/iR5900.cpp:642  static void recResetRaw()
pcsx2/x86/ix86-32/iR5900.cpp:644      Console.WriteLn(Color_StrongBlack, "EE/iR5900 Recompiler Reset");
pcsx2/x86/ix86-32/iR5900.cpp:2764     recReserve,   // in the R5900cpu vtable
pcsx2/x86/iCore.cpp               (819 lines) — the x86 emitter layer (x86emitter)
```

IOP (R3000A) recompiler: `pcsx2/x86/iR3000A.cpp` (1514 lines), `pcsx2/x86/iR3000Atables.cpp`, header `pcsx2/x86/iR3000A.h`:
```
pcsx2/x86/iR3000A.cpp:918   static void recReserveRAM()
pcsx2/x86/iR3000A.cpp:943   static void recReserve()
pcsx2/x86/iR3000A.cpp:1849      recReserve,   // R3000Acpu vtable
pcsx2/x86/iR3000A.h:25      extern uptr psxRecLUT[];
```

VU (microVU) recompiler: `pcsx2/x86/microVU.cpp` + 15 `.inl` files:
```
pcsx2/x86/microVU.cpp               (425 lines)
pcsx2/x86/microVU_Alloc.inl, microVU_Analyze.inl, microVU_Branch.inl,
microVU_Clamp.inl, microVU_Compile.inl, microVU_Execute.inl, microVU_Flags.inl,
microVU_IR.h, microVU_Log.inl, microVU_Lower.inl, microVU_Macro.inl,
microVU_Misc.h, microVU_Misc.inl, microVU_Tables.inl, microVU_Upper.inl
pcsx2/x86/newVif.h, Vif_Dynarec.cpp, Vif_UnpackSSE.cpp/.h
```

### 3.2 Host architectures supported — **x86-64 full JIT; arm64 has NO EE/VU/IOP recompiler**

Architecture selection is in `cmake/BuildParameters.cmake:80-144`:
```
 83  if("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64" OR ... STREQUAL "amd64" OR
 84     ... STREQUAL "AMD64" OR "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "x86_64")
 85      # Multi-ISA only exists on x86.
 86      option(DISABLE_ADVANCE_SIMD "Disable advance use of SIMD (SSE2+ & AVX)" OFF)
 88      list(APPEND PCSX2_DEFS _M_X86=1)
 89      set(ARCH_X86 TRUE)
...
115  elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "arm64" OR ... STREQUAL "aarch64" OR
116         "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "arm64")
117      message(STATUS "Building for Apple Silicon (ARM64).")
118      set(ARCH_ARM64 TRUE)
119      if(APPLE)
120          # Min spec is an M1
121          add_compile_options("-march=armv8.4-a" "-mcpu=apple-m1")
122      else()
123          # Require atomic rmw instructions
124          add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:-march=armv8.1-a>")
125      endif()
...
142  else()
143      message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
144  endif()
```

**And the repo says this out loud in its own root CMakeLists.txt:**
```
CMakeLists.txt:84-93
 84  if(ARCH_ARM64)
 85      message(WARNING "
 86  *************** UNSUPPORTED CONFIGURATION ***************
 87  Apple Silicon support in PCSX2 is INCOMPLETE. There are
 88  currently no EE/VU/IOP recompilers, and games will run
 89  VERY slow. There is no date for completion yet, you
 90  should set -DCMAKE_OSX_ARCHITECTURES=x86_64 for now,
 91  unless you want to work on the recompilers.
 92  *********************************************************")
 93  endif()
```

**What is actually in the arm64 directory — searched `glob **/arm64/**` and listed `pcsx2/arm64/`:**
```
pcsx2/arm64/AsmHelpers.cpp
pcsx2/arm64/AsmHelpers.h
pcsx2/arm64/RecStubs.cpp
pcsx2/arm64/Vif_Dynarec.cpp
pcsx2/arm64/Vif_UnpackNEON.cpp
pcsx2/arm64/Vif_UnpackNEON.h
```
That is the **complete** list (6 files). Registered in `pcsx2/CMakeLists.txt:1050-1060`:
```
1050  # ARM64
1051  set(pcsx2arm64Sources
1052      arm64/AsmHelpers.cpp
1053      arm64/Vif_Dynarec.cpp
1054      arm64/Vif_UnpackNEON.cpp
1055      arm64/RecStubs.cpp
1056      )
1058  set(pcsx2arm64Headers
1059      arm64/AsmHelpers.h
1060      )
```
- **NO `iR5900*` / EE recompiler for arm64.**
- **NO `iR3000A*` / IOP recompiler for arm64.**
- **NO `microVU*` / VU recompiler for arm64.**
- **NO `iCore` / x86-emitter equivalent for arm64.**

The arm64 assembler infrastructure that *does* exist is a vixl wrapper (`pcsx2/arm64/AsmHelpers.h:9-10` includes `vixl/aarch64/macro-assembler-aarch64.h`) providing register aliases (`RXRET`, `RXARG1`, `RQSCRATCH`, …), a constant pool (`ArmConstantPool`), and `armSetAsmPtr` / `armStartBlock` / `armEndBlock`. It is used *only* by the VIF-unpack dynarec and the GS software renderer.

The only arm64 JITs present:
1. **VIF unpack dynarec** — `pcsx2/arm64/Vif_Dynarec.cpp` (500 lines) + `Vif_UnpackNEON.cpp` (362 lines), enabled unconditionally by `pcsx2/Vif_Dynarec.h:46`: `static constexpr bool newVifDynaRec = 1; // Use code in Vif_Dynarec.inl`
2. **GS software renderer JIT** — `pcsx2/GS/Renderers/SW/GSDrawScanlineCodeGenerator.arm64.cpp` and `GSSetupPrimCodeGenerator.arm64.cpp`, selected at `pcsx2/CMakeLists.txt:488-493`:
```
488  elseif(ARCH_ARM64)
489      list(APPEND pcsx2GSSourcesUnshared
490          GS/Renderers/SW/GSDrawScanlineCodeGenerator.arm64.cpp
491          GS/Renderers/SW/GSSetupPrimCodeGenerator.arm64.cpp
492      )
493  endif()
```

### 3.3 Is there a pure INTERPRETER for the EE? — **Yes.**

| CPU | Interpreter file | Lines | Class / symbol |
|---|---|---|---|
| EE (R5900) | `pcsx2/Interpreter.cpp` | 688 | `intCpu` (`extern R5900cpu intCpu;` — `pcsx2/R5900.h:356`) |
| IOP (R3000A) | `pcsx2/R3000AInterpreter.cpp` | 269 | `psxInt` (`extern R3000Acpu psxInt;` — `pcsx2/R3000A.h:190`) |
| VU0 micro | `pcsx2/VU0microInterp.cpp` | 265 | `InterpVU0 CpuIntVU0` (`pcsx2/VUmicro.h:83-99`, `:161`) |
| VU1 micro | `pcsx2/VU1microInterp.cpp` | 239 | `InterpVU1 CpuIntVU1` (`pcsx2/VUmicro.h:101-110`, `:162`) |

```
pcsx2/VUmicro.h:83   class InterpVU0 final : public BaseVUmicroCPU
pcsx2/VUmicro.h:90       const char* GetLongName() const override { return "VU0 Interpreter"; }
pcsx2/VUmicro.h:101  class InterpVU1 final : public BaseVUmicroCPU
pcsx2/VUmicro.h:108      const char* GetLongName() const override { return "VU1 Interpreter"; }
pcsx2/VUmicro.h:161  extern InterpVU0 CpuIntVU0;
pcsx2/VUmicro.h:162  extern InterpVU1 CpuIntVU1;
```
Shared interpreter/dynarec code for VU0 micro lives in `pcsx2/VU0micro.cpp:4-5`: `// This module contains code shared by both the dynarec and interpreter versions / of the VU0 micro.`

**VU0 macro mode** is COP2, handled by `pcsx2/COP2.cpp`, which is `using namespace R5900::Interpreter;` (`pcsx2/COP2.cpp:10`) and drives the micro interpreter via `vu0ExecMicro(...)` (`pcsx2/COP2.cpp:18,25`). **Macro mode is interpreter-only in this arrangement on arm64** (on x86 it can be partly handled by mVU — see `VMManager.cpp:2772-2774`: *"mVU's VU0 needs to be properly initialized for macro mode even if it's not used for micro mode!"*).

### 3.4 How the backend is selected at build time and at runtime

**Build time:** two CMake booleans + one preprocessor macro.
- `ARCH_X86` / `_M_X86=1` **or** `ARCH_ARM64` — set in `cmake/BuildParameters.cmake:83-144` from `CMAKE_SYSTEM_PROCESSOR` / `CMAKE_OSX_ARCHITECTURES`.
- Source lists branch on them: `pcsx2/CMakeLists.txt:483-493` (GS SIMD), `:578-590` (GS vector headers), `:1074-1080` (recompiler sources + `zydis` vs `vixl`):
```
1074  if(ARCH_X86)
1075      list(APPEND pcsx2LTOSources ${pcsx2x86Sources} ${pcsx2x86Headers})
1076      target_link_libraries(PCSX2_FLAGS INTERFACE zydis)
1077  elseif(ARCH_ARM64)
1078      list(APPEND pcsx2LTOSources ${pcsx2arm64Sources} ${pcsx2arm64Headers})
1079      target_link_libraries(PCSX2_FLAGS INTERFACE vixl)
1080  endif()
```
- `USE_VULKAN`/`USE_OPENGL` → `ENABLE_VULKAN`/`ENABLE_OPENGL` defines (`BuildParameters.cmake:230-236`).

**Runtime:** the decisive switch is `pcsx2/VMManager.cpp:2700-2764`, entirely fenced by `#ifdef _M_X86`:
```
2700  void VMManager::InitializeCPUProviders()
2701  {
2702  #ifdef _M_X86 // TODO(Stenzek): Remove me once EE/VU/IOP recs are added.
2703      recCpu.Reserve();
2704      psxRec.Reserve();
2705
2706      CpuMicroVU0.Reserve();
2707      CpuMicroVU1.Reserve();
2708  #else
2709      // Despite not having any VU recompilers on ARM64, therefore no MTVU,
2710      // we still need the thread alive. Otherwise the read and write positions
2711      // of the ring buffer wont match, and various systems in the emulator end up deadlocked.
2712      vu1Thread.Open();
2713  #endif
2714
2715      VifUnpackSSE_Init();
2716  }
```
```
2751  #ifdef _M_X86 // TODO(Stenzek): Remove me once EE/VU/IOP recs are added.
2752      Cpu = CHECK_EEREC ? &recCpu : &intCpu;
2753      psxCpu = CHECK_IOPREC ? &psxRec : &psxInt;
2754
2755      CpuVU0 = EmuConfig.Cpu.Recompiler.EnableVU0 ? static_cast<BaseVUmicroCPU*>(&CpuMicroVU0) : static_cast<BaseVUmicroCPU*>(&CpuIntVU0);
2756      CpuVU1 = EmuConfig.Cpu.Recompiler.EnableVU1 ? static_cast<BaseVUmicroCPU*>(&CpuMicroVU1) : static_cast<BaseVUmicroCPU*>(&CpuIntVU1);
2757  #else
2758      Cpu = &intCpu;
2759      psxCpu = &psxInt;
2760
2761      CpuVU0 = &CpuIntVU0;
2762      CpuVU1 = &CpuIntVU1;
2763  #endif
2764  }
```
Runtime REC macros, `pcsx2/Config.h:1501-1511`:
```
1501  #define REC_VU1 (EmuConfig.Cpu.Recompiler.EnableVU1)
1508  #define CHECK_EEREC (EmuConfig.Cpu.Recompiler.EnableEE)
1509  #define CHECK_CACHE (EmuConfig.Cpu.Recompiler.EnableEECache)
1510  #define CHECK_IOPREC (EmuConfig.Cpu.Recompiler.EnableIOP)
1511  #define CHECK_FASTMEM (EmuConfig.Cpu.Recompiler.EnableEE && EmuConfig.Cpu.Recompiler.EnableFastmem)
```
So on arm64 the *user-facing* recompiler toggles are compiled out — the interpreter is forced.

**Cross-cutting markers of the missing work** — grep for `TODO(Stenzek): Remove me once EE/VU/IOP recs are added`:
```
pcsx2/R5900OpcodeTables.cpp:15   #ifdef _M_X86 // TODO(Stenzek): Remove me once EE/VU/IOP recs are added.
pcsx2/VMManager.cpp:2702         #ifdef _M_X86 // TODO(Stenzek): ...
pcsx2/VMManager.cpp:2726         #ifdef _M_X86 // TODO(Stenzek): ...
pcsx2/VMManager.cpp:2751         #ifdef _M_X86 // TODO(Stenzek): ...
pcsx2/VMManager.cpp:2771         #ifdef _M_X86 // TODO(Stenzek): ...
```
(5 occurrences total.)

---

## 4. DOES JIT WRITE TO EXECUTABLE MEMORY? — **Yes, and it is RWX, not W^X.**

### 4.1 The code-memory region is mapped read+write+execute

`pcsx2/Memory.cpp:88-117` reserves one contiguous `SharedMemoryMappingArea` for data **and code** and maps the code half with `PageAccess_Any()`:
```
 98  if (!(s_memory_mapping_area = SharedMemoryMappingArea::Create(HostMemoryMap::MainSize + HostMemoryMap::CodeSize, true)))
...
112  if ((s_code_memory = s_memory_mapping_area->Map(nullptr, 0, s_memory_mapping_area->OffsetPointer(HostMemoryMap::MainSize), HostMemoryMap::CodeSize, PageAccess_Any())) == nullptr)
113  {
114      Host::ReportErrorAsync("Error", "Failed to allocate code memory.");
```
`true` is the `jit` flag (`common/HostSys.h:142  static std::unique_ptr<SharedMemoryMappingArea> Create(size_t size, bool jit = false);`).

`PageAccess_Any()` is `All()` — read+write+exec — at `common/HostSys.h:47-51, 84-87`:
```
 47  __fi constexpr PageProtectionMode& All(bool allow = true)
 48  { m_read = m_write = m_exec = allow; return *this; }
...
 55  __fi constexpr bool CanExecute() const { return m_exec && m_read; }
 84  static __fi PageProtectionMode PageAccess_Any()
 85  { return PageProtectionMode().All(); }
```

`common/Linux/LnxHostSys.cpp:28-40` turns that into POSIX flags — note **`PROT_EXEC` is added alongside `PROT_WRITE`**:
```
 28  static __ri uint LinuxProt(const PageProtectionMode& mode)
 29  {
 30      u32 lnxmode = 0;
 31
 32      if (mode.CanWrite())
 33          lnxmode |= PROT_WRITE;
 34      if (mode.CanRead())
 35          lnxmode |= PROT_READ;
 36      if (mode.CanExecute())
 37          lnxmode |= PROT_EXEC | PROT_READ;
 38
 39      return lnxmode;
 40  }
```

`common/Linux/LnxHostSys.cpp:156-196` — the reservation and the `MAP_JIT` / `mprotect` dance:
```
156  std::unique_ptr<SharedMemoryMappingArea> SharedMemoryMappingArea::Create(size_t size, bool jit)
157  {
158      pxAssertRel(Common::IsAlignedPow2(size, __pagesize), "Size is page aligned");
159
160      uint flags = MAP_ANONYMOUS | MAP_PRIVATE;
161  #ifdef __APPLE__
162      if (jit)
163          flags |= MAP_JIT;
164  #endif
165      void* alloc = mmap(nullptr, size, PROT_NONE, flags, -1, 0);
166      if (alloc == MAP_FAILED)
167          return nullptr;
...
172  u8* SharedMemoryMappingArea::Map(void* file_handle, size_t file_offset, void* map_base, size_t map_size, const PageProtectionMode& mode)
...
185      else
186      {
187          // macOS doesn't seem to allow MAP_JIT with MAP_FIXED
188          // So we do the MAP_JIT in the allocation, and just mprotect here
189          // Note that this will only work the first time for a given region
190          if (mprotect(map_base, map_size, lnxmode) < 0)
191              return nullptr;
192      }
```
Because `mode` is `PageAccess_Any()`, `lnxmode` = `PROT_WRITE|PROT_READ|PROT_EXEC` → **the JIT region is permanently RWX on Apple and Linux.** There is no code anywhere that demotes it back to RX. Confirmed by absence: `grep SetExecutable|SetWritable|FinalizeCode|FlushInstructionCache` over `pcsx2/` returns only:
```
pcsx2/arm64/AsmHelpers.cpp:116        armAsm->FinalizeCode();
pcsx2/arm64/AsmHelpers.cpp:126        HostSys::FlushInstructionCache(armAsmPtr, size);
pcsx2/arm64/AsmHelpers.cpp:418        masm.FinalizeCode();
pcsx2/arm64/AsmHelpers.cpp:424        HostSys::FlushInstructionCache(...);
pcsx2/GS/Renderers/Common/GSFunctionMap.h:200  HostSys::FlushInstructionCache(code_ptr, static_cast<u32>(size));
pcsx2/GS/Renderers/SW/GSDrawScanlineCodeGenerator.arm64.cpp:106  armAsm->FinalizeCode();
pcsx2/GS/Renderers/SW/GSDrawScanlineCodeGenerator.arm64.cpp:189  armAsm->FinalizeCode();
pcsx2/GS/Renderers/SW/GSSetupPrimCodeGenerator.arm64.cpp:60       armAsm->FinalizeCode();
```
**No `vixl::CodeBuffer::SetExecutable()` / `SetWritable()` call exists in PCSX2**, even though vixl provides them (`3rdparty/vixl/src/code-buffer-vixl.cc:93,95` `SetExecutable() { mprotect(buffer_, capacity_, PROT_READ | PROT_EXEC); }` and `:105,107` `SetWritable() { mprotect(..., PROT_READ | PROT_WRITE); }`). PCSX2 never uses the write-toggle protocol.

The only W^X-adjacent primitive is cache flushing, which on arm64 is `__builtin___clear_cache`:
```
common/Linux/LnxHostSys.cpp:209-214
209  #ifdef ARCH_ARM64
211  void HostSys::FlushInstructionCache(void* address, u32 size)
212  {
213      __builtin___clear_cache(reinterpret_cast<char*>(address), reinterpret_cast<char*>(address) + size);
214  }
```

### 4.2 Windows path (for completeness)

`common/Windows/WinHostSys.cpp:150` uses `VirtualAlloc2(..., MEM_RESERVE | MEM_RESERVE_PLACEHOLDER, PAGE_NOACCESS, ...)` to reserve, then `:215` `MEM_RESERVE|MEM_COMMIT|MEM_REPLACE_PLACEHOLDER, PAGE_READWRITE` per page. The code half is later committed RWX through the same `PageAccess_Any()` mode. (`pcsx2/GS/GS.cpp:979` also calls `VirtualAlloc2` but that is the GS shared-memory/FIFO area, paired with the non-exec `mmap(... PROT_READ|PROT_WRITE ...)` at `pcsx2/GS/GS.cpp:1058,1063` — **not** a JIT region.)

### 4.3 Xbyak (x86 path) — also RWX-capable, and PCSX2 passes its own buffer

`3rdparty/xbyak/xbyak/xbyak.h:102-106` enables MAP_JIT on Apple:
```
102  #if defined(__APPLE__) && !defined(XBYAK_DONT_USE_MAP_JIT)
103      #define XBYAK_USE_MAP_JIT
105      #ifndef MAP_JIT
106          #define MAP_JIT 0x800
```
`3rdparty/xbyak/xbyak/xbyak.h:986-1018` (`MmapAllocator::alloc`) — allocates **RW** first, then relies on `protect()`:
```
 990  #if defined(MAP_ANONYMOUS)
 991      int mode = MAP_PRIVATE | MAP_ANONYMOUS;
...
 997  #if defined(XBYAK_USE_MAP_JIT)
 998      const int mojaveVersion = 18;
 999      if (util::getMacOsVersion() >= mojaveVersion) mode |= MAP_JIT;
1000  #endif
1012      int prot = PROT_READ | PROT_WRITE;
...
1018      void *p = mmap(NULL, size, prot, mode, fd, 0);
```
`3rdparty/xbyak/xbyak/xbyak.h:1848-1879` (`protect`):
```
1856      const int c_rw  = PROT_READ | PROT_WRITE;
1857      const int c_rwe = PROT_READ | PROT_WRITE | PROT_EXEC;
1858      const int c_re  = PROT_READ | PROT_EXEC;
...
1875      return mprotect(reinterpret_cast<void*>(roundAddr), size + (iaddr - roundAddr), mode) == 0;
```
**However**, PCSX2 supplies its own buffer via `GSNewCodeGenerator(void* code, size_t maxsize) : actual(maxsize, code)` (`pcsx2/GS/Renderers/SW/GSNewCodeGenerator.h:62-68`), and that buffer comes from the SW JIT reserve which is carved out of the RWX code mapping:
```
pcsx2/GS/Renderers/Common/GSFunctionMap.cpp:16-17
 16  s_memory_base = SysMemory::GetSWRec();
 17  s_memory_end  = SysMemory::GetSWRecEnd();
pcsx2/GS/Renderers/Common/GSFunctionMap.h:185,197
185  u8* code_ptr = GSCodeReserve::ReserveMemory(MAX_SIZE);
197  GSCodeReserve::CommitMemory(size);
```
and xbyak skips `setProtectMode` for caller-provided buffers:
```
3rdparty/xbyak/xbyak/xbyak.h:1720
1720  : type_(userPtr == AutoGrow ? AUTO_GROW : (userPtr == 0 || userPtr == DontSetProtectRWE) ? ALLOC_BUF : USER_BUF)
1729  if ((type_ == ALLOC_BUF && userPtr != DontSetProtectRWE && useProtect()) && !setProtectMode(PROTECT_RWE, false)) {
```
Same for the arm64/vixl SW generators: `GSDrawScanlineCodeGenerator.arm64.cpp:86-87` `GSDrawScanlineCodeGenerator(u64 key, void* code, size_t maxsize) : m_emitter(static_cast<vixl::byte*>(code), maxsize, vixl::aarch64::PositionDependentCode)` — direct emission into the RWX buffer.

### 4.4 macOS entitlements already request JIT

```
pcsx2/Resources/PCSX2.entitlements:5-10
  5      <key>com.apple.security.cs.allow-jit</key>
  6      <true/>
  7      <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  8      <true/>
  9      <key>com.apple.security.cs.disable-library-validation</key>
 10      <true/>
```
Referenced from `pcsx2/CMakeLists.txt:1415`: `XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${PCSX2_SOURCE_DIR}/Resources/PCSX2.entitlements"`.
This is the macOS Hardened Runtime model. (External knowledge, labelled: these `com.apple.security.cs.*` Hardened-Runtime entitlements are macOS-only; iOS/iPadOS does not grant them to third-party apps, and `MAP_JIT` on iOS additionally requires `pthread_jit_write_protect_np()`-style write/execute toggling under a special Apple-granted entitlement. I could not verify iOS entitlement availability from this repo — **it contains no iOS code at all**, see §7 — so that part must be validated against Apple's current documentation and the App Store review guidelines before it is quoted in a feasibility doc.)

### 4.5 Bottom line for W^X feasibility

PCSX2's design is **RWX, permanently, for all four JIT consumers** (EE/IOP/microVU on x86, VIF unpack on both, GS software renderer on both). Any iOS port must either (a) obtain a JIT entitlement **and** be rewritten to the `MAP_JIT` + `pthread_jit_write_protect_np()` toggle protocol — at minimum touching `common/Linux/LnxHostSys.cpp:156-196`, `pcsx2/Memory.cpp:112`, and every emitter finalization site — or (b) eliminate the JITs entirely.

---

## 5. GRAPHICS BACKENDS

### 5.1 Renderer directory inventory

`pcsx2/GS/Renderers/` contains exactly 9 subdirectories:

| Dir | Backend | Platform gate |
|---|---|---|
| `NULL` (`Null/`) | Null renderer (`GSRendererNull`) | always |
| `SW/` | **Software renderer** (`GSRendererSW`, `GSDrawScanline`, `GSRasterizer`, `GSTextureCacheSW`) | always |
| `HW/` | Shared hardware-renderer layer (`GSRendererHW`, `GSTextureCache`, `GSHwHack`, texture replacements) | always |
| `Common/` | `GSDevice`, `GSRenderer`, `GSTexture`, `GSVertex`, `GSFunctionMap`, `GSDirtyRect`, `GSFastList` | always |
| `OpenGL/` | OpenGL (`GSDeviceOGL`, `GSTextureOGL`, `GLContext*`, `GLShaderCache`, `GLState`, `GLStreamBuffer`) | **`if(NOT APPLE) option(USE_OPENGL ...)`** — `BuildParameters.cmake:22-24`; sources at `pcsx2/CMakeLists.txt:592-637` |
| `Vulkan/` | **Vulkan** (`GSDeviceVK`, `GSTextureVK`, `VKBuilders`, `VKLoader`, `VKShaderCache`, `VKStreamBuffer`, `VKSwapChain`, `vk_mem_alloc`) | `option(USE_VULKAN ...)` default ON; sources at `pcsx2/CMakeLists.txt:639-663` |
| `Metal/` | **Metal** | `if(APPLE)` — `pcsx2/CMakeLists.txt:877-891` |
| `DX11/` | Direct3D 11 | `if(WIN32)` — `pcsx2/CMakeLists.txt:693-704` |
| `DX12/` | Direct3D 12 | `if(WIN32)` — `pcsx2/CMakeLists.txt:698-704` |

### 5.2 Is there ANY Metal backend? — **YES, and it is a first-class, complete renderer.**

`pcsx2/GS/Renderers/Metal/` file listing:
```
cas.metal            fxaa.metal           GSMTLShaderCommon.h
convert.metal        GSDeviceMTL.h        GSMTLSharedHeader.h
interlace.metal      GSDeviceMTL.mm       GSTextureMTL.h
merge.metal          GSCMetalCPPAccessible.h  GSTextureMTL.mm
misc.metal           GSMTLDeviceInfo.h    present.metal
tfx.metal            GSMTLDeviceInfo.mm
```
That is **8 `.metal` shader source files** and **3 Objective-C++ implementation files** (`GSDeviceMTL.mm` is 2822 lines).

Registered at `pcsx2/CMakeLists.txt:877-891`:
```
877  if(APPLE)
878      list(APPEND pcsx2GSSources
879          GS/Renderers/Metal/GSDeviceMTL.mm
880          GS/Renderers/Metal/GSMTLDeviceInfo.mm
881          GS/Renderers/Metal/GSTextureMTL.mm
882      )
883      list(APPEND pcsx2GSHeaders
884          GS/Renderers/Metal/GSDeviceMTL.h
885          GS/Renderers/Metal/GSMetalCPPAccessible.h
886          GS/Renderers/Metal/GSMTLDeviceInfo.h
887          GS/Renderers/Metal/GSMTLSharedHeader.h
888          GS/Renderers/Metal/GSMTLShaderCommon.h
889          GS/Renderers/Metal/GSTextureMTL.h
890      )
891  endif()
```
Shader list and compilation, `pcsx2/CMakeLists.txt:665-674` and `:1383-1409`:
```
665  set(pcsx2GSMetalShaders
666      GS/Renderers/Metal/cas.metal
667      GS/Renderers/Metal/convert.metal
668      GS/Renderers/Metal/present.metal
669      GS/Renderers/Metal/merge.metal
670      GS/Renderers/Metal/misc.metal
671      GS/Renderers/Metal/interlace.metal
672      GS/Renderers/Metal/tfx.metal
673      GS/Renderers/Metal/fxaa.metal
674  )
...
1396      COMMAND xcrun metal ${flags} -std=${std} -target ${triple} -o ${shaderOut} -c ${PCSX2_SOURCE_DIR}/${shader}
1402      COMMAND xcrun metallib -o ${metallib} ${pcsx2GSMetalShaderOut}
...
1407      generateMetallib(macos-metal2.0 air64-apple-macos10.13 default)
1408      generateMetallib(macos-metal2.2 air64-apple-macos10.15 Metal22)
1409      generateMetallib(macos-metal2.3 air64-apple-macos11.0  Metal23)
```
`RenderAPI::Metal` is a first-class enum member (`pcsx2/GS/GS.h:16-24`) and a first-class `GSRendererType` at value `17` (`pcsx2/Config.h:271-281`: `Metal = 17`), with a display name `"Metal"` (`pcsx2/Pcsx2Config.cpp:694`).

### 5.3 What Apple platforms actually use today

**Metal is the default renderer on macOS.** `pcsx2/GS/GSUtil.cpp:276-284`:
```
276  GSRendererType GSUtil::GetPreferredRenderer()
277  {
278      // Memorize the value, so we don't keep re-querying it.
279      static GSRendererType preferred_renderer = GSRendererType::Auto;
280      if (preferred_renderer == GSRendererType::Auto)
281      {
282  #if defined(__APPLE__)
283          // Mac: Prefer Metal hardware.
284          preferred_renderer = GSRendererType::Metal;
```
Device factory, `pcsx2/GS/GS.cpp:97-100` and `:122-126`:
```
 97  #ifdef __APPLE__
 98      case GSRendererType::Metal:
 99          return RenderAPI::Metal;
100  #endif
...
122  #ifdef __APPLE__
123      case RenderAPI::Metal:
124          g_gs_device = std::unique_ptr<GSDevice>(MakeGSDeviceMTL());
125          break;
126  #endif
```

**Vulkan on Apple runs through MoltenVK, loaded with `dlopen` at runtime:**
```
pcsx2/GS/Renderers/Vulkan/VKLoader.cpp:50-63
 50  #ifdef __APPLE__
 ...
 56      !s_vulkan_library.Open(DynamicLibrary::GetVersionedFilename("MoltenVK").c_str(), error))
 ...
 62  if (!s_vulkan_library.Open(DynamicLibrary::GetVersionedFilename("vulkan", 1).c_str(), error) &&
 63      !s_vulkan_library.Open(DynamicLibrary::GetVersionedFilename("vulkan").c_str(), error))
```
and it is copied into the `.app` bundle:
```
pcsx2/CMakeLists.txt:1427-1439
1427  # Copy MoltenVK into the bundle
1428  unset(MOLTENVK_PATH CACHE)
1429  find_file(MOLTENVK_PATH NAMES libMoltenVK.dylib lib/libMoltenVK.dylib)
1433  if (MOLTENVK_PATH)
1434      target_sources(${target} PRIVATE "${MOLTENVK_PATH}")
1435      set_source_files_properties("${MOLTENVK_PATH}" PROPERTIES MACOSX_PACKAGE_LOCATION Frameworks)
1436      message(STATUS "Using MoltenVK from ${MOLTENVK_PATH}")
1437  else()
1438      message(WARNING "MoltenVK not found in path, it will depend on the target system having it.")
```
Also relevant: `common/CocoaTools.mm:45` — `// Store the layer pointer, that way MoltenVK doesn't call [NSView layer] outside the main thread.`
And `pcsx2/GS/Renderers/Vulkan/VKSwapChain.cpp:134  #if defined(__APPLE__)`.

**OpenGL is not built on Apple** (`BuildParameters.cmake:22-24`). Windows-only D3D11/D3D12 (`pcsx2/CMakeLists.txt:693-716`). On Windows-on-ARM the default is DX12 (`GSUtil.cpp:285-287`).

**Port implication (positive):** an iPadOS port has a real, modern GPU backend available — Metal — that is already written and already the macOS default, and the software renderer's arm64 code generator also already exists. The graphics side is **not** the blocker.

---

## 6. ARCHITECTURE / FRONTEND SEPARATION

### 6.1 There IS a linkable core library target

| CMake target | Type | Defined at | Purpose |
|---|---|---|---|
| `PCSX2_FLAGS` | `INTERFACE` library | `pcsx2/CMakeLists.txt:2` | compile defs/options/include dirs and the **entire dependency link set** |
| `PCSX2` | `add_library` (STATIC/SHARED; `OBJECT` if `DISABLE_ADVANCE_SIMD OR LTO_PCSX2_CORE`) | `pcsx2/CMakeLists.txt:4-10` | **the emulation core — all of EE/IOP/VU/GS/SPU2/CDVD/DEV9/USB/patches/savestates/VMManager** |
| `common` | `add_library` | `common/CMakeLists.txt:8` | host utilities (filesystem, threads, string, console, crash handler, HTTP, image, YAML) |
| `pcsx2-qt` | `add_executable` | `pcsx2-qt/CMakeLists.txt:7` | Qt6 Widgets GUI |
| `pcsx2-gsrunner` | `add_executable` | `pcsx2-gsrunner/CMakeLists.txt:1` | second, non-Qt frontend |
| `updater` | `add_executable` | `updater/CMakeLists.txt` | Windows-only |

```
pcsx2/CMakeLists.txt:2-10
  2  add_library(PCSX2_FLAGS INTERFACE)
  4  if(DISABLE_ADVANCE_SIMD OR LTO_PCSX2_CORE)
  6      add_library(PCSX2 OBJECT)
  7  else()
  8      add_library(PCSX2)
  9  endif()
 10  target_link_libraries(PCSX2 PRIVATE PCSX2_FLAGS)
```
The core links everything it needs by itself (`pcsx2/CMakeLists.txt:1148-1173`): `common imgui fmt::fmt libchdr libzip::zip cpuinfo cubeb rcheevos discord-rpc simpleini freesurround Freetype::Freetype SDL3::SDL3 ZLIB::ZLIB LZ4::LZ4 SoundTouch::SoundTouch PNG::PNG LZMA::LZMA Zstd::Zstd demanglegnu ccc plutovg::plutovg plutosvg::plutosvg`.
**No Qt appears in that list.** `PCSX2` is Qt-free. Note it *does* pull in `imgui` — the core owns the ImGui-based `FullscreenUI` (`pcsx2/ImGui/FullscreenUI.cpp`, `ImGuiManager.cpp`) which is the Big-Picture UI; that is a self-contained ImGui renderer that a new frontend would likely want to replace or bypass.

### 6.2 The frontend boundary is an explicit abstract `Host::` interface

`pcsx2/Host.h` (201 lines) is the entire contract: ~90 free functions in `namespace Host` covering translation, OSD, error reporting, settings get/set, CPU/GS thread dispatch, file selectors, clipboard, fullscreen, input device notifications, progress callbacks, lifecycle callbacks (`OnVMStarted`, `OnGameChanged`, `OnSaveStateSaved`, `OnAchievementsRefreshed`, …).

Implementations are split:
- **Core-provided** (`pcsx2/Host.cpp`, 398 lines): translation cache, layered settings, `GetBase*SettingValue` family, `SetBase*SettingValue`, `CommitBaseSettingChanges`, settings locks.
- **Frontend-provided**: `pcsx2-qt/QtHost.cpp` defines 55 `Host::` symbols — e.g.
```
pcsx2-qt/QtHost.cpp:1243   void Host::RunOnCPUThread(std::function<void()> function, bool block)
pcsx2-qt/QtHost.cpp:1256   void Host::RunOnGSThread(std::function<void()> function)
pcsx2-qt/QtHost.cpp:1436   void Host::SetDefaultUISettings(SettingsInterface& si)
pcsx2-qt/QtHost.cpp:1499   bool Host::InBatchMode()
pcsx2-qt/QtHost.cpp:1504   bool Host::InNoGUIMode()
pcsx2-qt/QtHost.cpp:1686   void Host::ReportInfoAsync(...)
pcsx2-qt/QtHost.cpp:1698   void Host::ReportErrorAsync(...)
pcsx2-qt/QtHost.cpp:1710   void Host::OpenURL(...)
pcsx2-qt/QtHost.cpp:1792   void Host::SetMouseMode(bool relative_mode, bool hide_cursor)
pcsx2-qt/QtHost.cpp:2049   std::unique_ptr<ProgressCallback> Host::CreateHostProgressCallback()
```

### 6.3 A second frontend already exists, proving the separation works

`pcsx2-gsrunner/Main.cpp` (1229 lines) is a **complete non-Qt frontend** built only against the core:
```
pcsx2-gsrunner/CMakeLists.txt:18-21
 18  target_link_libraries(pcsx2-gsrunner PRIVATE
 19      PCSX2_FLAGS
 20      PCSX2
 21  )
```
It includes only core headers (`pcsx2/VMManager.h`, `pcsx2/Host.h`, `pcsx2/GS.h`, `pcsx2/MTGS.h`, `pcsx2/GSDumpReplayer.h`, `pcsx2/Input/InputManager.h`, `pcsx2/SIO/Pad/Pad.h`, `pcsx2/Achievements.h`, …) — `pcsx2-gsrunner/Main.cpp:29-49` — and implements its own `Host::` callbacks.

It also supports running **without a window**, which is the closest thing to a headless mode:
```
pcsx2-gsrunner/Main.cpp:80    static std::optional<bool> s_use_window;
pcsx2-gsrunner/Main.cpp:715-726
715      else if (CHECK_ARG("-window"))
716      {
717          Console.WriteLn("Creating window");
718          s_use_window = true;
719          continue;
720      }
721      else if (CHECK_ARG("-surfaceless"))
722      {
723          Console.WriteLn("Running surfaceless");
724          s_use_window = false;
725          continue;
726      }
pcsx2-gsrunner/Main.cpp:887   if (s_use_window.value_or(true) && !GSRunner::CreatePlatformWindow())
```
`Host::InNoGUIMode()`/`InBatchMode()` exist in the interface (`pcsx2/Host.h:66-70`) and are implemented in QtHost (`:1499-1504`).

### 6.4 Is there an existing libretro core?

**No.** Searched `grep "libretro\.h|retro_run|RETRO_API|retro_init" --include=*.cpp` across the whole repo → **no matches**.
Searched `grep "libretro"` across the whole repo → matches are **exclusively inside `3rdparty/rcheevos/`** (vendored RetroAchievements library, which ships a generic libretro memory/glue layer: `3rdparty/rcheevos/src/rc_libretro.c`, `rc_libretro.h`) plus a passing mention in `3rdparty/rainterface/RA_Interface.h:100`. **There is no PCSX2 libretro core in this repository.**

### 6.5 Verdict for a SwiftUI frontend

**A custom SwiftUI frontend is viable at the architecture level** — the core is a Qt-free CMake library and the `Host::` boundary is a plain C++ free-function interface that has already been implemented twice (`QtHost.cpp`, `gsrunner/Main.cpp`). The work is: add an iOS CMake target, implement ~55 `Host::` functions, and provide a rendering surface. **The cost is not in the frontend boundary — it is in (i) the missing arm64 recompilers and (ii) the JIT/W^X situation.**

Caveats worth flagging:
- The core also contains `pcsx2/ImGui/FullscreenUI*` and `pcsx2/ImGui/ImGuiManager`, an entire Big-Picture UI compiled *into* the core. A SwiftUI frontend would either host it (ImGui has a Metal backend and an iOS example — `3rdparty/imgui/CHANGELOG.txt:6587` references `example_apple_metal`) or work around it.
- `pcsx2-qt/DisplayWidget.cpp/.h` is the Qt-specific render-window glue; it would be replaced wholesale.
- `Host::RunOnCPUThread` / `RunOnGSThread` and the `vu1Thread`/MTGS threading model must be mapped onto the iOS main-thread + `CAMetalLayer` rules.

---

## 7. APPLE PLATFORM CODE

### 7.1 What already exists for macOS

`grep __APPLE__` over `pcsx2/` → **55 matches**. Notable:

| Path | What it does |
|---|---|
| `common/CocoaTools.mm` (270 lines) | `CocoaTools::CreateMetalLayer` (`:25-48`, builds a `CAMetalLayer`, `[view setWantsLayer:YES]`, `[view setLayer:layer]`), `DestroyMetalLayer` (`:50-65`), `GetViewRefreshRate` (`:67-86`, `CGDisplayCopyDisplayMode`), `GetBundlePath` (`:106-115`), `GetNonTranslocatedBundlePath` (`:117-141`, `dlopen`s Security.framework), `MoveToTrash` (`:143-150`), `DelayedLaunch` (`:152-164`, spawns `/bin/sh` via `NSTask`), `ShowInFinder` (`:168-172`), `GetResourcePath` (`:174-185`), plus a full AppKit window/event-loop implementation `CreateWindow`/`DestroyWindow`/`GetWindowInfoFromWindow`/`RunCocoaEventLoop`/`StopMainThreadEventLoop` (`:189-270`) |
| `common/Darwin/DarwinMisc.cpp`, `DarwinMisc.h` | Darwin runtime bits (page size, cache line, page-fault handler) |
| `common/Darwin/DarwinThreads.cpp` | Darwin thread naming/priority |
| `common/CocoaTools.h` | the interface |
| `pcsx2/CDVD/Darwin/DriveUtility.cpp`, `IOCtlSrc.cpp` | macOS optical-drive IOKit access; `pcsx2/CMakeLists.txt:915-918` `set(pcsx2OSXSources CDVD/Darwin/DriveUtility.cpp CDVD/Darwin/IOCtlSrc.cpp)` |
| `pcsx2/USB/usb-eyetoy/cam-macos.mm` | AVFoundation webcam capture; `pcsx2/CMakeLists.txt:724-730` |
| `pcsx2/Input/SDLInputSource.cpp:595,602,667,732` | `#ifdef __APPLE__` joystick/rumble specifics |
| `pcsx2/GS/GSUtil.cpp:282-284` | prefer Metal |
| `pcsx2/GS/GS.cpp:30,97,122,660` | Metal render API + device creation + adapter enumeration |
| `pcsx2/GS/Renderers/Vulkan/VKLoader.cpp:50` , `VKLoader.h:25`, `VKSwapChain.cpp:134` | MoltenVK path |
| `pcsx2/GS/Renderers/HW/GSTextureCache.cpp:23` | Apple texture-cache quirk |
| `pcsx2/GS/GSVector4i_arm64.h:29,106` | `#if !defined(__APPLE__) && !defined(_MSC_VER)` — Apple's arm64 headers lack some intrinsics |
| `pcsx2/PINE.cpp:298,405` | Apple socket option quirks for the PINE debugger protocol |
| `pcsx2/Pcsx2Config.cpp:2161,2176,2262` | Apple default settings/renderer names |
| `pcsx2/VMManager.cpp:79-81,3661` | `#include "common/Darwin/DarwinMisc.h"` |
| `pcsx2/Resources/Info.plist.in`, `PCSX2.entitlements`, `PCSX2.icns` | bundle metadata / Hardened-Runtime entitlements / icon |

Apple link set, `pcsx2/CMakeLists.txt:1251-1266`:
```
1252      find_library(APPKIT_LIBRARY AppKit)
1253      find_library(IOKIT_LIBRARY IOKit)
1254      find_library(METAL_LIBRARY Metal)
1255      find_library(QUARTZCORE_LIBRARY QuartzCore)
1256      find_library(AVFOUNDATION_LIBRARY AVFoundation)
1257      find_library(COREMEDIA_LIBRARY CoreMedia)
```
macOS bundle / deployment target / signing:
```
BuildParameters.cmake:323          set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0)
BuildParameters.cmake:329          set(CMAKE_SHARED_MODULE_SUFFIX ".dylib")
BuildParameters.cmake:345          add_link_options(-Wl,-dead_strip,-dead_strip_dylibs)
pcsx2/CMakeLists.txt:1412-1419    MACOSX_BUNDLE true / MACOSX_BUNDLE_INFO_PLIST ... / XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS ...
pcsx2/CMakeLists.txt:1449-1451    add_custom_target(pcsx2-postprocess-bundle ... Qt6::macdeployqt "$<TARGET_FILE_DIR:${target}>/../.." -no-strip)
```
CI already builds a native arm64 macOS artifact:
```
.github/workflows/macos_build_matrix.yml:21-29
 21  build_macos_qt_arm:
 22      name: "arm64"
 ...
 28        arch: arm64
```

### 7.2 Is there any iOS/iPadOS code at all? — **NO.**

Exact searches and results:

| Query (tool, scope) | Result |
|---|---|
| `grep "TARGET_OS_IPHONE\|UIKit\|iOS\|iPhone"` in `pcsx2-qt/` | **no matches found** |
| `grep "TARGET_OS_IPHONE\|UIKit\|UIKit\.h"` in `pcsx2/` | **no matches found** |
| `grep "TARGET_OS_IPHONE\|iOS\|iPhone\|iPad\|UIKIT\|UIKit"` repo-wide | matches are **only** in: `3rdparty/cpuinfo/**` (its own iOS support tables), `3rdparty/cubeb/src/cubeb_audiounit.cpp` (`TARGET_OS_IPHONE` branches), `3rdparty/googletest/**`, `3rdparty/imgui/**`, `3rdparty/vulkan/include/vk_mem_alloc.h`, `3rdparty/soundtouch/readme.md`, and **`pcsx2/GS/Renderers/Metal/*`**, where the only hits are `@available(macOS X, iOS Y, *)` availability annotations that are Apple-idiomatic boilerplate, e.g. `GSMTLDeviceInfo.mm:25` `if (@available(macOS 11.0, iOS 14.0, *))` and `GSDeviceMTL.mm:380` `if (@available(macOS 10.15, iOS 10.3, *))`. `GSMTLDeviceInfo.h:21-24` documents MTL feature-set tiers by OS name (`Metal20 ///< Metal 2.0 (macOS 10.13, iOS 11)`, etc.). |

**Conclusion: there is no iOS target, no UIKit code, no iOS deployment target, no iOS CI job, and no iOS-specific branch anywhere in PCSX2's own source.** The `iOS x.y` tokens in the Metal renderer are documentation/availability syntax, not platform support.

### 7.3 Hard blockers specific to iOS (with code evidence)

1. **JIT / W^X.** `pcsx2/Memory.cpp:112` + `common/Linux/LnxHostSys.cpp:160-192` require `MAP_JIT` and permanently map the code region RWX; `pcsx2/Resources/PCSX2.entitlements:5-10` requests `com.apple.security.cs.allow-jit` and `allow-unsigned-executable-memory` (macOS Hardened Runtime keys). *(External knowledge, labelled: iOS does not expose these keys to ordinary third-party apps and requires Apple-granted JIT entitlements. Not verifiable from this repo.)*

2. **AppKit is used directly and is unavailable on iOS.** `common/CocoaTools.mm` links `AppKit`: `:15 #include <Cocoa/Cocoa.h>`, and uses `NSView` (`:41`), `NSWindow` (`:205`), `NSScreen` (`:198`), `NSApplication` (`:193`), `NSSound` (`:100`), `NSWorkspace` (`:170`), `NSEvent` (`:248`). `pcsx2/GS/Renderers/Metal/GSDeviceMTL.h:20 #include <AppKit/AppKit.h>` and `GSTextureMTL.h` likewise. **The entire Metal renderer's *presentation* path is AppKit-based** (the *rendering* is Metal and portable; the layer/window plumbing is not).

3. **`dlopen` of bundled, non-system dylibs.** `common/DynamicLibrary.cpp:96 m_handle = dlopen(filename, RTLD_NOW);` (and `:109` for a `Frameworks` path). Callers: `pcsx2/GS/Renderers/Vulkan/VKLoader.cpp:56,62` (MoltenVK, libvulkan), `pcsx2/GS/Renderers/Vulkan/VKShaderCache.cpp:126-146` (shaderc_shared), `pcsx2/GS/GSCapture.cpp:240-255` (avcodec/avformat/avutil/swscale/swresample), `pcsx2/GS/Renderers/OpenGL/GLContextEGL.cpp:17-35` (libEGL), `common/CocoaTools.mm:125` (`/System/Library/Frameworks/Security.framework/Security` — this *is* a system framework and is fine). **iOS forbids loading non-system dynamic libraries.** *(External policy knowledge, labelled.)*

4. **Process spawn / `fork`-style behaviour.** `common/CocoaTools.mm:152-164` `CocoaTools::DelayedLaunch` constructs an `NSTask` running `/bin/sh -c 'while /bin/ps -p $WAITPID …; do /bin/sleep 0.1; done; exec /usr/bin/open "$LAUNCHAPP"'`. Also `3rdparty/imgui/src/imgui.cpp:16327 pid_t pid = fork();` (macOS-only code path in ImGui's shell-open helper). Also `common/Linux/LnxMisc.cpp:341,348,358` `posix_spawnp` for `gst-play`/`gst-launch` media playback. **All of this is unavailable or meaningless on iOS.**

5. **Filesystem assumptions.** `CocoaTools::GetBundlePath` / `GetNonTranslocatedBundlePath` / `GetResourcePath` (`:106-141, :174-185`) assume a writable-adjacent `.app` bundle and translocated paths. `common/FileSystem.cpp` uses `CreateFileMappingW` / `mmap(MAP_SHARED)` (`:1274, :1288`) and `common/Linux/LnxHostSys.cpp:64-84` uses `shm_open` + `shm_unlink` for the main-memory shared mapping — **`shm_open` is not available on iOS**. Also `pcsx2/Memory.cpp:90` requires a named shared-memory object for guest RAM, and `VMManager::PerformEarlyHardwareChecks` fatally aborts on a host page-size mismatch (`pcsx2/VMManager.cpp:241-248`).

6. **Missing EE/VU/IOP recompilers on arm64** — see §3, §9. This is platform-independent but affects every Apple arm64 target including iPadOS.
7. **Qt6 + KDDockWidgets** — see §2.4(a).

---

## 8. ROUGH SIZE METRICS

Counted with `pwsh` over extensions `*.c *.cc *.cpp *.cxx *.h *.hpp *.inl *.mm *.m *.metal`, `Measure-Object -Line`:

| Tree | Files | Lines |
|---|---|---|
| `pcsx2/` (emulation core) | 713 | **297,927** |
| `3rdparty/` (C/C++ only) | 902 | **617,024** |
| `pcsx2-qt/` (Qt6 GUI) | 188 | **44,278** |
| `common/` (host utils library) | 128 | **25,240** |
| `tests/` | 12 | 2,608 |
| `pcsx2-gsrunner/` | 1 | 1,043 |

Byte sizes: `3rdparty/` = 1,079 files / **40.9 MB**; `pcsx2/`+`common/`+`pcsx2-qt/` = 1,466 files / **71.4 MB**.

**So the vendored third-party tree is ~2× the line count of the entire PCSX2 core** (617k vs. 298k lines), and the Qt GUI is ~15% of the core. The core is the smaller, more tractable half — but it is the half that needs the new recompilers.

### Top-level source directories

| Directory | One-line purpose |
|---|---|
| `3rdparty/` | 27 vendored third-party dependencies (see §1.3) + MSVC props |
| `bin/` | Runtime resources shipped with the binary: `docs/`, `resources/` (icons, fonts, shaders, translations), `utils/` |
| `cmake/` | CMake helper modules, find-modules, and the two central files `BuildParameters.cmake` + `SearchForStuff.cmake` |
| `common/` | Host-abstraction utility library (`common` target): filesystem, threads, strings, console, crash handler, HTTP, image, YAML, x86 emitter, Darwin/Linux/Windows shims |
| `pcsx2/` | **The emulation core** (`PCSX2` target): EE/IOP/VU interpreters+recompilers, GS, SPU2, CDVD, DEV9, USB, SIO/pads, IPU, MDEC, memory/TLB, patches, savestates, achievements, PINE, ImGui fullscreen UI, debugger back-end, and the `Host::` interface |
| `pcsx2-gsrunner/` | Second frontend: a Qt-free command-line runner for GS dumps/benchmarks with a `-surfaceless` mode |
| `pcsx2-qt/` | Qt6 Widgets desktop GUI frontend (main window, settings dialogs, debugger views, game list) |
| `tests/` | CTest unit/integration tests (`tests/ctest/`) + `run_test.pl` |
| `tools/` | Developer Python/shell scripts (translation-string generation, shader-to-C++, redump YAML, texture dump alpha scaler) |
| `updater/` | Windows-only self-updater |
| `.github/` | CI: per-OS build matrices (`linux_build_*`, `macos_build_*`, `windows_build_*`), lints, release workflows |

---

## 9. ARM64 BLOCKERS

### 9.1 Concrete code-level blockers to compiling EE/VU recompilers on arm64

**These are not "compile errors" — the code is deliberately excluded and replaced with stubs. The porting work is writing ~8,000 lines of new aarch64 backend.**

1. **The entire `pcsx2/x86/` backend is x86-only and has no arm64 counterpart.**
   - `pcsx2/CMakeLists.txt:1074-1080` selects `pcsx2x86Sources` (23 `.cpp` files) on `ARCH_X86` and only 4 files (`pcsx2arm64Sources`) on `ARCH_ARM64`.
   - The missing arm64 equivalents are, concretely: EE recompiler (`x86/ix86-32/iR5900*.cpp` — 11 files, `iR5900.cpp` alone is 2,366 lines), IOP recompiler (`x86/iR3000A.cpp` 1,514 lines + tables), microVU (16 `.inl`/`.h` files under `x86/`), and the shared x86 emitter layer (`x86/iCore.cpp`, `common/emitter/*`). Searched `grep "ARCH_ARM64|aarch64|arm64"` in `common/emitter/` → **no matches found**; the x86emitter is x86-only by construction.

2. **The x86 emitter is a hard dependency of the whole recompiler design.** `pcsx2/GS/Renderers/SW/GSNewCodeGenerator.h:9-18` even notes `// Xbyak pulls in windows.h, and breaks everything.` and then includes `xbyak/xbyak.h` — the same pattern applies to the EE/VU backends. An arm64 port must be re-expressed on vixl. `common/emitter/x86emitter.h` + `common/emitter/implement/*.h` + `common/emitter/instructions.h` are the x86-specific register/instruction DSL with no arm64 analogue.

3. **Fastmem / load-store backpatching is a stub that hard-fails.**
   ```
   pcsx2/arm64/RecStubs.cpp:11-14
    11  void vtlb_DynBackpatchLoadStore(uptr code_address, u32 code_size, u32 guest_pc, u32 guest_addr, u32 gpr_bitmask, u32 fpr_bitmask, u8 address_register, u8 data_register, u8 size_in_bits, bool is_signed, bool is_load, bool is_fpr)
    12  {
    13    pxFailRel("Not implemented.");
    14  }
   ```
   Any arm64 JIT would need this implemented (it rewrites a faulting load/store into a slow-path call). On arm64 this also requires a signal/`ucontext` handler capable of decoding and patching AArch64 instructions — `common/Linux/LnxHostSys.cpp:18-20` even excludes `<ucontext.h>` on Apple:
   ```
    18  #ifndef __APPLE__
    19  #include <ucontext.h>
    20  #endif
   ```
   and the Darwin page-fault handler is implemented separately in `common/Darwin/DarwinMisc.cpp` (`LnxHostSys.cpp:218` comment: `#ifndef __APPLE__ // These are done in DarwinMisc`).

4. **JIT state serialization is stubbed**, breaking save states for VU recompiled code:
   ```
   pcsx2/arm64/RecStubs.cpp:16-30
    16  bool SaveStateBase::vuJITFreeze()
    17  {
    18      if(IsSaving())
    19          vu1Thread.WaitVU();
    20
    21      Console.Warning("recompiler state is stubbed in arm64!");
    22
    23      // HACK!!
    24
    25      // size of microRegInfo structure
    26      std::array<u8,96> empty_data{};
    27      Freeze(empty_data);
    28      Freeze(empty_data);
    29      return true;
    30  }
   ```

5. **No MTVU (multi-threaded VU1) on arm64.** `pcsx2/VMManager.cpp:2709-2712`: *"Despite not having any VU recompilers on ARM64, therefore no MTVU, we still need the thread alive. Otherwise the read and write positions of the ring buffer wont match, and various systems in the emulator end up deadlocked."* → the `vu1Thread` is spun up and left idle as a synchronization dummy. Also `pcsx2/VMManager.cpp:2732-2737` on shutdown.

6. **`microVU` symbols are declared but never defined on arm64.** `pcsx2/VUmicro.h:164-165` unconditionally declares `extern recMicroVU0 CpuMicroVU0; extern recMicroVU1 CpuMicroVU1;` while the definitions live only in `pcsx2/x86/microVU.cpp` (compiled only under `ARCH_X86`). This links today only because every use site is inside `#ifdef _M_X86` (`VMManager.cpp:2706-2707, 2727-2728, 2755-2756, 2774`). Any arm64 recompiler work must also unwind all five `TODO(Stenzek)` guards (listed in §3.4).

7. **Five explicit `TODO(Stenzek): Remove me once EE/VU/IOP recs are added` markers** are the canonical to-do list for this work:
   `pcsx2/R5900OpcodeTables.cpp:15`, `pcsx2/VMManager.cpp:2702, 2726, 2751, 2771`.

8. **Minor but real arm64 codegen gaps already hit and worked around:** `pcsx2/GS/GSVector4i_arm64.h:29,106` `#if !defined(__APPLE__) && !defined(_MSC_VER)` (Apple's arm64 intrinsics headers lack something the generic path uses); `pcsx2/IPU/yuv2rgb.cpp:142` `#include <arm64_neon.h>` (MSVC-only header name — a separate arm64 portability wart); `pcsx2/IPU/IPU_MultiISA.cpp:1377,1392` and `IPU/yuv2rgb.cpp:45,139` already have `ARCH_X86`/`ARCH_ARM64` dual paths.

### 9.2 Can PCSX2 run at all without a JIT? — **YES, but "VERY slow" by the project's own words.**

**Hard evidence that it runs interpreter-only on arm64:**
- `pcsx2/VMManager.cpp:2757-2763` unconditionally assigns `Cpu = &intCpu; psxCpu = &psxInt; CpuVU0 = &CpuIntVU0; CpuVU1 = &CpuIntVU1;` when `_M_X86` is undefined.
- The project's own build warning (`CMakeLists.txt:87-89`): *"Apple Silicon support in PCSX2 is INCOMPLETE. There are currently no EE/VU/IOP recompilers, and games will run VERY slow."*
- CI already produces a working arm64 macOS binary (`.github/workflows/macos_build_matrix.yml:21-29`), so the interpreter path is a maintained, shipping configuration — not theoretical.

**What still works without a JIT (positive):**
- EE, IOP, VU0-micro, VU1-micro all have complete interpreters (§3.3).
- **The VIF unpack dynarec works on arm64** (`pcsx2/arm64/Vif_Dynarec.cpp`, enabled via `Vif_Dynarec.h:46`).
- **The GS software renderer JIT works on arm64** (`GSDrawScanlineCodeGenerator.arm64.cpp`, `GSSetupPrimCodeGenerator.arm64.cpp`).
- **The Metal renderer is complete and is the macOS default** (§5), and **Vulkan-through-MoltenVK also exists**.
- ImGui + the full `Host::`/`VMManager` lifecycle, savestates, achievements, CDVD, SPU2, pads all build.

**What degrades without a JIT (all evidenced, plus labelled inference):**
- No EE recompiler → every R5900 instruction takes the interpreter path (`pcsx2/Interpreter.cpp`).
- No IOP recompiler → `pcsx2/R3000AInterpreter.cpp` for all IOP/PS1-side code.
- No VU recompiler → interpreter for VU0/VU1 micro *and* COP2 macro mode (`pcsx2/COP2.cpp`).
- **Fastmem is disabled**, because `CHECK_FASTMEM` requires the recompiler: `pcsx2/Config.h:1511 #define CHECK_FASTMEM (EmuConfig.Cpu.Recompiler.EnableEE && EmuConfig.Cpu.Recompiler.EnableFastmem)`, and `pcsx2/vtlb.cpp:1299 if (!CHECK_FASTMEM || !CHECK_EEREC || !vtlbdata.vmap)`. So every guest memory access goes through the slow vtlb software path.
- **EECache is off** in practice, because the cache check is interleaved with the recompiler: `pcsx2/vtlb.cpp:172,227,255,294,582,593,598,608` all read `if (!CHECK_EEREC && CHECK_CACHE && …)`.
- `pcsx2/MTVU.h`/`MTVU.cpp` MTVU thread is a no-op dummy.

**Performance magnitude — labelled SPECULATION:** I found no benchmark numbers, no perf table, and no "expected FPS" claim anywhere in this repository for the arm64 interpreter path. I therefore cannot quantify the slowdown from source. Based on the interpreter-vs-recompiler instruction-dispatch ratio typical of MIPS JIT emulators, a plausible (unverified) range is roughly one to two orders of magnitude slower than the x86 recompiled path — i.e. the arm64 macOS build today is best described by the project's own phrase "VERY slow," suitable for debugging and possibly very light 2D titles, not a playable M4 iPad product. **This number must be measured empirically; do not quote it as fact.**

### 9.3 Net assessment for the feasibility study

| Question | Answer from source |
|---|---|
| Does PCSX2 build for arm64 today? | **Yes** — with an explicit upstream `UNSUPPORTED CONFIGURATION` warning (`CMakeLists.txt:84-93`) |
| Does it *run* on arm64? | **Yes**, interpreter-only, and upstream ships an arm64 macOS CI artifact |
| Is the EE/JIT ported to arm64? | **No** — `pcsx2/arm64/` has 6 files, none of them `iR5900`/`iR3000A`/`microVU` |
| Is there an arm64 VU recompiler? | **No.** Neither micro nor macro mode. VIF-unpack dynarec and GS software-renderer JIT only |
| Does it need executable memory? | **Yes, and it writes it as permanently RWX** (`pcsx2/Memory.cpp:112` + `PageAccess_Any()` + `common/Linux/LnxHostSys.cpp:160-192` + `pcsx2/Resources/PCSX2.entitlements:5-10`) |
| Does it need `MAP_JIT`? | **Yes on Apple** (`common/Linux/LnxHostSys.cpp:161-164`, `3rdparty/xbyak/xbyak/xbyak.h:997-1000`) |
| Is Metal available? | **Yes, fully** — 8 `.metal` shaders, `GSDeviceMTL.mm` (2,822 lines), and it is the macOS default renderer |
| Is a non-Qt frontend possible? | **Yes, proven** — `pcsx2-gsrunner` links only `PCSX2` + `PCSX2_FLAGS`; `Host::` is the ~90-function boundary, already implemented twice |
| Any libretro core? | **No** — searched, zero matches for `libretro.h`/`retro_run`/`RETRO_API` in any `.cpp` |
| Any iOS code? | **None.** No iOS target, no UIKit, no `TARGET_OS_IPHONE` in `pcsx2/` or `pcsx2-qt/` |
| License | **GPL-3.0-or-later** (not LGPL) + GPLv2/GPLv3-only files in the arm64 subtree |

**The two independent hard problems for an iPadOS port are therefore:**
1. **No arm64 EE/VU/IOP recompilers + a hard RWX/JIT requirement** → either write a new aarch64 JIT backend (large, and still gated by iOS JIT-entitlement policy) or ship an interpreter-only emulator the upstream project itself calls "VERY slow."
2. **GPLv3+ copyleft + Qt6/KDDockWidgets desktop GUI + `dlopen`/`shm_open`/`NSTask`/AppKit dependencies** → the shipped frontend and several core subsystems cannot be compiled or distributed for iPadOS as-is.

Metal, the `Host::` frontend abstraction, and the arm64 build infrastructure are already in place and are the parts that do **not** need work.

---

## Appendix: Things I could NOT determine

- **Exact performance of the arm64 interpreter path.** No benchmarks, FPS numbers, or perf tables exist in this repository. §9.2's "one to two orders of magnitude" is explicitly labelled speculation.
- **iOS JIT-entitlement availability today.** The repo requests macOS Hardened-Runtime keys only. Whether Apple grants an equivalent for iPadOS emulators is a policy question not answerable from this source tree; it must be checked against current Apple documentation / App Store guidelines.
- **Licenses for `3rdparty/ccc`, `3rdparty/glad`, `3rdparty/winpixeventruntime`.** No `LICENSE`/`LICENCE`/`COPYING`/`COPYRIGHT` file found in those directories by a recursive filename scan; `ccc/README.md` only points to an upstream repo. Upstream licenses are MIT/BSD in each case, but I did not confirm from in-tree text.
- **`3rdparty/include`** contains no license file and appears to be a stub/aggregate include directory; not investigated further.
- **Whether `PCSX2` builds as a shared library** (i.e. a `SHARED` vs default `STATIC` `add_library`). `pcsx2/CMakeLists.txt:8 add_library(PCSX2)` does not specify a type, so it follows `BUILD_SHARED_LIBS` (which I did not find set anywhere). A SwiftUI frontend could link either way, but the ABI/visibility story was not verified.
- **Vulkan-on-iOS viability.** `3rdparty/vulkan/include/vulkan/vulkan_ios.h` ships `VK_MVK_ios_surface` definitions (lines 22-25), but PCSX2's own Vulkan path loads MoltenVK via `dlopen` from a bundle `Frameworks` dir, which is not how iOS would deliver it. Not assessed.
