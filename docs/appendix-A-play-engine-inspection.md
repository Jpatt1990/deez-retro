# Play! PS2 Emulator — Source-Level Technical Profile
**Target of study:** port to iPadOS on Apple M4 iPad Pro (arm64, no JIT by default)
**Repository inspected (read-only):** `C:\Users\jpatt\deez-retro-work\upstream\Play-`
**Version:** `PROJECT_Version 0.30` (`CMakeLists.txt:26`), overridden at configure time by `git describe --always` (`CMakeLists.txt:32-48`).

---

## ⚠️ METHODOLOGY LIMITATION — READ FIRST

**All six git submodules are checked out as EMPTY directories in this clone.** `git submodule status` returns a leading `-` for every entry (meaning "not initialized"):

```
-f799f60ef6fa8b9676b4102b7dfa169fb40b6c92 deps/AltKit
-a5009f7dca062695b8e5aebbd71e67b4ddfa9251 deps/CodeGen
-8a5f6b1dea0b888b5a42b821e79470142bbea4e3 deps/Dependencies
-587f278917acc0026bf5fc34b39f995fc26bd015 deps/Framework
-d96578b5a18edc67a268ed4811f0a035c56de7a0 deps/Nuanceur
-284e38b6e53e0a7270cc234934e45230ed915a25 deps/libchdr
```
`Get-ChildItem deps\<name> -Force` returns 0 items for all six; `deps` contains 6 entries total.

**Consequence for accuracy:** the *entire CPU code generator* (`Jitter::CCodeGen`), the executable-memory allocator (`CMemoryFunction`), and the third-party license bundle live in these absent submodules. Where this report relies on submodule content, it is marked **[EXTERNAL-VERIFIED]** and was read over the network from the exact pinned commit via GitHub raw/API — not from the local clone. Everything else is **[LOCAL]**.

---

## 1. LICENSE

### 1.1 Project license: BSD 2-Clause (NOT GPLv3) **[LOCAL]**

The license file is named `License.txt` (not `LICENSE`/`COPYING`) at the repo root. There is **no SPDX identifier anywhere in the tree** — a grep for `SPDX-License-Identifier` across the whole repo returned 0 matches; a grep for `GNU General Public|Lesser General Public|Apache License|MIT License` returned only 2 hits, both in the Android Gradle wrapper bootstrap script (`build_android/gradlew:6`, `build_android/gradlew.bat:4`), which is unrelated tooling.

`License.txt:1-11`:
```
Copyright (c) 2006-2026, Jean-Philip Desjardins
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
```
Exactly **two** conditions and no third "endorsement" clause → **BSD-2-Clause**. The disclaimer (`License.txt:13-23`) is boilerplate BSD. This is permissive and carries **no copyleft, no source-disclosure obligation for the app**, and no App Store conflict — the single most important licensing finding for this feasibility study.

### 1.2 Per-file SPDX headers: **none found** **[LOCAL]**
Searched with `grep` tool, pattern `SPDX-License-Identifier` over the entire repository root. 0 matches. The project relies solely on the root `License.txt`.

### 1.3 Bundled submodules and their licenses

| Submodule | Pinned commit | License | Status |
|---|---|---|---|
| `deps/CodeGen` (Play--CodeGen) | `a5009f7dca062695b8e5aebbd71e67b4ddfa9251` | **BSD-2-Clause** — `License.txt`, "Copyright (c) 2010-2026, Jean-Philip Desjardins", byte-identical structure to root (1336 bytes), two conditions | **[EXTERNAL-VERIFIED]** |
| `deps/Framework` (Play--Framework) | `587f278917acc0026bf5fc34b39f995fc26bd015` | **NOT DETERMINED** — dir empty; not fetched | — |
| `deps/Nuanceur` | `d96578b5a18edc67a268ed4811f0a035c56de7a0` | **NOT DETERMINED** | — |
| `deps/libchdr` | `284e38b6e53e0a7270cc234934e45230ed915a25` | **NOT DETERMINED** | — |
| `deps/AltKit` | `f799f60ef6fa8b9676b4102b7dfa169fb40b6c92` | **NOT DETERMINED** | — |
| `deps/Dependencies` | `8a5f6b1dea0b888b5a42b821e79470142bbea4e3` | aggregate bundle — see 1.4 | partially **[EXTERNAL-VERIFIED]** |

### 1.4 Bundled third-party bundle `deps/Dependencies` **[EXTERNAL-VERIFIED, tree only]**

GitHub API tree listing at the pinned commit `8a5f6b1dea0b888b5a42b821e79470142bbea4e3` yields these vendored components:

`SDWebImage` (submodule), `build_android`, `build_cmake`, `build_win32`, `bzip2-1.0.6`, `cmake-ios`, `cmake-modules`, `d3dcompiler_winxp`, `ghc_filesystem` (submodule), `glew-2.0.0`, `iCade-iOS`, `lzmasdk-18.05`, `nlohmann_json`, `sqlite-3.20.1`, `tdemu-1.10`, `unrarsrc-5.2.5`, `xxHash` (submodule), `zlib` (submodule), `zstd` (submodule).

**Which of these the core actually consumes** (from `CMakeLists.txt` `add_subdirectory` calls) **[LOCAL]**:

- **Always, by `PlayCore`** (`Source/CMakeLists.txt`):
  - bzip2 — `find_package(BZip2)` first, falls back to bundled (`:87-101`)
  - `libzstd_zlibwrapper_static` — always bundled (`:103-109`)
  - `xxHash::xxhash` — always bundled (`:111-121`)
  - `libchdr` → `chdr-static` — always bundled (`:129-136`)
- **Optional**: ICU (`find_package(ICUUC)`, `:124-127`), nlohmann_json (`Source/ui_shared/CMakeLists.txt:26`, found-then-bundled), Qt6/Qt5 (desktop UI only), Vulkan (`find_package(Vulkan)`).
- **iOS-specific**: `iCade-iOS` (`Source/ui_ios/CMakeLists.txt:55-61`), `SDWebImage` (`:63-69`), `AltKit` (`:79-85`).
- **Tooling-only**: `unrarsrc-5.2.5` is pulled only by the optional PsfPlayer (`tools/PsfPlayer/Source/CMakeLists.txt:25`), which is `OFF` by default (`CMakeLists.txt:19`). `d3dcompiler_winxp` only by the Windows-only D3D9 backend.

> **⚠️ Note the `unrarsrc-5.2.5` (UnRAR) entry.** UnRAR's upstream license is famously *not* OSI-open-source and forbids use in recreating the RAR compression algorithm. It is **not** linked into the PS2 emulation core or the iOS build in the default configuration — but a licensing review should confirm this if PsfPlayer is ever enabled. I did **not** read its license file (dir absent); flagging as **UNVERIFIED**.

> **`tdemu-1.10`** (TrueMotion video decoder) appears in the bundle; I did **not** determine which target consumes it or its license. **UNVERIFIED.**

### 1.5 Explicitly named dependencies in the request: presence check **[LOCAL]**

