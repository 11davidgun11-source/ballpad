// Ballpad's side of the port's host-UI seam (port/hostui.h).
//
// The interface itself is SunPad's, vendored byte-for-byte in interface/sunpad/; this file is the
// adaptation layer that directory's README asks for, and it holds every Ballpad-specific decision:
// where the overlay is attached, how a frame of touch input becomes the port's pad, and what the
// menu's delegate callbacks do here. Keeping those decisions out of the vendored files is what
// makes "SunPad's controls, exactly as they are" a claim a reader can check with a diff.
//
// Everything here runs on the main thread. The port's frame loop is main-thread on iOS and
// PortHostUIPollPad is called from inside it, so there is no hopping and no UIKit lock; the only
// lock taken is SunPadInputMixer's own, and it takes that itself.

#import <UIKit/UIKit.h>

#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_video.h>

#include "port/hostui.h"

#import "SunPadDiagnostics.h"
#import "SunPadGameOverlay.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

// SunPad's button mask and the port's are the same twelve bits today. This is a translation rather
// than a cast on purpose: the compiler checks these names, so if either project's layout moves the
// wrong row is visible here, where a numeric hand-off would keep compiling and press a different
// button.
static unsigned int BallpadPortButtons(uint16_t sunPadButtons)
{
    const struct { SunPadButton sunPad; unsigned int port; } rows[] = {
        { SunPadButtonDpadLeft,  PORT_PAD_BUTTON_LEFT  },
        { SunPadButtonDpadRight, PORT_PAD_BUTTON_RIGHT },
        { SunPadButtonDpadDown,  PORT_PAD_BUTTON_DOWN  },
        { SunPadButtonDpadUp,    PORT_PAD_BUTTON_UP    },
        { SunPadButtonZ,         PORT_PAD_TRIGGER_Z    },
        { SunPadButtonR,         PORT_PAD_TRIGGER_R    },
        { SunPadButtonL,         PORT_PAD_TRIGGER_L    },
        { SunPadButtonA,         PORT_PAD_BUTTON_A     },
        { SunPadButtonB,         PORT_PAD_BUTTON_B     },
        { SunPadButtonX,         PORT_PAD_BUTTON_X     },
        { SunPadButtonY,         PORT_PAD_BUTTON_Y     },
        { SunPadButtonStart,     PORT_PAD_BUTTON_START },
    };

    unsigned int port = 0;
    for (const auto& row : rows)
    {
        if ((sunPadButtons & row.sunPad) != 0)
            port |= row.port;
    }
    return port;
}

// ── SunPad's menu, under a Ballpad header ─────────────────────────────────────
// The vendored -buildMenu titles its menu with the project the interface came from, and a UIMenu
// cannot be retitled once it is built. Rebinding the title without retyping the menu is what a
// subclass is for: this rebuilds nothing, takes every child the vendored method produced -- the
// same rows in the same order, the same handlers, the same Restart Required alerts -- and wraps
// them in a menu titled with this app. Declaring the private method is what makes the override
// legal; the vendored file keeps its bytes.
@interface SunPadGameOverlay (BallpadMenuTitle)
- (UIMenu *)buildMenu;
@end

@interface BallpadGameOverlay : SunPadGameOverlay
@end

@implementation BallpadGameOverlay

- (UIMenu *)buildMenu
{
    UIMenu *vendored = [super buildMenu];
    if (vendored == nil)
        return nil;

    NSBundle *bundle = NSBundle.mainBundle;
    NSString *title = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Ballpad Strikers";
    return [UIMenu menuWithTitle:title children:vendored.children];
}

@end

// SunPadGameOverlay holds its delegate weakly, so the app has to own the receiver.
@interface BallpadHostUIBridge : NSObject <SunPadGameOverlayDelegate>
// The overlay is retained by the view hierarchy that holds it; this is only how a lifecycle
// notification reaches the one object that knows about it.
@property(nonatomic, weak) SunPadGameOverlay *overlay;
@end

@implementation BallpadHostUIBridge

