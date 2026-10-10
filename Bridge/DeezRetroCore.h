//
//  DeezRetroCore.h
//  Deez Retro
//
//  Objective-C facade over the C/C++ emulation engines.
//  Everything that touches a C++ emulator core goes through this header.
//  The implementation (DeezRetroCore.mm) is Objective-C++.
//
//  This file is deliberately C/ObjC-only in its interface so Swift can consume
//  it through DeezRetro-Bridging-Header.h without importing any C++.
//
//  Phase 2 scope: Sega Dreamcast only (Flycast). PlayStation 2 is suspended.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Which emulation engine a session is running.
/// Only these two consoles are in scope for Deez Retro; PS2 is suspended.
typedef NS_ENUM(NSInteger, DREngine) {
    DREngineDreamcast = 0,  // Flycast
    DREnginePS2       = 1,  // suspended - not integrated, never reports as linked
};

/// CPU execution mode actually in use.
/// This is *reported*, not guessed: it reflects how the engine was compiled and
/// whether a dynarec could obtain executable memory.
typedef NS_ENUM(NSInteger, DRExecutionMode) {
    DRExecutionModeUnknown     = 0,
    DRExecutionModeDynarec     = 1,  // JIT recompiler active
    DRExecutionModeInterpreter = 2,  // no JIT; pure interpreter fallback
    DRExecutionModeUnavailable = 3,  // engine not linked into this build
};

/// Where the engine is in its lifecycle. Phase 2 needs this to be explicit
/// because "engine initialised" and "game running" are very different states,
/// and a bring-up build must never blur them.
typedef NS_ENUM(NSInteger, DREngineState) {
    DREngineStateNotLinked = 0,
    DREngineStateIdle      = 1,  // core initialised, renderer up, no game
    DREngineStateRunning   = 2,  // game executing
    DREngineStatePaused    = 3,
    DREngineStateFailed    = 4,
};

/// A plain snapshot of engine + platform capability, safe to cross into Swift.
@interface DRCoreStatus : NSObject
@property (nonatomic, readonly) DREngine engine;
@property (nonatomic, readonly) DREngineState state;
@property (nonatomic, readonly) DRExecutionMode executionMode;
/// Human-readable reason for the current execution mode
/// (e.g. "compiled interpreter-only (TARGET_NO_REC)").
@property (nonatomic, readonly, copy) NSString *executionModeDetail;
/// Whether the engine binary is actually linked into this build.
@property (nonatomic, readonly) BOOL engineLinked;
/// Whether a game is currently loaded.
@property (nonatomic, readonly) BOOL gameLoaded;
/// Whether the core was built interpreter-only.
@property (nonatomic, readonly) BOOL builtWithoutRecompiler;
/// Renderer in use, e.g. "OpenGL ES 3" / "Vulkan" / "none".
@property (nonatomic, readonly, copy) NSString *rendererName;
@end

/// Delegate for engine lifecycle callbacks.
@protocol DRCoreDelegate <NSObject>
@optional
- (void)coreDidStart:(DREngine)engine;
- (void)coreDidStop:(DREngine)engine;
- (void)coreDidFailWithMessage:(NSString *)message;
/// Called once per rendered frame. Use for FPS accounting / frame pacing.
- (void)coreDidRenderFrame;
@end

/// The single entry point the SwiftUI layer talks to.
@interface DRCore : NSObject

+ (instancetype)shared;

@property (nonatomic, weak, nullable) id<DRCoreDelegate> delegate;

/// Capability probe. Safe to call at any time, including before the engine is
/// initialised and when no engine is linked at all.
- (DRCoreStatus *)statusForEngine:(DREngine)engine;

/// Initialises the core *and* brings up the renderer.
///
/// This is the whole of the iOS bring-up sequence, in order:
///   set_user_config_dir / set_user_data_dir
///   flycast_init(0, nullptr)   -> addrspace::reserve, config::open, gui_init,
///                                 os_CreateWindow, os_SetupInput
///   config::ContentPath
///   initRenderApi()
///   mainui_init()              -> rend_init_renderer()
/// A current EAGLContext must already be set by the caller (the GLKView does
/// this), because mainui_init() creates the GLES context object.
- (BOOL)startEngine:(DREngine)engine error:(NSError **)error;

/// Loads a disc image / homebrew binary from a filesystem path.
/// Accepts .gdi, .chd, .cdi, .cue and .elf.
- (BOOL)loadGameAtPath:(NSString *)path error:(NSError **)error;

/// Advances the emulator by one frame. Must be called on the thread that owns
/// the GL context, once per display refresh.
///
/// Maps to mainui_rend_frame() (core/ui/mainui.cpp), NOT emu.render() directly:
/// mainui_rend_frame() also pumps os_DoEvents(), os_UpdateInputState() and the
/// ImGui overlay. Returns NO if no frame was produced.
- (BOOL)renderFrame;

- (void)start;   // begin executing
- (void)pause;   // stop executing, keep the game loaded
- (void)stopGame;
- (void)shutdown;

/// Save states. Negative slot values are rejected.
- (BOOL)saveStateToSlot:(NSInteger)slot error:(NSError **)error;
- (BOOL)loadStateFromSlot:(NSInteger)slot error:(NSError **)error;

/// Most recent measured frames per second, or 0 if not running.
@property (nonatomic, readonly) double measuredFPS;

@end

/// Exposed for the JIT acquisition layer: reports whether the dynarec can be
/// used. This is a pure capability query and never triggers acquisition.
FOUNDATION_EXPORT BOOL DRCoreDynarecUsable(void);

/// Called after JIT has been acquired out-of-band (StikDebug / StikJIT /
/// debugger attach) so the engine can promote itself from interpreter to
/// dynarec. Only meaningful for a build that actually contains a recompiler;
/// a TARGET_NO_REC build ignores it and DRCoreStatus will keep reporting
/// DRExecutionModeInterpreter.
FOUNDATION_EXPORT void DRCoreNotifyJITAcquired(void);

NS_ASSUME_NONNULL_END