- **SDL2 — NO SDL2 FOUND.** `grep` for `SDL` across all `CMakeLists.txt` returned only false positives: the string `_SDL_Proxy` in `Source/ui_js/CMakeLists.txt:58` is the PS2 VU "Store Doubleword Left" helper function name, not Simple DirectMedia Layer. Play! uses Qt for desktop windowing, not SDL.
- **ffmpeg — NO FFMPEG DEPENDENCY FOUND.** No `find_package`, no `add_subdirectory`, no `#include <libav*>` anywhere. The only occurrence of the string is a **stale comment** in the iOS toolchain (`deps/Dependencies/cmake-ios/ios.cmake`): `# When ffmpeg has been rebuilt for arm64 use:` — historical, and the line immediately below it already sets `set(IOS_ARCH "arm64")`.
- **libpng — NO LIBPNG FOUND.** Only `.png` *resource files* (icons) match.
- **zlib — present but not via `find_package`.** The `zstd_zlibwrapper` bundled target provides the zlib API; `Source/discimages/IszImageStream.cpp:201-218` calls `uncompress`/`BZ_OK` directly.

---

## 2. BUILD SYSTEM

### 2.1 Build system: CMake (exclusively) **[LOCAL]**

Top-level build files:

| Path | Role |
|---|---|
| `CMakeLists.txt` (97 lines) | Root; `cmake_minimum_required(VERSION 3.15)` (`:1`); `project(Play)` (`:8`) |
| `CMakePresets.json` (6667 bytes) | Preset definitions (`windows-x86_64-vs`, `windows-debugger-x86_64-vs`, …) |
| `Source/CMakeLists.txt` (580 lines) | The core: `cmake_minimum_required(VERSION 3.18)` (`:1`), `project(PlayCore)` (`:9`) |
| `Source/ui_ios/CMakeLists.txt` | iOS frontend app target |
| `Source/ui_qt/CMakeLists.txt` | Desktop Qt frontend |
| `Source/ui_android/CMakeLists.txt`, `Source/ui_js/CMakeLists.txt`, `Source/ui_libretro/CMakeLists.txt` | Other frontends |
| `tools/*/CMakeLists.txt` | Tests and tools |
| `build_android/build.gradle` | Android Gradle wrapper around the CMake build |
| `installer_ios/`, `installer_macos/`, `installer_win32/`, `installer_unix/`, `installer_android/` | Packaging |

**CMake minimum version: 3.15 at the root** (`CMakeLists.txt:1`) and **3.18 for `Source/` and `Source/ui_ios/`** (`Source/CMakeLists.txt:1`, `Source/ui_ios/CMakeLists.txt:1`).

**NOT Premake:** glob for `**/{premake*,*.lua,Makefile,*.mk}` → **no files found**.
**NOT MSBuild/Xcode as a source of truth:** glob for `**/*.{sln,vcxproj,slnx,xcodeproj,pbxproj}` → only two legacy files, both for a side tool: `tools/MediaCenter/build_win32/MediaCenter.sln` and `MediaCenter.vcxproj`. The main emulator's `.sln`/`.xcodeproj` are **generated by CMake** (README.md:157 "just double click on `Play.slnx` in 'build' folder" — i.e. produced in the build dir).

### 2.2 Required external dependencies

**Core (`PlayCore`) hard requirements** — `Source/CMakeLists.txt:34-142`:

| Dependency | Bundled or system | Evidence |
|---|---|---|
| `Framework` (Play--Framework) | bundled submodule | `:39-46` |
| `Framework_Http` | bundled submodule | `:48-54` |
| `app_shared` (in-tree) | in-tree | `:56-62` |
| `Framework_Amazon` (AWS S3) | bundled submodule, default ON | `:64-77`, `ENABLE_AMAZON_S3 ON` at `:16` |
| `CodeGen` | bundled submodule | `:79-85` |
| **BZip2** | `find_package` → **system if found, else bundled** | `:87-101` |
| **zstd + zlib wrapper** | **always bundled** | `:103-109` |
| **xxHash** | **always bundled** | `:111-121` |
| **ICU** (optional) | system | `:123-127` `find_package(ICUUC)` |
| **libchdr** | bundled submodule | `:129-136` |
| **Threads / pthread** | system, **REQUIRED** except Android/iOS | `:138-142` `find_package(Threads REQUIRED)` |

Platform-conditional:
- `-msse -msse2 -mssse3` added for x86 UNIX only (`Source/CMakeLists.txt:34-36`, guarded against ARM/AARCH64).
- `-fbracket-depth=512` for Clang (`:550-552`).
- Windows adds `winmm` (`:554-557`).

**Frontend-level requirements:**
- **Audio:** OpenAL via `FrameworkOpenAl` (`Source/sound/SH_OpenAL/CMakeLists.txt:15`); iOS links `-framework OpenAL` (`Source/ui_ios/CMakeLists.txt:167`). Also `SH_WaveOut` (Win32) and `SH_XAudio2` (Win32).
- **Graphics:** `Framework_OpenGl` (`Source/gs/GSH_OpenGL/CMakeLists.txt:7`), `Framework_Vulkan` + Vulkan SDK (`Source/gs/GSH_Vulkan/CMakeLists.txt:7`, `Source/ui_ios/CMakeLists.txt:12`), `FrameworkWin32` + D3D9 (Windows only).
- **Qt6 or Qt5** — desktop only; `find_package(Qt6 COMPONENTS ...)` falling back to `find_package(Qt5 REQUIRED ...)` (`Source/ui_qt/CMakeLists.txt:255,261`). **iOS does not use Qt** (root `CMakeLists.txt:69-72` gates `ui_ios` on `NOT USE_QT`; README.md:189 "iOS build doesn't use Qt").
- **libevdev** — Linux input (`Source/ui_qt/CMakeLists.txt:59`).
- **iOS system frameworks:** UIKit, CoreGraphics, GameController, QuartzCore, ImageIO (`Source/ui_ios/CMakeLists.txt:87-91`), plus `-lsqlite3` and `-ObjC` (`:167`).

**Notably absent:** SDL2, ffmpeg, libpng. See §1.5.

---

## 3. CPU CORE / JIT

### 3.1 Is there a JIT? Yes — and it covers EE, VU0, VU1, and both VU modes.

Play! is **JIT-only for CPU emulation**. The block executor hierarchy always calls generated native code.

- `Source/GenericMipsExecutor.h:22` — `class CGenericMipsExecutor : public CMipsExecutor`
- `Source/GenericMipsExecutor.h:59-70` — `int Execute(int cycles) override { ... block->Execute(); }`
- `Source/BasicBlock.cpp:331-333` — `void CBasicBlock::Execute() { m_function(&m_context); ... }`
- `Source/GenericMipsExecutor.h:139` — `auto block = BlockFactory(m_context, start, end);`

The code generator is created on demand at `Source/BasicBlock.cpp:90`:
```cpp
Jitter::CCodeGen* codeGen = Jitter::CreateCodeGen();
jitter = new CMipsJitter(codeGen);
```
`CMipsJitter` derives from the backend-agnostic IR layer: `Source/MipsJitter.h:6` — `class CMipsJitter : public Jitter::CJitter`.

### 3.2 Where the backends live **[EXTERNAL-VERIFIED]**

All backends are in the **`deps/CodeGen` submodule** (absent locally). Its `CMakeLists.txt` at commit `a5009f7d…` unconditionally compiles these backend sources:

```
src/AArch32Assembler.cpp
src/AArch64Assembler.cpp
src/Jitter_CodeGen_AArch32.cpp
src/Jitter_CodeGen_AArch32_64.cpp
src/Jitter_CodeGen_AArch32_Fpu.cpp
src/Jitter_CodeGen_AArch32_Md.cpp
src/Jitter_CodeGen_AArch64.cpp
src/Jitter_CodeGen_AArch64_64.cpp
src/Jitter_CodeGen_AArch64_Fpu.cpp
src/Jitter_CodeGen_AArch64_Md.cpp
src/Jitter_CodeGen_x86_32.cpp
src/Jitter_CodeGen_x86_64.cpp
src/Jitter_CodeGen_x86.cpp
src/Jitter_CodeGen_x86_Fpu_Avx.cpp
src/Jitter_CodeGen_x86_Fpu_Sse.cpp
src/Jitter_CodeGen_x86_Md_Avx.cpp
src/Jitter_CodeGen_x86_Md_Sse.cpp
src/Jitter_CodeGen_Wasm.cpp
src/Jitter_CodeGen_Wasm_64.cpp
src/Jitter_CodeGen_Wasm_Fpu.cpp
src/Jitter_CodeGen_Wasm_Md.cpp
src/Jitter_CodeGenFactory.cpp
src/MemoryFunction.cpp
```
Public headers include `include/Jitter_CodeGen_AArch64.h`, `include/Jitter_CodeGen_AArch32.h`, `include/Jitter_CodeGen_Wasm.h`, `include/Jitter_CodeGen_x86*.h`, `include/MemoryFunction.h`.

### 3.3 Backends available: x86-32, x86-64 (SSE + AVX variants), AArch32, **AArch64**, WASM

**Answer to "is there an arm64 dynarec at all?" — YES, a first-class one: `Jitter::CCodeGen_AArch64`.**

Runtime selection — `deps/CodeGen/src/Jitter_CodeGenFactory.cpp` `[EXTERNAL-VERIFIED]`, showing both the Apple and generic paths:
```cpp
#elif defined(__APPLE__)
	#include <TargetConditionals.h>
	#if TARGET_CPU_ARM
		#include "Jitter_CodeGen_AArch32.h"
	#elif TARGET_CPU_ARM64
		#include "Jitter_CodeGen_AArch64.h"
	...
#else
	#if defined(__arm__)
		#include "Jitter_CodeGen_AArch32.h"
	#elif defined(__aarch64__)
		#include "Jitter_CodeGen_AArch64.h"
```
and in `Jitter::CreateCodeGen()`:
```cpp
#elif defined(__APPLE__)
	...
	#elif TARGET_CPU_ARM64
		return new Jitter::CCodeGen_AArch64();
```
Note there is **no user-facing setting** to pick a backend: selection is purely compile-time/preprocessor. There is no "disable JIT" option.

### 3.4 Does arm64 coverage include VU macro AND micro mode? Yes — all paths funnel through the same `CCodeGen`.

The VU has two execution modes in Play!, and **both** compile through `CMipsJitter` → `Jitter::CCodeGen`, so a single backend covers everything:

| Unit | Mode | Class | Compiled via |
|---|---|---|---|
| EE main CPU | — | `CEeBasicBlock` / `CEeExecutor` | `Source/ee/EeExecutor.h:18`, `Source/ee/EeExecutor.cpp:216` `std::make_shared<CEeBasicBlock>(...)`, then `result->Compile()` (`:230`) |
| VU macro mode (EE COP2) | macro | `CCOP_VU` : `CMIPSCoprocessor` | `Source/ee/COP_VU.h:7,12` — `void CompileInstruction(uint32, CMipsJitter*, CMIPS*, uint32) override;` |
| VU macro mode (EE internal COP2) | macro | `CMA_VU` : `CMIPSArchitecture` | `Source/ee/MA_VU.h:10,15`; instantiated as `CMA_VU m_MAVU0; CMA_VU m_MAVU1;` in `Source/ee/Ee_SubSystem.h:116-117` |
| VU micro mode (VU0/VU1 running microcode) | micro | `CVuBasicBlock` / `CVuExecutor` | `Source/ee/VuExecutor.h:6` `class CVuExecutor : public CGenericMipsExecutor<BlockLookupOneWay, 8>`; `Source/ee/VuBasicBlock.cpp` uses `jitter->BeginIf(...)` etc. |
| VU micro instruction impl | micro | `CMA_VU::CLower` / `CUpper` | `Source/ee/MA_VU_Lower.cpp:27` — `void CMA_VU::CLower::CompileInstruction(uint32 address, CMipsJitter* codeGen, ...)`; `Source/ee/MA_VU_Upper.cpp:20` |

Instantiation of the VU JIT executors — `Source/ee/Ee_SubSystem.cpp:76,114,136`:
```cpp
m_EE.m_executor  = std::make_unique<CEeExecutor>(m_EE, m_ram);
m_VU0.m_executor = std::make_unique<CVuExecutor>(m_VU0, PS2::MICROMEM0SIZE);
m_VU1.m_executor = std::make_unique<CVuExecutor>(m_VU1, PS2::MICROMEM1SIZE);
```

### 3.5 Is there a pure INTERPRETER fallback for EE or VU? **NO — none exists.**

Searched with the `grep` tool, case-insensitive pattern `interpret` over the entire repository. All **946** matches are `reinterpret_cast` / `reinterpret_cast<...>`; there are **zero** matches for an interpreter class, file, or execution mode. There is no `CMIPSInterpreter`, no `MIPSInterpreter.cpp`, and `Source/MipsExecutor.h` declares only the abstract `CMipsExecutor` with a single `Execute` entry point (`Source/MipsExecutor.h:5-18`). The concrete implementation `CGenericMipsExecutor` (`Source/GenericMipsExecutor.h:22`) has exactly one execution path — the JIT block path.

The **only** alternative "backend" is the WASM code generator for the browser build (`Source/ui_js/Ps2VmJs.cpp:2` `#include "Jitter_CodeGen_Wasm.h"`), which still emits WebAssembly rather than interpreting — so it is not an interpreter fallback either, and it is not usable on iOS.

> **This is the single most consequential architectural finding for the iPadOS port.** There is no fallback to enable. Without executable-memory permission, Play! cannot emulate the EE or the VUs *at all*.

---

## 4. DOES THE JIT WRITE TO EXECUTABLE MEMORY?

**Yes. Unconditionally.** All JIT output is materialized into a self-modifying, executable buffer.

### 4.1 Where the buffer is created — `Source/BasicBlock.cpp:77-101` **[LOCAL]**
```cpp
void CBasicBlock::Compile()
{
#ifndef AOT_USE_CACHE
	Framework::CMemStream stream;
	{
		...
		Jitter::CCodeGen* codeGen = Jitter::CreateCodeGen();
		jitter = new CMipsJitter(codeGen);
		...
		jitter->SetStream(&stream);
		jitter->Begin();
		CompileRange(jitter);
		jitter->End();
	}
	m_function = CMemoryFunction(stream.GetBuffer(), stream.GetSize());
```
`CMemoryFunction` is the executable-memory owner, defined in the absent `deps/CodeGen`.

