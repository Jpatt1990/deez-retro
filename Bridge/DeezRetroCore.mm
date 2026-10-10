//
//  DeezRetroCore.mm
//  Deez Retro
//
//  Objective-C++ implementation of the engine facade for Flycast (Dreamcast).
//
//  Phase 2 scope: Dreamcast only, interpreter-only (TARGET_NO_REC), no JIT, no
//  entitlements. PlayStation 2 is suspended and is never reported as linked.
//
//  DESIGN NOTES
//  ------------
//  * Flycast exposes an embeddable API in core/emulator.h (flycast_init,
//    flycast_term, `extern Emulator emu`, dc_savestate/dc_loadstate) plus a
//    frame pump in core/ui/mainui.h (mainui_init / mainui_rend_frame /
//    mainui_term). We consume exactly those; no engine internals are reached
//    into. See docs/PHASE2-IOS-INTEGRATION.md for the full contract.
//
//  * The engine is only compiled in when DEEZRETRO_HAVE_FLYCAST is defined by
//    the build. Until then every entry point degrades to a reported
//    "engine not linked" state rather than a link error, so the Xcode project
//    builds and launches before the engine submodule is wired in.
//
//  * Execution mode is OBSERVED, never guessed. A TARGET_NO_REC build reports
//    interpreter because core/build.h set FEAT_SHREC to DYNAREC_NONE at compile
//    time, and that is read back here with the preprocessor.
//
//  * Nothing here claims the emulator works. It has not been compiled for iOS
//    or run on a device. See docs/PHASE2-BUILD-REPORT.md.
//

#import "DeezRetroCore.h"

#import <QuartzCore/QuartzCore.h>   // CACurrentMediaTime()
#import <UIKit/UIKit.h>             // UIScreen, AVAudioSession host
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>

#include <string>
#include <vector>

#if DEEZRETRO_HAVE_FLYCAST
// Exactly the include set Flycast's own iOS view controller uses
// (shell/apple/emulator-ios/emulator/FlycastViewController.mm:35-46).
#include "types.h"
#include "wsi/context.h"        // initRenderApi()
#include "ui/mainui.h"          // mainui_init / mainui_rend_frame / mainui_term
#include "emulator.h"           // flycast_init / Emulator emu / dc_*
#include "log/LogManager.h"
#include "stdclass.h"
#include "cfg/option.h"         // config::*, settings.display
#include "oslib/oslib.h"        // set_user_config_dir, os_InstallFaultHandler
#include "oslib/i18n.h"
#include "build.h"              // FEAT_SHREC / DYNAREC_NONE

// The iOS input layer. Header-only; these are the same headers the upstream
// shell uses, which is how DualSense support comes for free.
#include "ios_gamepad.h"
#include "ios_keyboard.h"
#include "ios_mouse.h"
#endif

#pragma mark - JIT capability state

// Set true once an out-of-band JIT acquisition path has succeeded
// (see JIT/JITAcquisition.swift). Read by the engine promotion logic.
static BOOL gJITAcquired = NO;

BOOL DRCoreDynarecUsable(void)
{
    return gJITAcquired ? YES : NO;
}

void DRCoreNotifyJITAcquired(void)
{
    gJITAcquired = YES;
#if DEEZRETRO_HAVE_FLYCAST
#if FEAT_SHREC != DYNAREC_NONE
    // Flycast selects the SH4 executor at runtime from config::DynarecEnabled
    // (core/emulator.cpp getSh4Executor()). Upstream's iOS shell never wires its
    // JIT authorization state into this option - it only displays it - so a
    // JIT-denied device still tries the recompiler and fails in executable-memory
    // allocation instead of degrading. We do it properly.
    //
    // Only meaningful before the game starts; a running game keeps its executor.
    config::DynarecEnabled.override(true);
#endif
#endif
}

#pragma mark - DRCoreStatus

