# Phase 2 — Flycast ↔ iPadOS integration contract

**Purpose.** This is the precise list of things that must be true for Flycast's
`core/` to link into a SwiftUI app on iPadOS, derived by reading the pinned SHA
`ed953fcb` directly. It answers Phase 2 step 1 (frontend reuse) and supplies the
concrete contents of steps 3–6.

Everything here is source-derived. **None of it has been compiled for iOS** —
see `docs/PHASE2-BUILD-REPORT.md` for what actually was compiled and on what.

---

## 1. Should the existing UIKit frontend be reused?

**Partly. Four things are worth reusing; the rest must be replaced.**

`shell/apple/emulator-ios/` is ~20 files. Classified by what it actually does:

| File | Lines | Reuse? | Why |
|---|---|---|---|
| `ios_main.mm` | 60 | **Yes, verbatim** | Pure host glue, no UI. Supplies 4 symbols the core requires (below). Reimplementing it means reimplementing Photo-library screenshot saving and Unicode normalisation for no benefit. |
| `ios_gamepad.h` | 526 | **Yes** | Header-only. Uses `GameController`; already maps `GCInputDualShockTouchpadButton`, the Xbox paddles, and `CHHapticEngine`. Reusing this is how the DualSense requirement is met. |
| `ios_keyboard.h`, `ios_mouse.h` | — | **Yes** | Header-only, register with Flycast's input layer. |
| `EmulatorView.h/.mm` | 73 | **No** | A `GLKView` subclass adding touch→`TouchMouse`. Reusable in principle, but taking it would put `shell/apple/emulator-ios/emulator/` on the Swift bridging-header path and make the app target depend on the engine checkout even when `DEEZRETRO_HAVE_FLYCAST=0`. Phase 2 wraps a plain `GLKView` instead; the only loss is touch-as-mouse, which is a follow-up. `App/EmulatorHostView.swift` explains why a plain GLKView suffices. |
| `FlycastViewController.mm` | 789 | **No, but mine it** | A `GLKViewController` tied to storyboards. Contains the JIT-detection code (PPSSPP-derived `checkTryDebug()`), the AltKit handoff, the `AVAudioSession` configuration, and the `viewDidLoad` init order. **Port the logic, not the class.** The init order is reproduced in §3 and the audio-session code in §4. |
| `AppDelegate.h/.mm`, `main.m` | — | No | `UIApplicationMain` bootstrap; SwiftUI's `@main` replaces it. |
| `FlycastStoryboard.storyboard`, `LaunchScreen.storyboard`, `*.xib`, `Images.xcassets` | — | No | Storyboard/XIB UI. |
| `PadViewController`, `EditPadViewController` | — | No | On-screen virtual pad UI. |
| `iCade-iOS/` | — | No | iCade Bluetooth keyboard support; obsolete. |
| `AltKit/` | — | Not in Phase 2 | Swift package for AltServer-based JIT. Only needed for Track B (dynarec), not interpreter-only. |
| `flycast.entitlements` | 10 | No | Contains only `get-task-allow`, which the App Store does not grant. |

**Verdict:** reuse `ios_main.mm` and the three header-only input files; replace
the view-controller/storyboard/virtual-pad layer with SwiftUI; port the
`viewDidLoad` logic and the `AVAudioSession` setup into the bridge.

Reusing the input headers is what gets the DualSense mapping (including
`GCInputDualShockTouchpadButton` → `IOS_BTN_TOUCHPAD`) without writing a
controller layer. It does require `shell/apple/emulator-ios/emulator` on the
include path for the bridge's `.mm` files — but only under
`#if DEEZRETRO_HAVE_FLYCAST`, so a build without the engine is unaffected.

---

## 2. The symbol contract: what the core needs that only the shell defines

This is the whole cost of not reusing Flycast's frontend. Each of these is
declared or referenced by `core/`, and defined **only** in the iOS shell. Miss
one and the link fails.

| # | Symbol | Referenced at | Defined by upstream in |
|---|---|---|---|
| 1 | `int darw_printf(const char*, ...)` | `core/types.h:55` (`#if defined(__APPLE__)`) | `ios_main.mm:24` |
| 2 | `void os_DoEvents()` | `core/oslib/oslib.h:8`; called from `core/ui/mainui.cpp:42` | `ios_main.mm:39` (deliberately empty) |
| 3 | `std::string os_PrecomposedString(std::string)` | declared `core/oslib/storage.cpp:26`, called at `:91` | `ios_main.mm:42` |
| 4 | `void hostfs::saveScreenshot(name, data)` | `core/ui/gui.cpp:1690`, `core/hw/naomi/printer.cpp:396,410` | `ios_main.mm:49` |
| 5 | `IOSGamepad::controllers` | static class member | `FlycastViewController.mm:54` |
| 6 | `IOSKeyboard::keyboards` | static class member | `FlycastViewController.mm:55` |
| 7 | `IOSMouse::mice` | static class member | `FlycastViewController.mm:56` |

Two are worth calling out because they are easy to miss:

- **`hostfs::saveScreenshot` is deliberately *not* provided by core on iOS.**
  `core/oslib/oslib.cpp:404` reads:
  ```c
  #if !defined(__ANDROID__) && !defined(TARGET_UWP) && !defined(TARGET_IPHONE) && !defined(__SWITCH__)
  void saveScreenshot(...) { ... }
  #endif
  ```
  `TARGET_IPHONE` is excluded because saving to Photos needs UIKit.

- **Items 5–7 are not functions but static data members.** They are declared
  `static` inside classes in the headers and need exactly one out-of-line
  definition. Upstream puts them in the view controller, so excluding that file
  removes them.

All seven are supplied by `Bridge/DeezRetroShell.mm`.

**Not** required, contrary to a reasonable guess: `os_SetThreadName` and
`http::get`/`http::post`. Those live in `shell/apple/common/util.mm` and
`shell/apple/common/http_client.mm`, which are *shared Apple glue rather than
frontend*, so the Phase 2 patch keeps them in the library build. That is why the
patch excludes only `shell/apple/emulator-ios/**`.

**Also not required:** `main()`. For Apple targets `main()` comes from
`shell/apple/emulator-ios/emulator/main.m` (`UIApplicationMain`), which the
patch excludes. So there is **no duplicate-`main` problem** — a concern raised in
the Phase 1 report that turned out to be wrong.

---

## 3. The bring-up sequence

Reproduced from `FlycastViewController.mm:195-335`, with the shell-specific
parts annotated. Ordering matters: `mainui_init()` creates the GLES context
object, so an `EAGLContext` must already be current before it runs.

```
 1. LogManager::Init()                                  core
 2. i18n::init()                                        core
 3. set_user_config_dir(docsDir)                        core   <- must precede flycast_init
    set_user_data_dir(docsDir)                          core
 4. os_InstallFaultHandler()                            core/linux/common.cpp
 5. settings.display.width/height/dpi from UIScreen     SHELL  <- ported in the bridge
 6. flycast_init(0, nullptr)                            core/nullDC.cpp:69
       -> addrspace::reserve()
       -> config::parseCommandLine()
       -> config::open()          (fails => onboarding UI)
       -> gui_init()
       -> os_CreateWindow()
       -> os_SetupInput()
 7. config::ContentPath.get().clear()                   core
    config::ContentPath.get().push_back(docsDir)        core
 8. EAGLContext(kEAGLRenderingAPIOpenGLES3)             SHELL  <- GLKView provides this
    [EAGLContext setCurrentContext:]                    SHELL
 9. initRenderApi()                                     core/wsi/switcher.cpp:33
       -> selects the renderer; on iOS this is a no-op switch because
          GLGraphicsContext::Create() dispatches to OSXGraphicsContext
10. mainui_init()                                       core/ui/mainui.cpp:83
       -> rend_init_renderer()
11. EventManager::listen(Event::Resume,                 SHELL  <- ported in the bridge
        updateAudioSession)                                    (see §4)

 per frame:
12. mainui_rend_frame()                                 core/ui/mainui.cpp:38
       -> os_DoEvents(); os_UpdateInputState()
       -> if GUI open: gui_display_ui()
          else:        emu.render()
 shutdown:
13. mainui_term(); flycast_term()                       core
```

### Two corrections to the Phase 1 report

1. **Call `flycast_init(0, nullptr)`, not `flycast_init(1, argv)`.** Upstream iOS
   and Android both pass zero arguments (`FlycastViewController.mm:218`,
   `Android.cpp:171`). `config::parseCommandLine(0, nullptr)` is the embedded
   entry, and passing a synthetic `argv` risks mis-parsing options.

2. **Drive frames with `mainui_rend_frame()`, not `emu.render()`.**
   `emu.render()` is called *by* `mainui_rend_frame()` when the overlay is
   closed. Calling it directly would skip `os_DoEvents()`,
   `os_UpdateInputState()`, the ImGui overlay, and the renderer-error recovery
   path (`mainui.cpp:60-77`).

---

## 4. Graphics: why `USE_OPENGL` must stay ON for iOS

This is a real bug in the Phase 1 build script, now fixed.

On iOS, `GLGraphicsContext::Create()` dispatches to `OSXGraphicsContext`
(`core/wsi/gl_context.cpp:105-106`):

```c
#if defined(LIBRETRO)
	LibretroGraphicsContext::Create(window, display);
#elif defined(TARGET_IPHONE)
	OSXGraphicsContext::Create(window, display);
#elif defined(USE_SDL)
	SDLGLGraphicsContext::Create(window, display);
...
```

`OSXGraphicsContext` lives at `core/wsi/osx.cpp`, guarded by
`#if defined(TARGET_IPHONE) && !defined(LIBRETRO)`, and — critically —
`core/wsi/CMakeLists.txt` only compiles `egl.cpp`, `gl_context.cpp`, `osx.cpp`
and `sdl.cpp` **inside `if(USE_OPENGL)`**:

