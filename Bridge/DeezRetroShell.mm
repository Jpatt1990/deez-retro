//
//  DeezRetroShell.mm
//  Deez Retro
//
//  Host-platform glue for Flycast on iPadOS.
//
//  WHY THIS FILE IS NECESSARY
//  --------------------------
//  Flycast's `core/` is *not* self-contained for iOS: a small set of symbols is
//  declared or referenced by the core but defined only in the iOS shell at
//  `shell/apple/emulator-ios/emulator/ios_main.mm` and
//  `shell/apple/emulator-ios/emulator/FlycastViewController.mm`.
//
//  Deez Retro excludes that shell (it is a UIKit app with storyboards, not a
//  library), so these definitions must be supplied here. This file is the entire
//  cost of not reusing Flycast's frontend. Missing any one of them is a link
//  error, so they are enumerated explicitly.
//
//  Symbol                                        Declared/referenced in core
//  --------------------------------------------  ------------------------------------------
//  1. darw_printf(const char*, ...)               core/types.h:55 (#if __APPLE__)
//  2. os_DoEvents()                               core/oslib/oslib.h:8, called from
//                                                 core/ui/mainui.cpp:42
//  3. os_PrecomposedString(std::string)           core/oslib/storage.cpp:26 (declared),
//                                                 called at storage.cpp:91
//  4. hostfs::saveScreenshot(name, data)          core/oslib/oslib.cpp:404 explicitly
//                                                 compiles this OUT on TARGET_IPHONE;
//                                                 referenced by core/ui/gui.cpp:1690 and
//                                                 core/hw/naomi/printer.cpp:396,410
//  5. IOSGamepad::controllers                     defined only in
//  6. IOSKeyboard::keyboards                      FlycastViewController.mm:54-56
//  7. IOSMouse::mice                              (static class members need a definition)
//
//  Items 1-4 come from ios_main.mm (60 lines, no UI). Items 5-7 are one-line
//  static member definitions. Reusing ios_main.mm verbatim instead of rewriting
//  it is the recommended path - see docs/PHASE2-IOS-INTEGRATION.md.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <string>
#include <vector>
#include <cstdarg>
#include <cstdio>

#include "types.h"

// ---------------------------------------------------------------------------
// 1-4: mirrors of shell/apple/emulator-ios/emulator/ios_main.mm
// ---------------------------------------------------------------------------

/// Flycast logs through this on Apple platforms (declared in core/types.h:55).
int darw_printf(const char *text, ...)
{
    va_list args;
    char temp[2048];
    va_start(args, text);
    vsnprintf(temp, sizeof(temp), text, args);
    va_end(args);
    NSLog(@"%s", temp);
    return 0;
}

/// The core pumps this once per frame from mainui_rend_frame()
/// (core/ui/mainui.cpp:42). Upstream's iOS implementation is intentionally
/// empty: UIKit runs its own run loop, and Flycast's input is delivered through
/// GameController callbacks rather than a polled event queue.
void os_DoEvents()
{
}

/// Unicode normalisation for on-screen file names. Declared in
/// core/oslib/storage.cpp:26 and called at :91 ("For macOS").
std::string os_PrecomposedString(std::string string)
{
    return [[[NSString stringWithUTF8String:string.c_str()] precomposedStringWithCanonicalMapping] UTF8String];
}

/// Screenshots. The core explicitly does NOT provide this on iOS
/// (core/oslib/oslib.cpp:404 excludes TARGET_IPHONE), because saving to the
/// Photos library needs UIKit.
namespace hostfs
{
void saveScreenshot(const std::string &name, const std::vector<u8> &data)
{
    if (data.empty())
        return;
    NSData *imageData = [NSData dataWithBytes:data.data() length:data.size()];
    UIImage *pngImage = [UIImage imageWithData:imageData];
    if (pngImage != nil)
        UIImageWriteToSavedPhotosAlbum(pngImage, nil, nil, nil);
}
} // namespace hostfs

// ---------------------------------------------------------------------------
// 5-7: static member definitions.
//
// These are declared `static` inside their classes in the iOS headers, so each
// needs exactly one definition in a translation unit. Upstream puts them in
// FlycastViewController.mm:54-56. `static` here is class-scope, not internal
// linkage, so duplicates would be an ODR violation.
//
// Only compiled when the iOS input headers are in the build. They pull in
// GameController and the whole Flycast input stack, so they are opt-in via
// DEEZRETRO_HAVE_FLYCAST to keep the app buildable before the engine links.
// ---------------------------------------------------------------------------

#if DEEZRETRO_HAVE_FLYCAST
#include "ios_gamepad.h"
#include "ios_keyboard.h"
#include "ios_mouse.h"

std::map<GCController *, std::shared_ptr<IOSGamepad>> IOSGamepad::controllers;
std::map<GCKeyboard *, std::shared_ptr<IOSKeyboard>> IOSKeyboard::keyboards;
std::map<GCMouse *, std::shared_ptr<IOSMouse>> IOSMouse::mice;
#endif