@interface DRCoreStatus ()
@property (nonatomic, readwrite) DREngine engine;
@property (nonatomic, readwrite) DREngineState state;
@property (nonatomic, readwrite) DRExecutionMode executionMode;
@property (nonatomic, readwrite, copy) NSString *executionModeDetail;
@property (nonatomic, readwrite) BOOL engineLinked;
@property (nonatomic, readwrite) BOOL gameLoaded;
@property (nonatomic, readwrite) BOOL builtWithoutRecompiler;
@property (nonatomic, readwrite, copy) NSString *rendererName;
@end

@implementation DRCoreStatus
@end

#pragma mark - DRCore

@interface DRCore ()
- (void)installEventHooks;
- (void)configureAudioSession;
- (void)installInputObservers;
- (void)applyScreenMetrics;
@end

@implementation DRCore
{
    DREngine _engine;
    BOOL _initialised;
    BOOL _gameLoaded;
    BOOL _running;
    BOOL _failed;

    // Frame accounting for measuredFPS.
    CFTimeInterval _fpsWindowStart;
    uint64_t       _framesInWindow;
    double         _measuredFPS;

    // Input observer tokens, released on shutdown.
    NSMutableArray<id> *_observers;
}

+ (instancetype)shared
{
    static DRCore *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DRCore alloc] init]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _engine = DREngineDreamcast;
        _observers = [NSMutableArray array];
        _fpsWindowStart = CACurrentMediaTime();
    }
    return self;
}

#pragma mark Capability reporting

- (DRCoreStatus *)statusForEngine:(DREngine)engine
{
    DRCoreStatus *s = [[DRCoreStatus alloc] init];
    s.engine = engine;
    s.gameLoaded = _gameLoaded;

    if (engine == DREnginePS2) {
        // Phase 1 conclusion, still in force: no PS2 engine is integrated and
        // PS2 development is suspended. Never report otherwise.
        s.engineLinked = NO;
        s.rendererName = @"none";
        s.state = DREngineStateNotLinked;
        s.executionMode = DRExecutionModeUnavailable;
        s.executionModeDetail = @"PS2 support suspended (Phase 2 is Dreamcast-only)";
        return s;
    }

#if DEEZRETRO_HAVE_FLYCAST
    s.engineLinked = YES;
    s.rendererName = @"OpenGL ES 3";

    // Compile-time truth: did this build contain a recompiler at all?
#if FEAT_SHREC == DYNAREC_NONE
    s.builtWithoutRecompiler = YES;
    s.executionMode = DRExecutionModeInterpreter;
    s.executionModeDetail = @"Built interpreter-only (TARGET_NO_REC); no JIT required";
#else
    s.builtWithoutRecompiler = NO;
    if (gJITAcquired) {
        s.executionMode = DRExecutionModeDynarec;
        s.executionModeDetail = @"JIT authorized; ARM64 SH4 dynarec active";
    } else {
        s.executionMode = DRExecutionModeInterpreter;
        s.executionModeDetail = @"JIT not authorized; using SH4 interpreter";
    }
#endif

    if (_failed)          s.state = DREngineStateFailed;
    else if (_running)    s.state = DREngineStateRunning;
    else if (_gameLoaded) s.state = DREngineStatePaused;
    else if (_initialised) s.state = DREngineStateIdle;
    else                  s.state = DREngineStateNotLinked;
#else
    s.engineLinked = NO;
    s.rendererName = @"none";
    s.state = DREngineStateNotLinked;
    s.executionMode = DRExecutionModeUnavailable;
    s.executionModeDetail = @"Flycast not linked into this build "
                            @"(build with DEEZRETRO_HAVE_FLYCAST=1)";
#endif
    return s;
}

#pragma mark Lifecycle