```cmake
if(USE_OPENGL)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_OPENGL)
    target_sources(${PROJECT_NAME} PRIVATE
            egl.cpp egl.h
            gl_context.cpp gl_context.h
            osx.cpp osx.h
            sdl.cpp sdl.h)
endif()
```

So passing `-DUSE_OPENGL=OFF` on iOS (as the Phase 1 script did) removes
`gl_context.cpp` and `osx.cpp` from the build and produces an undefined-symbol
link failure on `GLGraphicsContext::Create`. `USE_OPENGL=ON` on iOS does **not**
mean desktop OpenGL: the platform branch adds `GLES`, `GLES3`,
`HAVE_OPENGLES` and `HAVE_OPENGLES3` (`CMakeLists.txt:313-315`).

Presentation is handled by GLKit: `OSXGraphicsContext::swap()` calls
`do_swap_automation()`, which is a no-op unless `TEST_AUTOMATION` is defined
(`core/wsi/gl_context.h:60-62`). GLKView presents its own drawable after
`glkView:drawInRect:` returns, which is why upstream's iOS code never calls
`imguiDriver->present()`.

---

## 5. Audio

The engine side needs no work. `core/audio/audiobackend_coreaudio.cpp` uses
`AudioUnit` and selects `kAudioUnitSubType_RemoteIO` on iOS (`:89`).

What *does* need porting is the app-side session configuration, from
`FlycastViewController.mm:84-145` (`updateAudioSession`). It is registered on the
`Event::Resume` event and picks between two categories depending on whether the
Dreamcast microphone is in use:

| Mode | `AVAudioSessionCategory` | Options |
|---|---|---|
| Playback only | `AVAudioSessionCategoryAmbient` | MixWithOthers, DefaultToSpeaker, AllowBluetooth, AllowBluetoothA2DP, AllowAirPlay |
| Microphone in use | `AVAudioSessionCategoryPlayAndRecord` | same set |

Both then call `setActive:YES`. Reimplemented in `Bridge/DeezRetroCore.mm`.

---

## 6. Controller input

`ios_gamepad.h` registers each `GCController` as a Flycast `GamepadDevice` port
via `IOSGamepad::addController`. To use it the host must:

1. Observe `GCControllerDidConnectNotification` / `GCControllerDidDisconnectNotification`.
2. Call `IOSGamepad::addController(controller)` /
   `IOSGamepad::removeController(controller)` (see
   `FlycastViewController.mm:276-295`, which also seeds already-connected
   controllers from `[GCController controllers]`).
3. Observe `GCKeyboardDidConnectNotification` / `GCMouseDidConnectNotification`
   for `IOSKeyboard` / `IOSMouse`.

DualSense specifics already handled by the header: `GCInputDualShockTouchpadButton`
→ `IOS_BTN_TOUCHPAD` (`ios_gamepad.h:306-308`), triggers and sticks as
`IOS_AXIS_*`, and `gcController.haptics` → `CHHapticEngine` (`:311-313`).

Port assignment is `gcController.playerIndex = port` for ports 0–3
(`ios_gamepad.h:334-335`).

---

## 7. Game import and launch

Flycast's own content path is used, not a bespoke one:

```
config::ContentPath.get().clear();
config::ContentPath.get().push_back(documentsDir);   // done at bring-up
```

Accepted container types, taken from the shell's exported UTI
(`plist.in:121-128`): `chd`, `gdi`, `cue`, `cdi`. Homebrew `.elf` is also
loadable. Launch is `emu.loadGame(path)` (`core/emulator.h:120`), and the header
documents the constraint that matters for a library frontend:

> *If a game is already loaded, or the emulator is in the error state,
> `unloadGame()` must be called first.*

So the bridge enforces that ordering rather than assuming it.

---

## 8. Minimal CMake invocation for the iOS core library

```bash
cmake -S engines/flycast -B build/flycast-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DDEEZRETRO_CORE_LIBRARY=ON \
  -DDEEZRETRO_NO_REC=ON \
  -DUSE_VULKAN=OFF \
  -DUSE_DX9=OFF -DUSE_DX11=OFF \
  -DUSE_BREAKPAD=OFF -DUSE_DISCORD=OFF -DUSE_LUA=OFF -DUSE_OPENMP=OFF \
  -DUSE_HOST_LIBZIP=OFF -DUSE_HOST_LIBCHDR=OFF -DUSE_LIBCDIO=OFF

cmake --build build/flycast-ios --config Release --target flycast -j $(sysctl -n hw.ncpu)
```

Note what is **absent**: `-DUSE_OPENGL=OFF` must not be there (§4), and there is
no `-DCMAKE_CXX_FLAGS=-DTARGET_NO_REC` because the patch provides
`-DDEEZRETRO_NO_REC=ON` instead.

Frameworks the iOS target needs, taken from Flycast's own link list
(`CMakeLists.txt:1348-1360`): `UIKit`, `Foundation`, `GLKit`, `GameController`,
`AudioToolbox`, `AVFoundation`, plus `OpenGLES` (which upstream only links on the
libretro path, so Deez Retro links it explicitly) and `Security` for the
JIT-entitlement probe.