// The two callbacks that return text answer from what this build actually is, so the diagnostic
// report and any problem report describe Ballpad rather than the project the overlay came from.
- (NSString *)gameOverlayDiagnosticContext:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    UIDevice *device = UIDevice.currentDevice;
    return [NSString stringWithFormat:@"Ballpad Strikers %@ (%@) on %@ %@",
                                      version, build, device.model, device.systemVersion];
}

- (NSString *)gameOverlayPerformanceProfile:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    // This is not SunPad's emulator performance profile and must not be reported as one. What a
    // native-port build can honestly say is which build it is, because that is what a reader needs
    // to tell a Simulator result from a device one.
#if TARGET_OS_SIMULATOR
    return @"native port, Simulator";
#else
    return @"native port, device";
#endif
}

// The four actions that ask the host to do something are where N5 attaches Ballpad's own importer,
// settings store and diagnostics. Until those exist they record the request and stop: the menu row
// is live and its geometry is SunPad's, but nothing here may claim to have imported, removed or
// reconfigured anything it has not.
- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    SunPadLog(@"host ui: game data change requested (not routed yet)");
}

- (void)gameOverlayRequestsGameDataFolderImport:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    SunPadLog(@"host ui: game data folder import requested (not routed yet)");
}

- (void)gameOverlayRequestsGameDataRemoval:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    SunPadLog(@"host ui: game data removal confirmed by the user (not routed yet)");
}

- (void)gameOverlayRequestsControllerMapping:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    SunPadLog(@"host ui: controller mapping requested (not routed yet)");
}

#pragma mark - Lifecycle

// The port already owns pause: Aurora turns SDL's minimized event -- which SDL's UIKit layer
// raises for UIApplicationDidEnterBackground -- into a frame it refuses to present, so there is
// deliberately no second pause here competing with it. Two things that seam does not cover do
// belong here. Input: a stick or button still held as the app leaves the foreground has no frame
// left to be released in, and a latched edge would then survive into the first frame after the
// resume -- the mixer is the one place that can guarantee the release, and it is the same
// boundary the per-frame publish reads. And controller visibility: re-reading GameController's
// enumeration on resume is what -refreshControllerVisibility is documented for, and it is a
// notification rather than a per-frame check because it animates the controls in or out.
- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    (void)notification;
    [[SunPadInputMixer sharedMixer] clearInputFromTouch:YES];
    SunPadLog(@"host ui: background; touch input released at the mixer");
}

// Logged rather than acted on: the port resumes the frame loop from its own lifecycle, so the
// useful evidence is the ordering of the three notifications around a cycle.
- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    (void)notification;
    SunPadLog(@"host ui: foreground; frame loop resumes on the port's own lifecycle");
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    [self.overlay refreshControllerVisibility];
    SunPadLog(@"host ui: active; controller visibility re-checked");
}

@end

// The overlay is retained by the view hierarchy it is added to. The bridge is not retained by the
// overlay, so this is what keeps the menu's actions connected.
static SunPadGameOverlay *s_overlay = nil;
static BallpadHostUIBridge *s_bridge = nil;

// SDL3 hands out the UIWindow it created for the window the port presents into, which is the
// window whose view controller holds the render surface. The key-window search is a fallback so
// that a missing property cannot silently leave the player with no controls at all; it is a
// fallback because the SDL window is the one the renderer is attached to.
static UIWindow *BallpadWindowForSDLWindow(void *sdlWindow)
{
    if (sdlWindow != nullptr)
    {
        SDL_PropertiesID properties = SDL_GetWindowProperties((SDL_Window *)sdlWindow);
        UIWindow *window = (__bridge UIWindow *)SDL_GetPointerProperty(
            properties, SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
        if (window != nil)
            return window;
    }

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
        {
            if (window.isKeyWindow)
                return window;
        }
    }
    return nil;
}