- (BOOL)startEngine:(DREngine)engine error:(NSError **)error
{
    if (engine != DREngineDreamcast) {
        if (error) {
            *error = [NSError errorWithDomain:@"DeezRetro" code:1 userInfo:@{
                NSLocalizedDescriptionKey:
                    @"Only the Dreamcast (Flycast) engine is integrated. PS2 is suspended."
            }];
        }
        return NO;
    }
    _engine = engine;

#if DEEZRETRO_HAVE_FLYCAST
    if (_initialised)
        return YES;

    // --- Steps 1-4 of the bring-up sequence (see PHASE2-IOS-INTEGRATION.md §3)
    LogManager::Init();
    i18n::init();

    // Flycast writes config, saves and screenshots under the user directories.
    // These must be set BEFORE flycast_init(), which opens the config there.
    NSArray<NSURL *> *urls =
        [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                               inDomains:NSUserDomainMask];
    if (urls.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DeezRetro" code:7 userInfo:@{
                NSLocalizedDescriptionKey: @"No Documents directory available."
            }];
        }
        return NO;
    }
    std::string homedir = std::string(urls.firstObject.path.UTF8String) + "/";
    set_user_config_dir(homedir);
    set_user_data_dir(homedir);

    os_InstallFaultHandler();

    // --- Step 6. NOTE: zero arguments, as upstream's iOS and Android shells do
    // (FlycastViewController.mm:218, Android.cpp:171). config::parseCommandLine()
    // is the embedded entry point.
    if (flycast_init(0, nullptr) != 0) {
        _failed = YES;
        if (error) {
            *error = [NSError errorWithDomain:@"DeezRetro" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"flycast_init() failed. See the device log."
            }];
        }
        return NO;
    }

    // --- Step 7: where games are discovered.
    config::ContentPath.get().clear();
    config::ContentPath.get().push_back(homedir);

    // --- Step 5: screen metrics, so the renderer sizes its framebuffer correctly.
    [self applyScreenMetrics];

    // --- Step 9/10. A current EAGLContext must already be set by the caller
    // (the GLKView does this in its setup); mainui_init() -> rend_init_renderer()
    // creates the GLES context object and will fail without one.
    initRenderApi();
    mainui_init();

    [self configureAudioSession];
    [self installEventHooks];
    [self installInputObservers];

    _initialised = YES;
    return YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"DeezRetro" code:3 userInfo:@{
            NSLocalizedDescriptionKey:
                @"This build has no emulation engine linked. Build the Flycast "
                @"core library and define DEEZRETRO_HAVE_FLYCAST=1."
        }];
    }
    return NO;
#endif
}

#if DEEZRETRO_HAVE_FLYCAST

- (void)applyScreenMetrics
{
    // Mirrors FlycastViewController.mm:318-326.
    UIScreen *screen = [UIScreen mainScreen];
    settings.display.width  = (int)roundf(screen.nativeBounds.size.width);
    settings.display.height = (int)roundf(screen.nativeBounds.size.height);
    if (settings.display.width < settings.display.height)
        std::swap(settings.display.width, settings.display.height);
    float scale = 1.f;
    if ([screen respondsToSelector:@selector(scale)])
        scale = (float)screen.scale;
    settings.display.dpi = 160.f * scale;
}

- (void)configureAudioSession
{
    // Ported from FlycastViewController.mm:84-145 (updateAudioSession).
    // Category depends on whether the emulated Dreamcast microphone is in use.
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;

    bool micInUse = false;   // Phase 2: microphone input is not wired up yet.

    AVAudioSessionCategoryOptions opts =
          AVAudioSessionCategoryOptionMixWithOthers
        | AVAudioSessionCategoryOptionDefaultToSpeaker
        | AVAudioSessionCategoryOptionAllowBluetooth
        | AVAudioSessionCategoryOptionAllowBluetoothA2DP
        | AVAudioSessionCategoryOptionAllowAirPlay;

    NSString *category = micInUse ? AVAudioSessionCategoryPlayAndRecord
                                  : AVAudioSessionCategoryAmbient;
    if (![session setCategory:category withOptions:opts error:&err])
        NSLog(@"[DeezRetro] AVAudioSession.setCategory failed: %@", err);
    err = nil;
    if (![session setActive:YES error:&err])
        NSLog(@"[DeezRetro] AVAudioSession.setActive failed: %@", err);
}