### 4.2 The JIT **rewrites its own generated code in place after execution begins** — `Source/BasicBlock.cpp:399-434` **[LOCAL]**
This is crucial: it is not merely "write once, then execute".
```cpp
void CBasicBlock::LinkBlock(LINK_SLOT linkSlot, CBasicBlock* otherBlock)
{
#if !defined(AOT_ENABLED) && !defined(__EMSCRIPTEN__)
	...
	auto patchValue = reinterpret_cast<uintptr_t>(otherBlock->m_function.GetCode());
	auto code = reinterpret_cast<uint8*>(m_function.GetCode());
	m_function.BeginModify();
	*reinterpret_cast<uintptr_t*>(code + m_linkBlockTrampolineOffset[linkSlot]) = patchValue;
	m_function.EndModify();
#endif
}
```
The block linker writes a raw pointer **into the middle of already-generated executable code**, then invalidates the instruction cache. `BeginModify()`/`EndModify()` (lines 412/414) are exactly the protection-transition hooks.

### 4.3 The allocator: `deps/CodeGen/src/MemoryFunction.cpp` **[EXTERNAL-VERIFIED]**

This is the decisive file. Per-platform strategy:

```cpp
#ifdef _WIN32
	#define MEMFUNC_USE_WIN32
#elif defined(__APPLE__)
	#include "TargetConditionals.h"
	#include <libkern/OSCacheControl.h>
	#if TARGET_OS_OSX
		#define MEMFUNC_USE_MMAP
		#define MEMFUNC_MMAP_ADDITIONAL_FLAGS (MAP_JIT)
		#if TARGET_CPU_ARM64
			#define MEMFUNC_MMAP_REQUIRES_JIT_WRITE_PROTECT
		#endif
	#else
		#define MEMFUNC_USE_MACHVM
		#if TARGET_OS_IPHONE
			#define MEMFUNC_MACHVM_STRICT_PROTECTION
		#endif
	#endif
#elif defined(__EMSCRIPTEN__)
	#define MEMFUNC_USE_WASM
#else
	#define MEMFUNC_USE_MMAP
#endif
```

**iOS (`TARGET_OS_IPHONE`) uses `MEMFUNC_USE_MACHVM` with `MEMFUNC_MACHVM_STRICT_PROTECTION`:**
```cpp
#elif defined(MEMFUNC_USE_MACHVM)
	vm_size_t page_size = 0;
	host_page_size(mach_task_self(), &page_size);
	unsigned int allocSize = ((size + page_size - 1) / page_size) * page_size;
	vm_allocate(mach_task_self(), reinterpret_cast<vm_address_t*>(&m_code), allocSize, TRUE);
	memcpy(m_code, code, size);
	vm_prot_t protection =
	#ifdef MEMFUNC_MACHVM_STRICT_PROTECTION
		VM_PROT_READ | VM_PROT_EXECUTE;
	#else
		VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE;
	#endif
	kern_return_t result = vm_protect(mach_task_self(), reinterpret_cast<vm_address_t>(m_code), size, 0, protection);
	assert(result == 0);
```

**macOS arm64 uses `mmap` + `MAP_JIT` + `pthread_jit_write_protect_np`:**
```cpp
	m_code = mmap(nullptr, size, PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | additionalMapFlags, -1, 0);
	...
#ifdef MEMFUNC_MMAP_REQUIRES_JIT_WRITE_PROTECT
	pthread_jit_write_protect_np(false);
#endif
	memcpy(m_code, code, size);
#ifdef MEMFUNC_MMAP_REQUIRES_JIT_WRITE_PROTECT
	pthread_jit_write_protect_np(true);
#endif
```

**Windows is outright RWX:**
```cpp
	m_code = framework_aligned_alloc(size, BLOCK_ALIGN);
	memcpy(m_code, code, size);
	DWORD oldProtect = 0;
	BOOL result = VirtualProtect(m_code, size, PAGE_EXECUTE_READWRITE, &oldProtect);
```

**Linux/Android (generic `MEMFUNC_USE_MMAP`) is outright RWX** — note no `MEMFUNC_MMAP_REQUIRES_JIT_WRITE_PROTECT` is defined off macOS-arm64, so no write-protect toggling occurs:
```cpp
	m_code = mmap(nullptr, size, PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | additionalMapFlags, -1, 0);
```

And the explicit W^X transitions used by the in-place patcher:
```cpp
void CMemoryFunction::BeginModify()
{
#if defined(MEMFUNC_USE_MACHVM) && defined(MEMFUNC_MACHVM_STRICT_PROTECTION)
	kern_return_t result = vm_protect(mach_task_self(), ..., VM_PROT_READ | VM_PROT_WRITE);
#elif defined(MEMFUNC_USE_MMAP) && defined(MEMFUNC_MMAP_REQUIRES_JIT_WRITE_PROTECT)
	pthread_jit_write_protect_np(false);
#endif
}

void CMemoryFunction::EndModify()
{
#if defined(MEMFUNC_USE_MACHVM) && defined(MEMFUNC_MACHVM_STRICT_PROTECTION)
	kern_return_t result = vm_protect(mach_task_self(), ..., VM_PROT_READ | VM_PROT_EXECUTE);
#elif ...
	pthread_jit_write_protect_np(true);
#endif
	ClearCache();
}
```

### 4.4 Verdict on the W^X / no-JIT question

| Platform | Allocation | RWX or W^X? |
|---|---|---|
| Windows | `VirtualAlloc`+`VirtualProtect(PAGE_EXECUTE_READWRITE)` | **RWX** |
| Linux/Android | `mmap(PROT_WRITE\|PROT_EXEC)` | **RWX** |
| **macOS arm64** | `mmap(MAP_JIT, PROT_WRITE\|PROT_EXEC)` + `pthread_jit_write_protect_np` | **W^X via MAP_JIT hardening** |
| **iOS/iPadOS** | `vm_allocate` → `vm_protect(R\|X)`, transitions to `R\|W` in `BeginModify`, back to `R\|X` in `EndModify` | **Strictly W^X** — single mapping, alternating protection, never simultaneous RWX |

**The iOS code path is already W^X-clean and uses the exact hardened-runtime pattern Apple expects** (RW↔RX transitions on a single mapping, no dual-mapping, no persistent RWX). That removes one class of App-Store/hardened-runtime objection.

**However — and this is decisive — W^X cleanliness is orthogonal to entitlement availability.** The code still *requires* the ability to create `VM_PROT_EXECUTE` pages. On stock (non-jailbroken, non-debugged) iPadOS, a third-party app cannot `vm_protect` to `VM_PROT_EXECUTE` or `mmap(MAP_JIT)` without the JIT entitlement, which is not grantable to App Store apps; `assert(result == 0)` at `vm_protect` would abort. Play!'s own documentation states this outright.

### 4.5 Play!'s own confirmation that JIT is mandatory on iOS **[LOCAL]**

`README.md:32-47`:
```
## Running on iOS ##

This emulator uses JIT code generation to speed things up. This is not supported by default by iOS, thus, there are some extra requirements:

- Have a device running iOS 13 or less, or an arm64e device running iOS 14.2/14.3.
- Have a jailbroken device.
...
**If you try to play a game without JIT enabled, you will experience a crash when you launch the game.**
```