extern "C" void PortHostUIStart(void *sdlWindow)
{
    @autoreleasepool
    {
        if (s_overlay != nil)
            return;   // once per process; a second call is a port bug, not a second window

        UIWindow *window = BallpadWindowForSDLWindow(sdlWindow);
        if (window == nil)
        {
            SunPadLog(@"host ui: no UIWindow for the port's SDL window; no touch controls");
            return;
        }

        UIView *host = window.rootViewController.view ?: window;
        // BallpadGameOverlay, not the vendored class: the only difference is the menu header, and
        // everything else -- layout, hit-testing, the rows, the alerts -- is the vendored code.
        s_overlay = [[BallpadGameOverlay alloc] initWithFrame:host.bounds];
        // The SDL view controller resizes its view for a rotation, a size class change and a
        // safe-area change alike. Matching its autoresizing mask is what keeps SunPad's layout
        // math -- which reads its own bounds and insets -- on the same surface as the game.
        s_overlay.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        s_bridge = [BallpadHostUIBridge new];
        s_bridge.overlay = s_overlay;
        s_overlay.delegate = s_bridge;
        [host addSubview:s_overlay];

        // Registered once, for the same reason the overlay is built once: the notifications are
        // process-wide and the bridge is the process's single receiver for them.
        NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
        [notifications addObserver:s_bridge
                          selector:@selector(applicationDidEnterBackground:)
                              name:UIApplicationDidEnterBackgroundNotification
                            object:nil];
        [notifications addObserver:s_bridge
                          selector:@selector(applicationWillEnterForeground:)
                              name:UIApplicationWillEnterForegroundNotification
                            object:nil];
        [notifications addObserver:s_bridge
                          selector:@selector(applicationDidBecomeActive:)
                              name:UIApplicationDidBecomeActiveNotification
                            object:nil];

        // The overlay's own log is what makes a menu action visible after the fact, so the log the
        // vendored diagnostics write starts with the interface rather than with the first problem.
        SunPadDiagnosticsStart();
        SunPadLog(@"host ui: overlay %@ over %@ (%@)",
                  NSStringFromCGRect(s_overlay.frame), host, NSStringFromCGRect(host.bounds));
    }
}

extern "C" int PortHostUIPollPad(PortHostPad *out)
{
    if (out == nullptr || s_overlay == nil)
        return 0;

    // Logged once rather than per frame. This is the only line that shows the port's frame loop
    // reached the app's adapter -- which is a real question here, because the port also carries a
    // weak no-op for this same function and a build that resolved to that one would look identical
    // from the outside -- and at sixty a second it would be noise that hides everything else.
    static bool s_loggedFirstPoll = false;
    if (!s_loggedFirstPoll)
    {
        s_loggedFirstPoll = true;
        SunPadLog(@"host ui: first pad poll; the port is driving this adapter");
    }

    // Read the mixer exactly once per frame, as its header requires: it clears its latched button
    // edges as it is consumed, so a second read in the same frame finds them gone, and a frame
    // that skipped the read carries a tap past the frame it belonged to.
    SunPadInputState state = [[SunPadInputMixer sharedMixer] consumeMergedState];
    out->buttons = BallpadPortButtons(state.buttons);
    out->stickX = state.stickX;
    out->stickY = state.stickY;
    out->substickX = state.cStickX;
    out->substickY = state.cStickY;
    out->triggerLeft = state.triggerL;
    out->triggerRight = state.triggerR;
    return 1;
}

extern "C" void PortHostUIFrame(void)
{
    @autoreleasepool
    {
        // Nothing per frame yet, and deliberately nothing invented. The overlay lays itself out
        // from its own bounds and safe-area insets, so a resize is UIKit's to report; the
        // GameController re-check after a foreground resume is a lifecycle notification rather
        // than a per-frame poll (N4-C), and doing it here would restart the control-hide
        // animation sixty times a second.
    }
}

extern "C" void PortHostUIStop(void)
{
    @autoreleasepool
    {
        if (s_bridge != nil)
            [NSNotificationCenter.defaultCenter removeObserver:s_bridge];

        SunPadGameOverlay *overlay = s_overlay;
        s_overlay = nil;
        overlay.delegate = nil;
        [overlay removeFromSuperview];
        s_bridge = nil;
    }
}