- (void)installEventHooks
{
    // The engine must re-apply the audio session when it resumes.
    DRCore *strongSelf = self;   // DRCore is a singleton; outlives the engine.
    EventManager::listen(Event::Resume, [](Event, void *param) {
        DRCore *core = (__bridge DRCore *)param;
        [core configureAudioSession];
    }, (__bridge void *)strongSelf);
}

- (void)installInputObservers
{
    // Ported from FlycastViewController.mm:242-295. IOSGamepad/IOSKeyboard/
    // IOSMouse live in the reused iOS headers; they register themselves as
    // Flycast GamepadDevices.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue *main = [NSOperationQueue mainQueue];
    __weak DRCore *weakSelf = self;

    void (^add)(NSNotification *) = ^(NSNotification *note) {
        DRCore *s = weakSelf; if (s == nil) return;
        IOSGamepad::addController((GCController *)note.object);
    };
    void (^remove)(NSNotification *) = ^(NSNotification *note) {
        DRCore *s = weakSelf; if (s == nil) return;
        IOSGamepad::removeController((GCController *)note.object);
    };

    [_observers addObject:[nc addObserverForName:GCControllerDidConnectNotification
                                          object:nil queue:main usingBlock:add]];
    [_observers addObject:[nc addObserverForName:GCControllerDidDisconnectNotification
                                          object:nil queue:main usingBlock:remove]];

    // Controllers already connected before we started observing.
    for (GCController *controller in [GCController controllers])
        IOSGamepad::addController(controller);

    if (@available(iOS 14.0, *)) {
        [_observers addObject:[nc addObserverForName:GCKeyboardDidConnectNotification
            object:nil queue:main usingBlock:^(NSNotification *note) {
                IOSKeyboard::addKeyboard((GCKeyboard *)note.object);
        }]];
        [_observers addObject:[nc addObserverForName:GCKeyboardDidDisconnectNotification
            object:nil queue:main usingBlock:^(NSNotification *note) {
                IOSKeyboard::removeKeyboard((GCKeyboard *)note.object);
        }]];
        [_observers addObject:[nc addObserverForName:GCMouseDidConnectNotification
            object:nil queue:main usingBlock:^(NSNotification *note) {
                IOSMouse::addMouse((GCMouse *)note.object);
        }]];
        [_observers addObject:[nc addObserverForName:GCMouseDidDisconnectNotification
            object:nil queue:main usingBlock:^(NSNotification *note) {
                IOSMouse::removeMouse((GCMouse *)note.object);
        }]];
    }
}
#endif  // DEEZRETRO_HAVE_FLYCAST

- (BOOL)renderFrame
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_initialised)
        return NO;

    // mainui_rend_frame() pumps os_DoEvents(), os_UpdateInputState(), the ImGui
    // overlay and emu.render(). Calling emu.render() directly would skip all of
    // that plus the renderer-error recovery path (mainui.cpp:60-77).
    bool rendered = mainui_rend_frame();

    if (rendered) {
        _framesInWindow++;
        CFTimeInterval now = CACurrentMediaTime();
        CFTimeInterval elapsed = now - _fpsWindowStart;
        if (elapsed >= 1.0) {
            _measuredFPS = (double)_framesInWindow / elapsed;
            _framesInWindow = 0;
            _fpsWindowStart = now;
        }
        if ([self.delegate respondsToSelector:@selector(coreDidRenderFrame)])
            [self.delegate coreDidRenderFrame];
    }
    return rendered ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)loadGameAtPath:(NSString *)path error:(NSError **)error
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_initialised && ![self startEngine:DREngineDreamcast error:error])
        return NO;

    // emulator.h: "If a game is already loaded, or the emulator is in the error
    // state, unloadGame() must be called first." Enforce it rather than assume it.
    if (_gameLoaded || _failed) {
        [self stopGame];
        _failed = NO;
    }

    try {
        emu.loadGame(path.fileSystemRepresentation, nullptr);
    } catch (const std::exception &e) {
        _failed = YES;
        if (error) {
            *error = [NSError errorWithDomain:@"DeezRetro" code:4 userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Failed to load game: %s", e.what()]
            }];
        }
        return NO;
    } catch (...) {
        _failed = YES;
        if (error) {
            *error = [NSError errorWithDomain:@"DeezRetro" code:4 userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to load game (unknown exception)."
            }];
        }
        return NO;
    }
    _gameLoaded = YES;
    return YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"DeezRetro" code:3 userInfo:@{
            NSLocalizedDescriptionKey: @"No engine linked; cannot load a game."
        }];
    }
    return NO;