The app **detects** the absence of JIT and warns the user, but does not degrade gracefully — `Source/ui_ios/CoverViewController.mm:12-30`:
```cpp
static bool IsJitAvailable()
{
	//If ppid != 1, it means we're being run in the debugger
	if(getppid() != 1) return true;
	if([[AltServerJitService sharedAltServerJitService] jitEnabled])
	{
		return true;
	}
	{
		//Check if we can scan the mobile directory (only possible if jailbroken)
		std::error_code errorCode;
		fs::directory_iterator dirIterator("/private/var/mobile", errorCode);
		if(!errorCode)
		{
			return true;
		}
	}
	return false;
}
```
and `Source/ui_ios/CoverViewController.mm:194`:
```objc
UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"JIT unavailable" message:@"JIT doesn't seem to be available at the moment. If JIT is not available, the emulator will crash. Do you wish to continue?" ...];
```

There is also a **simulated-debugger** trick to obtain the JIT entitlement via `ptrace` — `Source/ui_ios/DebuggerSimulator.cpp:10-14`:
```cpp
void StartSimulateDebugger()
{
	auto ptrace_ptr = reinterpret_cast<ptrace_ptr_t>(dlsym(RTLD_SELF, "ptrace"));
	ptrace_ptr(PT_TRACE_ME, 0, NULL, 0);
}
```

### 4.6 A genuine partial escape hatch: AOT block cache

The only mechanism that could bypass runtime codegen is the **Ahead-Of-Time block cache**. `Source/BasicBlock.cpp:25-41,150-174` — with `AOT_USE_CACHE` the JIT emits object files offline (`Jitter::CObjectFile`, with `CPU_ARCH_ARM64` support at `tools/PsfPlayer/Source/ui_aot/Main_Aot.cpp:264`) and at runtime only *links against precompiled native functions*:
```cpp
#ifdef AOT_USE_CACHE
	AOT_BLOCK* blocksBegin = &_aot_firstBlock;
	...
	m_function = reinterpret_cast<void (*)(void*)>(blockIterator->fct);
#endif
```
**Caveat:** the AOT-cached functions still live in executable memory inside the app binary (which is legitimately `PROT_EXEC` from the code signature), so this is *architecturally* the one viable route to no-JIT operation — but it is gated behind `BUILD_AOT_CACHE`, which the root CMakeLists annotates as **"for PsfPlayer only"** (`CMakeLists.txt:22`), and `USE_AOT_CACHE` defaults to **OFF** (`:21`). It is not wired up for the iOS app. I did not verify how much of the EE/VU workload it can cover. **Flagging as the key open engineering question, not a confirmed solution.**

---

## 5. GRAPHICS BACKENDS

### 5.1 Backends present **[LOCAL]**

Interface + implementations under `Source/gs/`:

| Backend | Path | Target |
|---|---|---|
| Null / stub | `Source/gs/GSH_Null.cpp`, `GSH_Null.h` | `CGSH_Null : public CGSHandler` — no rendering |
| OpenGL (desktop/GL) | `Source/gs/GSH_OpenGL/` | `gsh_opengl` STATIC (`GSH_OpenGL/CMakeLists.txt:29`) |
| OpenGL (Win32 WGL) | `Source/gs/GSH_OpenGLWin32/` | Windows only |
| **Vulkan** | `Source/gs/GSH_Vulkan/` | `gsh_vulkan` STATIC (`GSH_Vulkan/CMakeLists.txt:29`) |
| Direct3D 9 | `Source/gs/GSH_Direct3D9/` | Windows only |

**There is NO software rasterizer.** `CGSH_Null` (`Source/gs/GSH_Null.h:5-21`) only implements the transfer hooks as no-ops; it renders nothing. This matters: there is no CPU fallback renderer for iPadOS if the GPU API path is unavailable.

Shaders are generated portably at runtime via **Nuanceur** — a shader IR/codegen library (`Source/gs/GSH_Vulkan/GSH_VulkanDraw.cpp:6-7` `#include "nuanceur/Builder.h"`, `#include "nuanceur/generators/SpirvShaderGenerator.h"`; `Source/gs/GSH_Direct3D9/GSH_Direct3D9_Shader.cpp:3` uses `HlslShaderGenerator`). So GLSL/SPIR-V/HLSL are all emitted from one C++ description — a Metal backend would require a new Nuanceur generator.

### 5.2 On Apple platforms specifically: **OpenGL ES (deprecated) AND Vulkan-via-MoltenVK. No Metal backend.**

**OpenGL on iOS** — `Source/ui_ios/GSH_OpenGLiOS.cpp:19-27`:
```cpp
void CGSH_OpenGLiOS::InitializeImpl()
{
	m_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
```
using `CAEAGLLayer` (`Source/ui_ios/GSH_OpenGLiOS.cpp:5` `CGSH_OpenGLiOS::CGSH_OpenGLiOS(CAEAGLLayer* layer)`), and `RenderView.mm:16` `return [CAEAGLLayer class];`. Note `Source/gs/GSH_OpenGL/GSH_OpenGL.h:17`:
```cpp
#if !defined(GLES_COMPATIBILITY) && !defined(__APPLE__)
```
i.e. desktop-GL-only code is excluded on Apple. This path uses **OpenGL ES 3.0, which Apple deprecated as of iOS 12** — functional but on a deprecation path.

**Vulkan on Apple = MoltenVK** — `Source/gs/GSH_Vulkan/GSH_Vulkan.cpp:88-94`:
```cpp
#ifdef __APPLE__
#if TARGET_OS_IPHONE
	extensions.push_back(VK_MVK_IOS_SURFACE_EXTENSION_NAME);
#else
	extensions.push_back(VK_MVK_MACOS_SURFACE_EXTENSION_NAME);
#endif
#endif
```
iOS presents into a **`CAMetalLayer`** — `Source/ui_ios/GSH_VulkaniOS.h:9,12,18`:
```objc
	CGSH_VulkaniOS(CAMetalLayer*);
	static FactoryFunction GetFactoryFunction(CAMetalLayer*);
	CAMetalLayer* m_layer = nullptr;
```
`Source/ui_ios/RenderView.mm:17-18`: `case PREFERENCE_VALUE_VIDEO_GS_HANDLER_VULKAN: return [CAMetalLayer class];`
`Source/ui_ios/EmulatorViewController.mm:90-94` selects the backend at runtime:
```objc
#ifdef HAS_GSH_VULKAN
	case PREFERENCE_VALUE_VIDEO_GS_HANDLER_VULKAN:
		g_virtualMachine->CreateGSHandler(CGSH_VulkaniOS::GetFactoryFunction((CAMetalLayer*)self.view.layer));
		break;
#endif
```
MoltenVK is bundled as an XCFramework — `Source/ui_ios/CMakeLists.txt:190-196`:
```cmake
		XCODE_EMBED_FRAMEWORKS "$ENV{VULKAN_SDK}/lib/MoltenVK.xcframework"
		XCODE_EMBED_FRAMEWORKS_CODE_SIGN_ON_COPY TRUE
```
MoltenVK quirks are explicitly worked around: `Source/gs/GSH_Vulkan/GSH_Vulkan.cpp:468` ("MoltenVK doesn't report this properly..."), `Source/gs/GSH_Vulkan/GSH_VulkanDrawDesktop.cpp:103` ("This image is needed for MoltenVK/Metal which seem to discard pixels").

There is a **mobile-specific Vulkan draw path**: `Source/gs/GSH_Vulkan/GSH_VulkanDrawMobile.cpp` (vs. `GSH_VulkanDrawDesktop.cpp`) — evidence the iOS/Android tile-GPU path is a deliberately maintained, separate implementation.

**Search for Metal:** grep for `Metal` across the repo returns only (a) `CAMetalLayer`/MetalLayer interop for MoltenVK (above; `Source/ui_qt/vulkanwindow.h:13` `void* GetMetalLayer() const;`, `Source/ui_qt/macos/LayerFromView.mm:11`), and (b) **false positives from game titles** — e.g. `Source/gs/GSHandler.cpp:1353` "//- Metal Slug 4", `tools/VuTest/FlagsTest4.cpp:10` "From Metal Gear Solid 3". **No native Metal renderer exists.**

---

## 6. PLATFORM / SHELL LAYER

### 6.1 Separation: clean — core is a standalone static library **[LOCAL]**

`Source/CMakeLists.txt:567-576`:
```cmake
add_library(PlayCore STATIC ${COMMON_SRC_FILES} ${PLATFORM_SPECIFIC_SRC_FILES})
target_link_libraries(PlayCore ${PROJECT_LIBS})
target_include_directories(PlayCore
	PUBLIC
		${CMAKE_CURRENT_SOURCE_DIR}
	PRIVATE
		${CMAKE_CURRENT_SOURCE_DIR}/../deps/Framework/include
		${CMAKE_CURRENT_SOURCE_DIR}/../deps/CodeGen/include
)
target_compile_definitions(PlayCore PUBLIC ${DEFINITIONS_LIST})
```

**The reusable target is `PlayCore`, a STATIC library** (`Source/CMakeLists.txt:567`). Note it is *not* named `libPlay`. Its `PUBLIC` include directory is `Source/`, so a host app adds `Source/` to its header search path and links `PlayCore` plus its transitive deps.

Frontends are thin executables that each consume `PlayCore`:
- iOS: `Source/ui_ios/CMakeLists.txt:20-26` (`add_subdirectory` of `Source/` if `NOT TARGET PlayCore`, then `list(APPEND UI_IOS_PROJECT_LIBS PlayCore)`), producing `add_executable(Play MACOSX_BUNDLE ...)` at `:158`.
- Qt desktop: `add_executable(Play ...)` at `Source/ui_qt/CMakeLists.txt:296,325,327,359`.
- libretro core: `Source/ui_libretro/` → artifact `play_libretro.dylib` / `play_libretro_ios.dylib` (`.github/workflows/build-macos.yaml:83`, `build-ios.yaml:62`).
- Android: `Source/ui_android/`; Web: `Source/ui_js/`.

**A custom SwiftUI frontend can therefore link `PlayCore` directly.** The iOS target is already `project(PlayUI LANGUAGES C Swift)` (`Source/ui_ios/CMakeLists.txt:9`) — **Swift is already an enabled language in the iOS build**, so mixed Swift/ObjC++ is already wired. The existing `main.mm`/`AppDelegate.mm` are ObjC, and `-fobjc-arc` is applied (`:159`), but the CMake project already declares Swift.

### 6.2 Public API boundary

The host-facing entry point is **`CPS2VM`**, declared in `Source/PS2VM.h:19`:
```cpp
class CPS2VM : public CVirtualMachine
```
Its host-relevant surface (`Source/PS2VM.h:37-95`) is small and clean:

| Member | Line | Purpose |
|---|---|---|
| `void Initialize(); void Destroy();` | `:40-41` | lifecycle |
| `void Resume() override; void Pause() override; void PauseAsync();` | `:48-50` | run control |
| `void Reset(...)` | `:51` | reset |
| `STATUS GetStatus() const override;` | `:53` | state query |
| `void CreateGSHandler(const CGSHandler::FactoryFunction&);` | `:55` | **inject renderer** |
| `void CreatePadHandler(const CPadHandler::FactoryFunction&);` | `:59` | inject input |
| `void CreateSoundHandler(const CSoundHandler::FactoryFunction&);` | `:63` | inject audio |
| `std::future<bool> SaveState(const fs::path&); / LoadState(...)` | `:77-78` | save states |
| `NewFrameEvent OnNewFrame;` | `:103` | **frame callback for the UI loop** |
| `ExecutableReloadedHandler Before/AfterExecutableReloaded;` | `:105-106` | hook points |
| `void ReportTouchPosition(float, float); void ReleaseScreenPosition();` | `:92-95` | **touch input already exists** |
| `OpticalMediaPtr m_cdrom0;` | `:97` | disc image |
| `static fs::path GetStateDirectoryPath();` | `:74` | paths |

The renderer is injected through a factory function, which is exactly how the three existing frontends plug in — e.g. `EmulatorViewController.mm:88`: `g_virtualMachine->CreateGSHandler(CGSH_OpenGLiOS::GetFactoryFunction((CAEAGLLayer*)self.view.layer));`.

Base class: `CVirtualMachine` in `Source/VirtualMachine.h` (declares `Resume`, `Pause`, `GetStatus`, `STATUS` enum).

Supporting public headers a host would touch: `Source/PS2VM.h`, `Source/VirtualMachine.h`, `Source/app_shared/AppConfig.h` (preferences), `Source/gs/GSHandler.h` (factory function type), `Source/ui_shared/BootablesProcesses.h` + `BootablesDbClient.h` (game library; already used by the iOS shell at `Source/ui_ios/CoverViewController.mm:5-6`).

`Source/ui_shared/` is the shared frontend-support library (library scanning, DB, arcade defs, stats) and is already consumed by iOS (`Source/ui_ios/CMakeLists.txt:71-77`). `Source/app_shared/` holds `AppConfig`/`Log` (`Source/app_shared/CMakeLists.txt`).

**Assessment:** the core/frontend boundary is genuinely library-grade. A SwiftUI shell is a realistic proposition *for the UI layer*; the blocker is entirely the CPU execution model, not the API shape.

---

## 7. APPLE / ARM64 READINESS

### 7.1 Existing arm64 dynarec: YES (§3.3)
`Jitter::CCodeGen_AArch64` with a dedicated `AArch64Assembler.cpp`, plus separate `_Fpu`, `_Md`, and `_64` translation files. This is a mature, not nominal, backend.

### 7.2 Existing Apple Silicon / macOS arm64 support: YES, and it ships universal

`.github/workflows/build-macos.yaml:41`:
```
cmake .. -G"Xcode" -DBUILD_LIBRETRO_CORE=yes "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
```
`.github/workflows/build-macos.yaml:45`:
```
xcodebuild -project Play.xcodeproj build -target ALL_BUILD -configuration Release -arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO
```
So macOS releases are already **universal arm64+x86_64**, and the AArch64 codegen runs natively on Apple Silicon today.