#endif
}

- (void)start
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_initialised || !_gameLoaded || _running)
        return;
    emu.start();
    _running = YES;
    _fpsWindowStart = CACurrentMediaTime();
    _framesInWindow = 0;
    if ([self.delegate respondsToSelector:@selector(coreDidStart:)])
        [self.delegate coreDidStart:_engine];
#endif
}

- (void)pause
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_running)
        return;
    emu.stop();
    _running = NO;
    if ([self.delegate respondsToSelector:@selector(coreDidStop:)])
        [self.delegate coreDidStop:_engine];
#endif
}

- (void)stopGame
{
#if DEEZRETRO_HAVE_FLYCAST
    if (_running) {
        emu.stop();
        _running = NO;
    }
    if (_gameLoaded) {
        emu.unloadGame();
        _gameLoaded = NO;
    }
    _measuredFPS = 0;
#endif
}

- (void)shutdown
{
#if DEEZRETRO_HAVE_FLYCAST
    [self stopGame];
    if (_initialised) {
        // Step 13 of the bring-up sequence.
        mainui_term();
        flycast_term();
        _initialised = NO;
    }
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (id token in _observers)
        [nc removeObserver:token];
    [_observers removeAllObjects];
#endif
}

#pragma mark Save states

- (BOOL)saveStateToSlot:(NSInteger)slot error:(NSError **)error
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_gameLoaded) {
        if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:5 userInfo:@{
            NSLocalizedDescriptionKey: @"No game loaded; nothing to save." }];
        return NO;
    }
    if (slot < 0) {
        if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:8 userInfo:@{
            NSLocalizedDescriptionKey: @"Save-state slot must not be negative." }];
        return NO;
    }
    if (!dc_savestateAllowed()) {
        if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:6 userInfo:@{
            NSLocalizedDescriptionKey: @"Save states are not allowed right now." }];
        return NO;
    }
    dc_savestate((int)slot);
    return YES;
#else
    if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:3 userInfo:@{
        NSLocalizedDescriptionKey: @"No engine linked." }];
    return NO;
#endif
}

- (BOOL)loadStateFromSlot:(NSInteger)slot error:(NSError **)error
{
#if DEEZRETRO_HAVE_FLYCAST
    if (!_gameLoaded) {
        if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:5 userInfo:@{
            NSLocalizedDescriptionKey: @"No game loaded; nothing to load." }];
        return NO;
    }
    if (slot < 0) {
        if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:8 userInfo:@{
            NSLocalizedDescriptionKey: @"Save-state slot must not be negative." }];
        return NO;
    }
    dc_loadstate((int)slot);
    return YES;
#else
    if (error) *error = [NSError errorWithDomain:@"DeezRetro" code:3 userInfo:@{
        NSLocalizedDescriptionKey: @"No engine linked." }];
    return NO;
#endif
}

- (double)measuredFPS
{
    return _measuredFPS;
}

@end