Apple-specific code paths already present **[LOCAL]**, from a grep of `Source/` for `TARGET_OS_IPHONE|TARGET_OS_IOS|TARGET_OS_OSX|TARGET_OS_TV|__APPLE__|TARGET_IOS` (34 matches):
- `Source/ee/EeExecutor.cpp:12-37` — `TargetConditionals.h`, `TARGET_CPU_ARM64` → `STATE_FLAVOR ARM_THREAD_STATE64`, and `#if TARGET_OS_TV` disables memory protection.
- `Source/ee/EeExecutor.cpp:83-128` — **Mach exception port** based handler (`mach_port_allocate`, `thread_set_exception_ports`, `EXC_MASK_BAD_ACCESS`) for the guest-RAM write-protection fault path, with a dedicated handler thread (`HandlerThreadProc`, `:312-378`). This is per-thread and Apple-specific.
- `Source/FpUtils.cpp:6-19` — `TARGET_CPU_ARM64` → `DENORM_AARCH64`; `:34-43` uses inline AArch64 asm to set the FPCR flush-to-zero bit:
  ```cpp
  #ifdef DENORM_AARCH64
  	static const uint64 fpcrFZ = (1 << 24);
  	__asm__ __volatile__(
  	    "mrs x0, fpcr\n"
  	    "orr x0, x0, %0\n"
  	    "msr fpcr, x0\n"
  	    : : "ri"(fpcrFZ) : "x0");
  #endif
  ```
- `Source/gs/GSH_Vulkan/GSH_Vulkan.cpp:88-94` — MoltenVK iOS/macOS surface extensions.
- `Source/Posix_VolumeStream.cpp:8,27`, `Source/DiskUtils.cpp:33,269`, `Source/FrameLimiter.cpp:62`.
- macOS entitlements: `installer_macos/Play.entitlements:5-6` — `<key>com.apple.security.cs.allow-jit</key><true/>`.

### 7.3 Prior iOS port: YES — this is not a greenfield port

There is a **complete, shipping iOS frontend** at `Source/ui_ios/` (36 files, ~1,652 lines) with `installer_ios/build_ipa.sh`, `build_cydia.sh`, and CI (`.github/workflows/build-ios.yaml`). Key facts:
- Toolchain: `deps/Dependencies/cmake-ios/ios.cmake` sets `IPHONEOS_DEPLOYMENT_TARGET 12.2` and, for device builds, `set(IOS_ARCH "arm64")` — **iOS device builds are already arm64**.
- `Source/ui_ios/Info.plist.in:31-35` declares `UIRequiredDeviceCapabilities` = `opengles-3`, `armv7` (**stale**: the actual arch is arm64 now).
- App identifier `com.virtualapplications.play` (`Source/ui_ios/CMakeLists.txt:179`); `XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"` (`:186`) — **already iPhone+iPad**.
- Full ObjC UI, virtual on-screen controls (`VirtualPadView.mm`, `VirtualPadStick.mm`), GameController integration, cover-art library browser, settings, save-state UI.
- **There is no `.entitlements` file for iOS** — only `installer_macos/Play.entitlements`. The iOS build is signed ad-hoc in CI: `codesign -s "-" Source/ui_ios/Release-iphoneos/Play.app` (`.github/workflows/build-ios.yaml:41`), and distributes via IPA + Cydia `.deb`. That is the signature of an app that **cannot pass App Store review** in its current JIT-dependent form.

So: iPadOS is not an unproven target for the *platform* layer — it is a proven target that is fundamentally blocked on the *JIT entitlement*, and distributed outside the App Store.

### 7.4 SIMD usage that could block arm64 compilation: **none found — properly guarded** ✅

Grep for `emmintrin.h|xmmintrin.h|immintrin.h|smmintrin.h|__m128|__m256|_mm_` across the repo yielded exactly **three files**, and **all three are behind a portable feature macro**, not raw x86 assumptions:

1. **`Source/ee/Vif.h:14-16`** — guarded:
   ```cpp
   #ifdef FRAMEWORK_SIMD_USE_SSE
   #include <emmintrin.h>
   #endif
   ```
   with the `__m128i` use at `:601` inside the same guard (via `SimdDefs.h`, `:12`).

2. **`Source/FpUtils.cpp:21-24`** — guarded by the locally-computed `DENORM_X86`, which is arm64-excluded, **and there is an explicit AArch64 alternative** (§7.2):
   ```cpp
   #ifdef DENORM_X86
   #include <xmmintrin.h>
   #include <pmmintrin.h>
   #endif
   ```

3. **`Source/gs/GSH_OpenGL/GSH_OpenGL_Texture.cpp:352-355`** — guarded:
   ```cpp
   #if defined(FRAMEWORK_SIMD_USE_SSE)
   #include <xmmintrin.h>
   #include <emmintrin.h>
   #include <tmmintrin.h>
   ```

Correspondingly, SSE compiler flags are added **only for x86 UNIX** and explicitly excluded for both ARM variants — `Source/CMakeLists.txt:34-36`:
```cmake
if(TARGET_PLATFORM_UNIX AND NOT TARGET_PLATFORM_UNIX_ARM AND NOT TARGET_PLATFORM_UNIX_AARCH64)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -msse -msse2 -mssse3")
endif()
```
and `Source/gs/GSH_OpenGL/CMakeLists.txt:21-27` mirrors this (ARM gets `-mfpu=neon` instead).

**Conclusion: the SIMD question is a non-issue.** `FRAMEWORK_SIMD_USE_SSE` is defined by the Framework submodule's `SimdDefs.h` per-architecture (that header is in `deps/Framework`, absent locally — I verified the *guards* and the *absence of unguarded intrinsics* in the main tree, but I did not read `SimdDefs.h` itself; `FRAMEWORK_SIMD_USE_*` naming and the arm32 CMake branch strongly imply an ARM/NEON counterpart, but I did **not** confirm a NEON path exists. **Partially unverified.**) Since these are all optional fast paths with C++ fallbacks, an unguarded-SSE compile failure on arm64 is not a realistic risk.

### 7.5 Other arm64-relevant items
- `tools/PsfPlayer/Source/ui_aot/Main_Aot.cpp:264` — `cpuArch = Jitter::CObjectFile::CPU_ARCH_ARM64;` proves the AOT object-file emitter has an arm64 path (§4.6).
- Android ships `arm64-v8a` (`build_android/build.gradle:55`), and Linux arm32/arm64 CI exists (`.github/workflows/build-linux_arm32.yaml`, `build-linux_arm64.yaml`) — so the AArch64 backend is exercised on non-Apple platforms too.

---

## 8. ROUGH SIZE METRICS

Measured with PowerShell over `Source/`, counting `*.cpp,*.h,*.mm,*.m` and summing physical lines.

| Scope | Files | Lines |
|---|---|---|
| **Core emulation (`Source/` minus `ui_*`)** | **472** | **91,993** |
| All of `Source/` (incl. all frontends) | 721 | 115,682 |

**Top-level `Source/` directories, with purpose:**

| Directory | Files | Lines | Purpose |
|---|---|---|---|
| `ee/` | 71 | 26,418 | Emotion Engine: EE MIPS IV arch (`MA_EE`), VU arch (`MA_VU` upper/lower), COP_FPU/COP_SCU/COP_VU, VIF0/VIF1, GIF, IPU (MPEG-2), DMAC, INTC, timers, SIF, PS2OS (HLE BIOS/kernel), EE + VU executors |
| `iop/` | 156 | 27,619 | I/O Processor (MIPS R3000): HLE kernel modules (`Iop_*`), ioman devices, SIF, SPU2, CDVD, USB, memory cards, plus Namco System 246/147 arcade IOP hardware |
| `gs/` | 51 | 18,339 | Graphics Synthesizer: `GSHandler` core, `GsPixelFormats`, cached-area/transfer logic, texture cache, and the GSH_* rendering backends |
| `ui_qt/` | 159 | 14,242 | Qt6/Qt5 desktop frontend (Windows/macOS/Linux) + debugger UI + frame debugger |
| `ui_libretro/` | 8 | 4,784 | libretro core frontend (dominated by the vendored `ext/libretro.h` API header) |
| `ui_shared/` | 20 | 1,666 | Frontend-shared: game-library scanning, bootables DB, arcade defs/drivers, TheGamesDB & S3 clients, stats |
| `ui_ios/` | 36 | 1,652 | **Existing iPadOS/iPhone ObjC frontend** + AltServer JIT service + virtual pad |
| `psx/` | 2 | 1,290 | PS1 BIOS HLE shim (PS2 runs PS1 games in PS1 mode) |
| `saves/` | 22 | 1,215 | Memory card images & save importers (Max, PSU, XPS, Mcd) |
| `discimages/` | 16 | 1,213 | Disc image containers: CHD, CSO, ISZ, MDS, cue sheets |
| `ui_android/` | 19 | 985 | Android frontend (Java + JNI + Vulkan/OpenGL ES glue) |
| `input/` | 5 | 944 | Input binding manager & generic provider |
| `ISO9660/` | 13 | 578 | ISO9660 filesystem parsing |
| `sound/` | 9 | 547 | Sound handler interface + OpenAL / WaveOut / XAudio2 backends |
| `hdd/` | 7 | 505 | PS2 HDD: APA partitioning & PFS filesystem readers |
| `states/` | 11 | 370 | Save-state serialization (zip/XML/register-state files) |
| `ui_js/` | 7 | 360 | Emscripten/WASM frontend |
| `s3stream/` | 2 | 223 | Amazon S3 disc-image streaming (optional) |
| `app_shared/` | 5 | 138 | `AppConfig` preferences + `Log` |

Plus ~100 files at the `Source/` root level (MIPS core, block/JIT scaffolding, PS2VM, ELF, memory map, etc.) — these were **not** separately counted because my first PowerShell pass mis-globbed `-Include` on a non-recursive `Get-ChildItem`; the 91,993 figure above **does** include them (it was computed recursively). Files of note at that level: `PS2VM.cpp/.h`, `MIPS.cpp/.h`, `MipsJitter.cpp/.h`, `BasicBlock.cpp/.h`, `GenericMipsExecutor.h`, `MA_MIPSIV*.cpp`, `MemoryMap.cpp`, `ElfFile.cpp`, `ScreenShotUtils.cpp`.

**Interpretation:** ~92k lines of core C++ is a mid-size emulator codebase. The `ee/` + `iop/` + `gs/` triad (72,376 lines, 79% of core) is the irreducible porting surface.

---

## 9. SUMMARY FOR THE FEASIBILITY STUDY

**Favourable findings**
1. **BSD-2-Clause, no copyleft, no per-file restrictions** — no licensing barrier to a commercial or App Store iPadOS app (§1.1).
2. **A real arm64 dynarec already exists** (`Jitter::CCodeGen_AArch64`) and is exercised natively on Apple Silicon via universal macOS builds (§3.3, §7.2).
3. **An iOS frontend already exists and ships** — arm64 device builds, iPad device family, virtual pad, ObjC UI, IPA/Cydia packaging (§7.3).
4. **The iOS executable-memory path is already W^X-compliant** — single `vm_allocate` mapping alternating R|X ↔ R|W via `vm_protect`, never RWX (§4.3–4.4). No dual-mapping or RWX hardening problem to fix.
5. **SIMD is not a porting blocker** — all SSE intrinsics sit behind `FRAMEWORK_SIMD_USE_SSE`, and arm64 already has a dedicated FPCR flush-to-zero path (§7.4).
6. **Clean core/frontend separation** — `PlayCore` is a static library with a small, injectable API (`CPS2VM`), and the iOS CMake project already enables Swift (§6).

**Blocking findings**
1. **Play! has no interpreter. At all.** ~92k lines of core C++ with exactly one execution path: generated native code, called via `m_function(&m_context)` (§3.5, §3.1). There is nothing to fall back to.
2. **Without executable-memory permission, the emulator cannot run — by construction, not by misconfiguration.** `vm_protect(..., VM_PROT_EXECUTE)` will fail and `assert(result == 0)` will abort. Play!'s README says the app *will crash* (§4.5).
3. **The JIT is not merely write-once.** Block linking rewrites raw pointers *into already-executable code* at runtime (`LinkBlock` → `BeginModify`/`EndModify`, §4.2), so an immutable-code design would also break block chaining, not just compilation.
4. **The iOS build is ad-hoc signed and distributed outside the App Store** (`codesign -s "-"`, IPA + Cydia `.deb`, plus jailbreak/debugger/AltServer JIT activation). Current form is **not App-Store-viable** (§4.5, §7.3).
5. **No software rasterizer and no Metal backend.** Backends are OpenGL ES (deprecated) and Vulkan-via-MoltenVK (§5.1–5.2). A native Metal path would require a new Nuanceur shader generator.

**The one open avenue, explicitly unproven:** the AOT block cache (`AOT_USE_CACHE` / `AOT_BUILD_CACHE`, `Source/BasicBlock.cpp:25-41,150-174`, `tools/PsfPlayer/Source/ui_aot/Main_Aot.cpp:264` `CPU_ARCH_ARM64`) compiles basic blocks offline into object files and at runtime only resolves function pointers — no runtime codegen. It is currently `OFF` by default and documented as "for PsfPlayer only". **I did not verify coverage, correctness, or feasibility for the full EE+VU+GS workload under a no-JIT iPadOS constraint. This should be the focus of any follow-up investigation.** Whether the resulting code pages must themselves be executable (they are, being part of the signed binary) and whether Apple would accept that arrangement are separate questions I cannot answer from source inspection alone.

**Items I could NOT determine (stated explicitly)**
- Licenses of `deps/Framework`, `deps/Nuanceur`, `deps/libchdr`, `deps/AltKit` — directories empty, not fetched.
- Licenses of most vendored `deps/Dependencies` components (bzip2, zlib, zstd, xxHash, glew, sqlite, lzma, nlohmann_json, SDWebImage, iCade, `tdemu-1.10`, `unrarsrc-5.2.5`) — only the *directory listing* was retrieved, not license files. The UnRAR entry in particular warrants a licensing review if PsfPlayer is ever enabled.
- The contents of `deps/Framework/include/SimdDefs.h`, which defines `FRAMEWORK_SIMD_USE_SSE` and any ARM/NEON counterpart. I verified the *guards* in the main tree, not the macro's definition.
- Actual App Store / entitlement policy outcomes — out of scope for source inspection.
- The practical performance and completeness of the AOT path (see above).
