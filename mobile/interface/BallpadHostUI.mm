// Ballpad's side of the port's host-UI seam (port/hostui.h).
//
// The interface itself is SunPad's, vendored byte-for-byte in interface/sunpad/; this file is the
// adaptation layer that directory's README asks for, and it holds every Ballpad-specific decision:
// where the overlay is attached, how a frame of touch input becomes the port's pad, what the
// menu's delegate callbacks do here, and what each of the vendored menu rows is bound to on this
// runtime. Keeping those decisions out of the vendored files is what makes "SunPad's controls,
// exactly as they are" a claim a reader can check with a diff: the rows, their titles, their order
// and their icons still come from the vendored -buildMenu, and the handful this file does change
// are named by their vendored title in -buildMenu below.
//
// Everything here runs on the main thread. The port's frame loop is main-thread on iOS and
// PortHostUIPollPad is called from inside it, so there is no hopping and no UIKit lock; the only
// lock taken is SunPadInputMixer's own, and it takes that itself.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <GameController/GameController.h>

#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_video.h>
// getenv, for the STRIKERS_LOG_ poll gates further down. Included rather than reached for through
// UIKit: the port's own files spell it this way, and this one reads the same variables they do.
#include <stdlib.h>
// memcmp, for the RIFF and WAVE tags the audio row's read-back checks before it trusts a chunk.
#include <string.h>

// The port's plain-C headers, included rather than restated: aspect, the frame limiter, and the
// frame-time benchmark the FPS row reads. include/port/input.h is here for the same reason -- it is
// where the controller-mapping panel reads the physical map the port actually resolved.
#include "port/aspect.h"
#include "port/audio.h"
#include "port/benchmark.h"
#include "port/framerate.h"
#include "port/hostui.h"
#include "port/input.h"
#include "port/overlay.h"

// The render-scale pin is the one exception, and the exception is the point. include/port/launch.h
// declares PortSetRenderScale and PortRenderScale inside a PORT_USE_AURORA guard and reaches for
// aurora/aurora.h to do it, while PORT_USE_AURORA is a compile definition on the port's own target
// that does not reach this one. Both are symbols in the port's archive either way, so declaring
// them here is the same link with a much smaller include graph for a UIKit file.
extern "C" {
void PortSetRenderScale(float scale);
float PortRenderScale(void);
void PortRenderTargetSize(unsigned int* width, unsigned int* height);
// The two accessors that say the display *aspect* reached the renderer rather than only the store.
// The render target below follows the window's shape, so it is deliberately not one of them; these
// are: PortLogicalFrameWidth is the coordinate space the game's GXSetViewport, GXSetScissor and 2D
// orthographic projections are set from (480 * aspect, so 640 at 4:3), and PortCameraAspectBlend is
// how far the gameplay camera has been carried from its 4:3 tuning toward its widescreen one.
unsigned int PortLogicalFrameWidth(void);
float PortCameraAspectBlend(void);
}

#import "SunPadDiagnostics.h"
#import "SunPadGameOverlay.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#import "BallpadControllerMapping.h"
#import "BallpadCredits.h"
#import "BallpadGameData.h"
#import "BallpadLog.h"

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

// ── Ballpad's own row state ───────────────────────────────────────────────────
// The frame-limit row (doc 36 R1 item 11) stands where a vendored row promised an emulator's
// "Experimental 60 FPS" boot mode. A native port has no boot mode to change and no emulated clock
// to speed up -- it has the limiter, which caps rather than accelerates -- so the row's state is
// Ballpad's own key and the vendored key is left where N4 put it (R1 item 14). The port reads
// STRIKERS_FPS_LIMIT once at start and knows nothing about user defaults, which is why this is
// re-applied in PortHostUIStart and not only when the row is tapped.
// The key itself lives with BallpadLog's other app-level facts, because the settings read-back that
// reports this row has to name it too.

static BOOL BallpadFrameLimitIsUnlimited(void)
{
    return [NSUserDefaults.standardUserDefaults boolForKey:BallpadFrameLimitUnlimitedKey];
}

// The C-stick's horizontal axis. "Modern C-stick horizontal" exists because the GameCube camera's
// horizontal convention is inverted relative to what a player raised on a dual-stick pad expects;
// SunPad's own input encoder applies the flip on the way to its emulator, and here the port *is*
// the emulator, so the same flip has to happen on the way into the port's pad. Without this the
// switch would persist a preference that nothing reads -- exactly the failure R1 item 5 names.
static int BallpadCStickX(int sunPadCStickX)
{
    if ([SunPadSettings sharedSettings].modernCStickHorizontal)
        return -sunPadCStickX;
    return sunPadCStickX;
}

// ── The two display settings that have to reach the renderer ──────────────────
// SunPad offers the render scale and the aspect from two surfaces each, and neither surface
// reaches this runtime: the menu's Render Resolution and Aspect Ratio rows are the vendored
// handlers, which write SunPadSettings and stop at -refreshMenuButton, and the settings panel's own
// "Render" segmented control does the same. Ballpad rebuilds the menu rows against its own
// handlers, so that route acts where it happens; the panel's control is vendored code whose bytes
// are the fidelity claim, so this is the other half of the bridge. It is deliberately
// route-independent: whatever put a value in SunPadSettings -- Ballpad's own menu row, the vendored
// panel control, or the store an earlier run left behind -- is read here and handed to the port.
//
// Read from PortHostUIFrame rather than from a UIKit action, because that call sits inside the
// port's frame, after PortPumpAuroraEvents has already run PortFollowWindowShape. A pin applied
// from a UIKit handler races the next follow pass; applied here it is the frame's last word.
//
// Each setting has two states and only the first is a choice:
//   * a stored value is the player's, and it pins the port;
//   * a missing one is nobody's, and the port keeps doing what it did before this bridge existed --
//     following the window, with the window's own height for the render scale and the window's own
//     shape for the aspect. The vendored menu can say that for the aspect -- "Fill Screen" is
//     exactly the window's shape -- but the vendored panel has no render-scale segment for it, so a
//     missing render scale is primed once the window has settled, and the stored value then
//     describes what the port is already doing. The window is resized during the port's own
//     start-up (the first measured phone run showed a transient 448-row window before the real
//     one), so "settled" is sixty consecutive frames of one value rather than the first frame's
//     reading: priming on a transient would freeze the picture at the size of a window that no
//     longer exists.
static NSInteger s_renderScalePinned;   // 0 = the port still follows the window's height
static NSInteger s_aspectPinned = -1;   // -1 = the port still follows the window's shape
static float s_followScaleSeen;
static unsigned s_followScaleFrames;

static BOOL BallpadStoredSetting(NSString *key, NSInteger *outValue)
{
    NSNumber *value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (value == nil)
        return NO;
    *outValue = value.integerValue;
    return YES;
}

// The window's own scale, in the units the setting can hold. The port derives a fractional scale
// from the window height; the vendored control offers four integers, so the nearest one is what the
// setting can carry without pretending to a precision it does not have.
static NSInteger BallpadRenderScaleNearest(float follow)
{
    NSInteger scale = (NSInteger)(follow + 0.5f);
    return scale < 1 ? 1 : (scale > 4 ? 4 : scale);
}

static float BallpadAspectValueForMode(NSInteger mode)
{
    switch (mode)
    {
        case SunPadAspectRatioWidescreen: return 16.0f / 9.0f;
        case SunPadAspectRatioFillScreen: return -1.0f;
        default:                          return 4.0f / 3.0f;
    }
}

// The port's own read-back of what the display rows changed: the render target the renderer is
// configured with, the scale it was asked for, the aspect the picture is being fitted to with
// whether that shape is the window's or a pinned one, and the two numbers that say the aspect
// reached the *renderer* rather than only the store. One helper for the log and for the FPS counter
// because "the row reached the store" and "the row reached the renderer" are different facts, and
// this string is the second one -- it is read back through the same accessors the display bridge
// writes through, so a row that changed the store and nothing else shows up here as a target that
// did not move.
//
// The target's own shape is the window's, at the render scale, which is why the aspect row moves
// `logical` and `blend` and leaves `WxH` alone. That is not a gap in the row; it is where the change
// lands. The port presents one buffer scaled to the surface and fits the picture inside it by moving
// the game's logical frame and camera, so a reader who only had `WxH` would read an aspect change as
// having done nothing -- which is exactly the mistake this field pair exists to prevent.
static NSString *BallpadDisplayReadBack(void)
{
    unsigned int width = 0;
    unsigned int height = 0;
    PortRenderTargetSize(&width, &height);
    return [NSString stringWithFormat:@"%ux%u @%.2fx aspect %.3f %@ logical %u blend %.2f",
            width, height, (double)PortRenderScale(), (double)PortTargetAspect(),
            PortAspectFollowsWindow() ? @"window" : @"pinned",
            PortLogicalFrameWidth(), (double)PortCameraAspectBlend()];
}

// The port's own account of the audio path, in the shape of the display read-back above and for the
// same reason: "MusyX initialised" and "the device was handed the mixer's bytes" are two different
// facts, and only the second one is sound. The numbers are the mixer's own, and they are read
// together because each one alone names a different silence: a studio in state 1 with voices on it
// says the sequencer ran, voices whose sample resolves to memory says the samples were found, a
// peak envelope and pan volume say the voices were driving them, the bus peak says the mix that
// came out the far end was not silent, and the transport's tick and underrun counts say whether the
// device was ever handed it. The dump fields are the recorded-audio row's state, read from the
// mixer rather than remembered here, so the row's checkmark follows the recording and not the tap.
//
// How many frames the port has asked this seam to publish for. It is the loop's own rate measured
// by a clock outside the port, which is the only way to say whether the audio clock and the frame
// clock are the same clock: the transport's ticks are 5 ms of *audio* time and this is one *frame*
// of game time, and a run where the two per-second rates differ is a run where every voice lands
// further from the model that speaks it than the one before.
static unsigned long s_framesPolled;

static NSString *BallpadAudioReadBack(void)
{
    unsigned long buffers = 0;
    unsigned long underruns = 0;
    int everNonSilent = 0;
    PortAudioStats(&buffers, &underruns, &everNonSilent);

    // The transport's queue, which is the half of "are the sounds attached to the models" that
    // voices and bus peaks cannot answer: those say a sound exists, this says how far behind the
    // frame that produced it the speaker still is. Printed with its own spread and its own drain
    // rate, because a queue length is only a length in time if the stream's bytes are leaving at
    // the stream's own rate.
    PortAudioLatencyInfo onset;
    NSString *onsetText = PortAudioLatencyStats(&onset)
        ? [NSString stringWithFormat:@"onset lead %.1f min %.1f max %.1f mean %.1f ms over %lu "
                                   @"frames | devhold %.1f ms | drain %.0f B/s of %u",
                                   onset.leadMs, onset.leadMinMs, onset.leadMaxMs,
                                   onset.leadMeanMs, onset.handovers, onset.deviceMs,
                                   onset.drainBytesPerSec, onset.streamByteRate]
        : @"onset unmeasured (nothing queued yet)";

    // The frame clock beside the audio one, with the line's own timestamp as the third reading.
    // The port's rolling window and this seam's own count are two independent measures of the same
    // rate, and they are printed together because a rate compared only against itself is not a
    // measurement.
    PortBenchLive live;
    PortBenchGetLive(&live);
    NSString *transportText = [NSString stringWithFormat:@"%@ | clock frame %lu fps %.1f",
                                                         onsetText, s_framesPolled, live.fps];

    PortAudioMixInfo mix;
    if (!PortAudioMixStats(&mix))
    {
        // The mixer has not run, which is what an audio-off build and a boot that never reached
        // sndInit() both look like from here. Reported as itself rather than as silence: the
        // transport's own numbers are still worth having, because ticks with no mixer is a
        // different fault from no ticks at all.
        return [NSString stringWithFormat:@"device %d ticks %lu underruns %lu %@ | the mixer has "
                @"not run | %@", PortAudioDeviceOpen(), buffers, underruns,
                everNonSilent ? @"non-silent" : @"silent", transportText];
    }

    return [NSString stringWithFormat:
            @"device %d ticks %lu underruns %lu %@ | studios %d voices %d sample %d env 0x%04x "
            @"pan 0x%04x bus %d | frq %u master %.2f limiter %.3f | dumping %d frames %lu | %@",
            PortAudioDeviceOpen(), buffers, underruns, everNonSilent ? @"non-silent" : @"silent",
            mix.studios, mix.voices, mix.withSample, mix.peakEnv, mix.peakVol, mix.busPeak,
            mix.mixFrq, (double)mix.masterGain, (double)mix.limitGain, mix.dumping,
            mix.dumpFrames, transportText];
}

static void BallpadLogAudioTarget(NSString *what)
{
    BallpadLog(@"audio: %@ -- %@", what, BallpadAudioReadBack());
}

// The audio read-back on a clock, because the question it answers is about a run rather than about
// a tap. A row change alone would miss a device that failed to open before the row existed, and a
// per-frame line would bury the rest of the log. Two seconds is the port's own mixer-report period,
// so the app's line and the port's line pair up when they are read together.
static void BallpadLogAudioIfDue(void)
{
    static CFTimeInterval s_last;
    static BOOL s_written = NO;
    const CFTimeInterval now = CACurrentMediaTime();
    if (s_written && now - s_last < 2.0)
        return;
    BallpadLogAudioTarget(s_written ? @"running" : @"start-up");
    s_written = YES;
    s_last = now;
}

static void BallpadLogDisplayTarget(NSString *what)
{
    BallpadLog(@"display: %@ -- %@", what, BallpadDisplayReadBack());
    // Both read-backs, because a display row can be wrong in two independent ways: the store can
    // hold a value the renderer never got, or the renderer can hold one no surface shows. The line
    // above answers the second question and BallpadLogSettingsSnapshot answers the first, and this
    // is the one place in the run where both answers are known to belong to the same change.
    BallpadLogSettingsSnapshot(what);
}

// The vendored settings panel writes the store itself -- its bytes are the fidelity claim (R1 item
// 1), so Ballpad cannot hook the panel's controls -- which leaves one honest way for the log to
// report a panel change: notice the value that moved. Six numbers compared once a frame is cheap,
// and the line it writes is the same read-back a menu row writes, so a report spells a panel change
// and a row change the same way. Only the settings no menu row also owns are watched here; the
// display settings have their own bridge above, which reports them where they are pinned.
static void BallpadLogSettingsIfPanelChanged(void)
{
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    const struct { const char *name; NSInteger value; } readings[] = {
        { "control opacity",    (NSInteger)(settings.controlOpacity * 100.0 + 0.5) },
        { "control size",       (NSInteger)(settings.controlSizeScale * 100.0 + 0.5) },
        { "hide on controller", settings.hideTouchControlsWhenControllerConnected ? 1 : 0 },
        { "modern c-stick",     settings.modernCStickHorizontal ? 1 : 0 },
        { "fps counter",        settings.showFPSCounter ? 1 : 0 },
        { "layout editing",     settings.editingControlLayout ? 1 : 0 },
    };
    const size_t count = sizeof(readings) / sizeof(readings[0]);
    static NSInteger s_seen[sizeof(readings) / sizeof(readings[0])];
    static BOOL s_primed = NO;

    NSMutableArray<NSString *> *moved = [NSMutableArray array];
    for (size_t index = 0; index < count; ++index)
    {
        // The first pass only records: a run's opening line is the startup state, and it comes from
        // the display bridge rather than from six settings that were never touched.
        if (s_primed && readings[index].value != s_seen[index])
            [moved addObject:[NSString stringWithUTF8String:readings[index].name]];
        s_seen[index] = readings[index].value;
    }
    s_primed = YES;
    if (moved.count > 0)
        BallpadLogSettingsSnapshot([NSString stringWithFormat:@"%@ changed by the settings panel",
                                    [moved componentsJoinedByString:@", "]]);
}

// -- The touch settings, read back from the overlay itself (R1 item 5) --------
// The store and the overlay are different witnesses, and only the second one is what the player
// touches. SunPadSettings can hold an opacity that no control is drawn at: the vendored panel
// writes the store and the overlay reads it back during its own layout pass, so a value that never
// reached a view is exactly the failure this reading has to be able to show. The vendored bytes
// are the fidelity claim and are not instrumented, so the reading is taken from the live view tree
// instead: alpha, bounds and center are public UIView state, they are what UIKit draws from, and
// the identifiers walked here are the overlay's own layout keys -- the same ones it persists a
// moved control under, and the same ones a UI test sees as elements.
//
// Whether a control is hidden is the one drawn fact whose input is not on this machine. The
// vendored `-applyControllerVisibility` compiles the controller half of its resolution out under
// `TARGET_OS_SIMULATOR`, so the count this build can read is *not* the value the overlay resolved
// from, and the line says so by publishing the setting, the count and the drawn hidden count as
// three separate fields rather than one verdict. The hardware merge itself stays F12/NOT_RUN.
static NSArray<UIView *> *BallpadTouchControlsInDrawOrder(SunPadGameOverlay *overlay)
{
    NSArray<NSString *> *order = @[ @"move", @"c", @"D_U", @"D_D", @"D_L", @"D_R",
                                    @"A", @"B", @"X", @"Y", @"Z", @"Start", @"L", @"R" ];
    NSMutableDictionary<NSString *, UIView *> *found = [NSMutableDictionary dictionary];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:overlay];
    while (pending.count > 0)
    {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        NSString *identifier = view.accessibilityIdentifier;
        if (identifier.length > 0 && found[identifier] == nil)
            found[identifier] = view;
        [pending addObjectsFromArray:view.subviews];
    }
    NSMutableArray<UIView *> *controls = [NSMutableArray array];
    for (NSString *identifier in order)
        if (found[identifier] != nil)
            [controls addObject:found[identifier]];
    return controls;
}

static NSString *BallpadOverlayTouchReadBack(SunPadGameOverlay *overlay)
{
    NSArray<UIView *> *controls = BallpadTouchControlsInDrawOrder(overlay);
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    NSMutableArray<NSString *> *drawn = [NSMutableArray array];
    NSUInteger hidden = 0;
    for (UIView *control in controls)
    {
        if (control.hidden)
            hidden++;
        // The identifier first and the drawn numbers after it, so a reader can line the reading up
        // with the control it came from. A control the overlay has hidden is named as hidden rather
        // than left with an alpha of zero and no explanation. The trailing k is the *per-control*
        // size override the editor writes, 1.0 when there is none, and it is published because it
        // is the only thing that tells the editor's own resize apart from the panel's global size
        // setting, which moves every control's drawn bounds with it: two different settings that
        // both show up as a drawn size changing, and only one of them is item 5's move/resize pair.
        [drawn addObject:[NSString stringWithFormat:@"%@ %.2f %.0fx%.0f @%.0f,%.0f k%.2f%@",
                          control.accessibilityIdentifier, (double)control.alpha,
                          (double)control.bounds.size.width, (double)control.bounds.size.height,
                          (double)control.center.x, (double)control.center.y,
                          (double)[settings sizeScaleForControl:control.accessibilityIdentifier],
                          control.hidden ? @" hidden" : @""]];
    }

    // The two panel values the drawn numbers above are supposed to follow, published beside them so
    // a reader can tie a drawn alpha or a drawn size to the setting that asked for it. The store's
    // own line is a different witness -- it can hold an opacity no control was ever drawn at -- and
    // these are the values the overlay resolved at the moment it laid the tree out.
    // `hidden` is the count of the drawn controls the overlay has hidden, which is the resolved half
    // of the visibility setting above it: the vendored pass paints a hidden control at an alpha of
    // zero and flags the view, and only a count taken off those views says whether the resolution
    // reached the drawing. The editor paints every control at full alpha while it is open, which is
    // why a reader comparing a drawn alpha with the opacity setting has to allow that one state.
    return [NSString stringWithFormat:@"controllers %lu hide-requested %d opacity %.2f size %.2f drawn %lu hidden %lu | %@",
            (unsigned long)GCController.controllers.count,
            settings.hideTouchControlsWhenControllerConnected ? 1 : 0,
            (double)settings.controlOpacity,
            (double)settings.controlSizeScale,
            (unsigned long)controls.count,
            (unsigned long)hidden,
            drawn.count > 0 ? [drawn componentsJoinedByString:@" | "]
                            : @"no control is drawn"];
}

// A drag or a slider moves the tree every frame, and the value worth keeping is the one it settles
// on: the line is written a third of a second after the tree stops moving, so a touch that ends
// leaves one reading rather than sixty. The overlay is watched by identity, because a lifecycle
// rebuild replaces it and a reading of the old tree would describe controls nobody can touch.
static void BallpadLogOverlayTouchIfSettled(SunPadGameOverlay *overlay)
{
    static __weak SunPadGameOverlay *s_readFrom = nil;
    static NSString *s_logged = nil;
    static NSString *s_pending = nil;
    static CFTimeInterval s_pendingSince = 0.0;

    if (overlay != s_readFrom)
    {
        s_readFrom = overlay;
        s_logged = nil;
        s_pending = nil;
    }

    NSString *now = BallpadOverlayTouchReadBack(overlay);
    if (s_logged != nil && [now isEqualToString:s_logged])
        return;
    const CFTimeInterval stamp = CACurrentMediaTime();
    if (s_pending == nil || ![now isEqualToString:s_pending])
    {
        s_pending = now;
        s_pendingSince = stamp;
        return;
    }
    if (stamp - s_pendingSince < 0.35)
        return;
    s_logged = now;
    s_pending = nil;
    BallpadLog(@"overlay: the touch controls as drawn -- %@", now);
}

// -- The safe area the controls are drawn inside (doc 34 F06) -----------------
// F06's rotation half asks whether the landscape layout fits the safe areas, and this is the
// reading that answers it: not "the layout ran" but "every control it drew is inside the region the
// surface says is safe". The vendored pass is the only thing that decides where a control goes, and
// it derives its placement from the overlay's own -safeAreaInsets, so the surface's safe rect is
// the reference and the controls' converted frames are the claim. Nothing here is a device
// constant: the numbers come from UIKit and the verdict is a containment test.
//
// This is worth a line of its own rather than a clause on the overlay read-back above because the
// two disagree in the case that matters. Rotating the device from one landscape side to the other
// leaves the surface the same *size* -- so an overlay reading that prints bounds and centres looks
// unchanged -- while the notch and the home indicator swap sides and the safe rect moves under
// every control. The insets are therefore stated in the line, and the runner's F06 clause is that
// two different inset readings were seen (the rotation happened) and that no line in either of them
// put a drawn control outside the safe rect.
//
// Settled rather than immediate, for the reason the overlay read-back is: a rotation animates, and
// the frames sampled during the animation are the ones on their way somewhere. Thirty-five
// hundredths of a second after the tree stops moving is the layout that stayed.
static NSString *BallpadLayoutReadBack(SunPadGameOverlay *overlay)
{
    const UIEdgeInsets insets = overlay.safeAreaInsets;
    // Half a point of slack, so a control the vendored pass placed exactly on the safe edge is
    // inside it rather than outside by a rounding error.
    const CGRect safe = CGRectInset(UIEdgeInsetsInsetRect(overlay.bounds, insets), -0.5, -0.5);

    NSArray<UIView *> *controls = BallpadTouchControlsInDrawOrder(overlay);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *outside = [NSMutableArray array];
    NSUInteger judged = 0;
    for (UIView *control in controls)
    {
        // Only what is actually drawn is judged: a control the player has hidden by the
        // controller-connected rule or by the opacity slider is not a layout claim, and counting it
        // would turn a setting into a false failure.
        if (control.hidden || control.alpha == 0.0)
            continue;
        judged++;
        [names addObject:control.accessibilityIdentifier ?: @"?"];
        const CGRect drawn = [control convertRect:control.bounds toView:overlay];
        if (!CGRectContainsRect(safe, drawn))
            [outside addObject:[NSString stringWithFormat:@"%@ %@", control.accessibilityIdentifier ?: @"?",
                                NSStringFromCGRect(drawn)]];
    }

    // The FPS counter is Ballpad's own view rather than one of the vendored controls, and it is
    // placed against the same insets by BallpadPositionFPSCounterLabel -- so it belongs in the same
    // verdict. It is reported separately because it is the one drawn thing whose frame is set once
    // per surface shape, and a rotation that did not re-place it is a defect this line can show.
    //
    // Found by the identifier it publishes rather than held as a reference, for the reason
    // BallpadControlLabelled gives: the reading is of the tree the player has, and this file's
    // counter key is not in scope this early in the translation unit.
    UILabel *counter = nil;
    for (UIView *subview in overlay.subviews)
        if ([subview isKindOfClass:UILabel.class] &&
            [subview.accessibilityIdentifier isEqualToString:@"BallpadFPSCounter"])
            counter = (UILabel *)subview;
    NSString *counterField = @"fps 0";
    if (counter != nil && counter.superview != nil)
    {
        const CGRect drawn = [counter convertRect:counter.bounds toView:overlay];
        counterField = [NSString stringWithFormat:@"fps 1 origin %.1f,%.1f inside %d",
                        (double)drawn.origin.x, (double)drawn.origin.y,
                        CGRectContainsRect(safe, drawn) ? 1 : 0];
    }

    NSString *offenders = outside.count > 0
        ? [NSString stringWithFormat:@" (%@)", [outside componentsJoinedByString:@"; "]]
        : @"";
    return [NSString stringWithFormat:
            @"surface %.0fx%.0f safe %.1f,%.1f,%.1f,%.1f | judged %lu outside %lu%@ | %@ | %@",
            (double)CGRectGetWidth(overlay.bounds), (double)CGRectGetHeight(overlay.bounds),
            (double)insets.left, (double)insets.top, (double)insets.right, (double)insets.bottom,
            (unsigned long)judged, (unsigned long)outside.count, offenders,
            [names componentsJoinedByString:@","], counterField];
}

static void BallpadLogLayoutIfSettled(SunPadGameOverlay *overlay)
{
    static __weak SunPadGameOverlay *s_readFrom = nil;
    static NSString *s_logged = nil;
    static NSString *s_pending = nil;
    static CFTimeInterval s_pendingSince = 0.0;

    if (overlay != s_readFrom)
    {
        s_readFrom = overlay;
        s_logged = nil;
        s_pending = nil;
    }

    NSString *now = BallpadLayoutReadBack(overlay);
    if (s_logged != nil && [now isEqualToString:s_logged])
        return;
    const CFTimeInterval stamp = CACurrentMediaTime();
    if (s_pending == nil || ![now isEqualToString:s_pending])
    {
        s_pending = now;
        s_pendingSince = stamp;
        return;
    }
    if (stamp - s_pendingSince < 0.35)
        return;
    s_logged = now;
    s_pending = nil;
    BallpadLog(@"layout: %@", now);
}

// The C-stick flip, read back where it is applied: the pad the port is handed. R1 item 5 counts
// this switch among the settings that have to reach the runtime, and this runtime's C-stick is the
// port's, so the value worth publishing is the published one. Only transitions of the setting and
// of the player's own direction are logged, which is what bounds the line count during a drag, and
// both raw and published values are printed so the flip can be checked rather than described.
static void BallpadLogCStickIfTurned(int raw, int published)
{
    const int sign = raw > 0 ? 1 : (raw < 0 ? -1 : 0);
    if (sign == 0)
        return;
    const BOOL modern = [SunPadSettings sharedSettings].modernCStickHorizontal;
    static int s_lastKey = -3;
    const int key = (modern ? 10 : 0) + (sign + 1);
    if (key == s_lastKey)
        return;
    s_lastKey = key;
    BallpadLog(@"c-stick: the mixer's own X %d reached the port as %d (modern c-stick %@)", raw,
               published, modern ? @"on" : @"off");
}

static void BallpadApplyDisplaySettings(void)
{
    NSInteger stored = 0;

    if (s_renderScalePinned != 0)
    {
        NSInteger wanted = [SunPadSettings sharedSettings].renderScale;
        if (wanted != s_renderScalePinned)
        {
            s_renderScalePinned = wanted;
            PortSetRenderScale((float)wanted);
            BallpadLogDisplayTarget([NSString stringWithFormat:@"render scale %ld from the "
                                     @"settings store", (long)wanted]);
        }
    }
    else if (BallpadStoredSetting(@"SunPadRenderScale", &stored))
    {
        s_renderScalePinned = stored;
        PortSetRenderScale((float)stored);
        BallpadLogDisplayTarget([NSString stringWithFormat:@"render scale %ld stored by an "
                                 @"earlier run; the panel and the renderer agree from here",
                                 (long)stored]);
    }
    else
    {
        const float follow = PortRenderScale();
        if (follow <= 0.0f)
        {
            s_followScaleSeen = 0.0f;
            s_followScaleFrames = 0;
        }
        else if (follow != s_followScaleSeen)
        {
            s_followScaleSeen = follow;
            s_followScaleFrames = 0;
        }
        else if (++s_followScaleFrames >= 60)
        {
            NSInteger scale = BallpadRenderScaleNearest(follow);
            [SunPadSettings sharedSettings].renderScale = scale;
            [[SunPadSettings sharedSettings] synchronize];
            s_renderScalePinned = scale;
            PortSetRenderScale((float)scale);
            BallpadLogDisplayTarget([NSString stringWithFormat:@"no render scale stored; the "
                                     @"window settled at %.2fx, so the setting was primed to %ld "
                                     @"and pinned", (double)follow, (long)scale]);
        }
    }

    if (BallpadStoredSetting(@"SunPadAspectRatioMode", &stored))
    {
        if (stored != s_aspectPinned)
        {
            s_aspectPinned = stored;
            PortSetTargetAspect(BallpadAspectValueForMode(stored));
            BallpadLogDisplayTarget([NSString stringWithFormat:@"aspect mode %ld from the "
                                     @"settings store", (long)stored]);
        }
    }
    else if (s_aspectPinned >= 0)
    {
        // The key left the store under a pinned aspect -- a reset or a migration -- so the aspect
        // goes back to the window rather than staying pinned to a setting nothing holds.
        s_aspectPinned = -1;
        PortSetTargetAspect(-1.0f);
        BallpadLogDisplayTarget(@"aspect setting cleared; the port follows the window again");
    }
}

// One presentation route, for the overlay's own rows and for the delegate callbacks the vendored
// menu sends through the bridge alike: same presenter, same style, and a line when there is nothing
// to present from rather than a silent no-op.
static void BallpadPresentOverlayViewController(SunPadGameOverlay *overlay,
                                                UIViewController *viewController)
{
    UIViewController *presenter = overlay.window.rootViewController;
    if (presenter == nil)
    {
        BallpadLog(@"host ui: no presenter for %@", NSStringFromClass(viewController.class));
        return;
    }
    viewController.modalPresentationStyle = UIModalPresentationPageSheet;
    [presenter presentViewController:viewController animated:YES completion:nil];
}

// A vendored control, found by the label SunPad gave it rather than held as an ivar. Reaching into
// the vendored class's storage by name would be a dependency on internals that a byte-for-byte copy
// is not allowed to develop, and the labels are the same strings the UI suite and VoiceOver use, so
// what is found here is what a player can find. Three callers want this: the popover anchor for a
// share sheet, the shoulder whose shape is re-derived below, and the settings read-backs that prove
// a setting landed.
static UIView *BallpadControlLabelled(UIView *root, NSString *label)
{
    if ([root.accessibilityLabel isEqualToString:label])
        return root;
    for (UIView *subview in root.subviews)
    {
        UIView *found = BallpadControlLabelled(subview, label);
        if (found != nil)
            return found;
    }
    return nil;
}

// The three-dot button specifically, for use as a popover anchor on iPad.
static UIButton *BallpadMenuButton(UIView *view)
{
    UIView *found = BallpadControlLabelled(view, @"Menu");
    return [found isKindOfClass:UIButton.class] ? (UIButton *)found : nil;
}

// The vendored menu button is a plain UIButton with a circular layer and an ellipsis image, and
// UIKit drives it through selected and highlighted states while a primary-action menu is being
// dismissed. On current iPadOS that transition can synthesize a rectangular selected appearance
// over the circle, and an app that returns from the background to a rebuilt SDL surface can lose
// the button entirely. Both are the same problem -- the button has no explicit appearance to fall
// back on -- and one explicit configuration is the repair. It is applied from here rather than in
// the vendored file precisely because the vendored bytes are the fidelity claim; KartPad's own note
// on this defect (docs/IOS-THREE-DOT-MENU-FIX.md in that project) documents the same repair from the
// owning layer, with the same capsule, the same fill and the same stroke the vendored code draws.
static void BallpadConfigureMenuButton(UIButton *button)
{
    // Configured once: a configuration set on every layout would fight the highlight UIKit is
    // already driving.
    if (button == nil || button.configuration != nil)
        return;

    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.image = [button imageForState:UIControlStateNormal];
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsZero;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;

    UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
    background.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    background.cornerRadius = 20.0;
    background.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.30];
    background.strokeWidth = 1.0;
    configuration.background = background;

    button.automaticallyUpdatesConfiguration = NO;
    button.configuration = configuration;
    // One owner per visual: the configuration holds the fill and the stroke now, so the layer must
    // not draw a second border over it.
    button.backgroundColor = UIColor.clearColor;
    button.layer.borderWidth = 0.0;
}

// ── The right shoulder (the operator's "R has to look like L" item) ───────────
// SunPad's R control is a pressure track built for Sunshine's spray nozzle: it paints a water fill
// up to a detent line and reports a press only in the last quarter of its width. Strikers wants
// neither half of that. The game asks for PAD_TRIGGER_R -- the same bit L sets -- and the console it
// came from has two identical shoulder buttons, which is why the operator's reference is the left
// one. So R here is L's twin: the repair below gives it L's shape, L's border and no artwork, and
// these flags supply the press the detent would otherwise have gated. They are fed from the
// control's own gestures -- the public surface KartPad's owner layer uses for its own shoulder
// adaptation -- and they never touch the control's pressure, which keeps flowing to the port exactly
// as the vendored control produced it.
static BOOL s_rightShoulderHeld = false;
static BOOL s_rightShoulderPressEdge = false;
// While the layout editor is up, every vendored handler returns early, so R has to be inert too.
static BOOL s_rightShoulderInert = false;
// One pending cosmetic repair per layout burst; see -ballpadScheduleShoulderRepair.
static BOOL s_shoulderRepairPending = false;
// The border the two shoulders share at rest, captured once from L rather than re-read on every
// pass, and the reason is the defect that capture removes: see -ballpadApplyShoulderRepair. The
// colour is retained because it is read from a layer and then held across passes; the capture
// happens once per process, so the retain is a single reference and not a leak that grows.
static CGFloat s_shoulderRestBorderWidth = 0.0;
static CGColorRef s_shoulderRestBorderColor = NULL;

// Whether the overlay is raising its layout editor. Decided from the one control that exists only
// while editing -- the done button the UI suite presses to leave -- rather than from the vendored
// class's live flag, which is private, and because that button is the same answer the player and the
// test get.
//
// The editor is hidden by hiding its *bar*, not the button, and a hidden ancestor still leaves a
// view's -window set. So the question is asked of the ancestors: the button is visible only when
// every view between it and the overlay is visible, which is exactly the state the editor bar's own
// -hidden flag decides. Asking the button alone would answer "editing" for the whole session and
// leave the right shoulder permanently inert.
static BOOL BallpadOverlayIsEditingLayout(UIView *overlay)
{
    UIView *done = BallpadControlLabelled(overlay, @"Finish moving touch controls");
    if (done == nil || done.window == nil)
        return NO;
    for (UIView *view = done; view != nil && view != overlay; view = view.superview)
    {
        if (view.hidden || view.alpha == 0.0)
            return NO;
    }
    return YES;
}

// The R press as the port should read it this frame: the control is held, or a tap began and ended
// between two polls. The edge is consumed here for the same reason the vendored mixer latches its
// own -- a tap shorter than a frame would otherwise be lost -- and one asserted frame is exactly what
// a physical tap of that length produces.
static BOOL BallpadRightShoulderPressed(void)
{
    const BOOL pressed = (s_rightShoulderHeld || s_rightShoulderPressEdge) && !s_rightShoulderInert;
    s_rightShoulderPressEdge = false;
    return pressed;
}

// The trigger's own drawing: the water fill and the detent line, both shape sublayers of the
// control's layer. Hiding them is the whole of "L's twin" on the drawing side; the fill, the title,
// the border and the corner radius the vendored button factory gave both shoulders are left alone.
static void BallpadHideTriggerArtwork(UIView *shoulder)
{
    for (CALayer *layer in shoulder.layer.sublayers)
    {
        if ([layer isKindOfClass:CAShapeLayer.class])
            layer.hidden = YES;
    }
}

// L's and R's live geometry side by side, because "R looks like L" is a claim a reader should be
// able to check without a screenshot: the frames and bounds come from the two views after both the
// vendored layout pass and the repair have run, and the corner radius and border are read back from
// the layers that draw them. The one part of R that is deliberately *not* L's twin is the trigger's
// own artwork, so it is reported as the count of shape sublayers still visible -- zero is the
// expected answer, and any other number says the hidden-only pass above missed something.
//
// Written on change rather than per call, because the caller is -layoutSubviews and a UIKit
// animation (the control-hide transition, a rotation, the editor's own bar) drives that method every
// frame. The fingerprint covers what the repair is supposed to control, so the line appears when a
// vendored pass undid something, which is the event worth reading about, and stays quiet when the
// same geometry is applied again.
static void BallpadLogShoulderGeometry(UIView *overlay, NSString *what)
{
    UIView *left = BallpadControlLabelled(overlay, @"L");
    UIView *right = BallpadControlLabelled(overlay, @"R");
    if (left == nil || right == nil)
    {
        BallpadLog(@"shoulder: %@ -- L %@, R %@", what,
                   left != nil ? @"found" : @"missing", right != nil ? @"found" : @"missing");
        return;
    }

    NSUInteger artwork = 0;
    for (CALayer *layer in right.layer.sublayers)
        if ([layer isKindOfClass:CAShapeLayer.class] && !layer.hidden)
            artwork++;

    const BOOL sameBorder = left.layer.borderColor == NULL || right.layer.borderColor == NULL
        ? (left.layer.borderColor == right.layer.borderColor)
        : CGColorEqualToColor(left.layer.borderColor, right.layer.borderColor);

    NSArray<NSNumber *> *fingerprint = @[
        @((long long)(left.bounds.size.width * 100.0)),
        @((long long)(left.bounds.size.height * 100.0)),
        @((long long)(right.bounds.size.width * 100.0)),
        @((long long)(right.bounds.size.height * 100.0)),
        @((long long)(left.frame.origin.x * 100.0)),
        @((long long)(right.frame.origin.x * 100.0)),
        @((long long)(left.frame.origin.y * 100.0)),
        @((long long)(right.frame.origin.y * 100.0)),
        @((long long)(left.layer.cornerRadius * 100.0)),
        @((long long)(right.layer.cornerRadius * 100.0)),
        @((long long)(left.layer.borderWidth * 100.0)),
        @((long long)(right.layer.borderWidth * 100.0)),
        @(sameBorder ? 1 : 0),
        @((long long)artwork),
        // The layout editor is the one state in which the pair is deliberately not kept in step,
        // so it belongs in the fingerprint as well: with it out, opening or closing the editor
        // would change the reading below without changing the key, and the line that says which
        // state the numbers came from would never be written.
        @(BallpadOverlayIsEditingLayout(overlay) ? 1 : 0),
    ];
    static NSArray<NSNumber *> *s_seen = nil;
    if (s_seen != nil && [s_seen isEqualToArray:fingerprint])
        return;
    s_seen = fingerprint;

    // The two numbers that say "one drawn thing, drawn twice" without a picture: how far each
    // shoulder sits from its own edge of the surface, and the row each one is on. They are derived
    // from the live frames rather than reported by the repair, so a repair that stopped mirroring
    // the pair would print the difference here instead of covering it up.
    const CGFloat leftInset = CGRectGetMinX(left.frame);
    const CGFloat rightInset = CGRectGetWidth(overlay.bounds) - CGRectGetMaxX(right.frame);
    const CGFloat rowDelta = CGRectGetMinY(right.frame) - CGRectGetMinY(left.frame);

    BallpadLog(@"shoulder: %@ -- editing %d | L frame %@ bounds %@ R frame %@ bounds %@; "
               @"corner L %.1f R %.1f, border L %.1f R %.1f %@, mirror inset L %.1f R %.1f "
               @"row delta %.1f, R visible shape layers %lu, R class %@, R value %@",
               what, BallpadOverlayIsEditingLayout(overlay) ? 1 : 0,
               NSStringFromCGRect(left.frame), NSStringFromCGSize(left.bounds.size),
               NSStringFromCGRect(right.frame), NSStringFromCGSize(right.bounds.size),
               (double)left.layer.cornerRadius, (double)right.layer.cornerRadius,
               (double)left.layer.borderWidth, (double)right.layer.borderWidth,
               sameBorder ? @"same" : @"differs",
               (double)leftInset, (double)rightInset, (double)rowDelta,
               (unsigned long)artwork, NSStringFromClass(right.class), right.accessibilityValue ?: @"none");
}
// L's and R's press state, sampled every frame rather than on the layout pass the geometry line
// above is written from. The repair runs in -layoutSubviews and a press does not re-lay the overlay
// out, so a press is invisible to that line -- and the two shoulders do not publish a press the
// same way:
//
//   * L is a plain SunPadGameButton, and the vendored pass presses a plain button by scaling it to
//     0.92. Its outline never moves, so that transform is the whole of its press state.
//   * R is the vendored SunPadTriggerButton, the one control with a detent: at or past 0.75 of its
//     width the vendored pass writes a 3.0 outline and below it the at-rest 2.0. Its transform
//     never moves, so that outline is the whole of its press state.
//
// Which is why a width on its own cannot name a press, and why an earlier version of this line
// could not either: it read 3.0 as "at the detent", and while the layout editor is open the
// vendored -updateControlAppearance paints 3.0 on *every* control, both shoulders included. Those
// lines were counted as a press on the wrong shoulder -- a fault that had not happened. So the line
// names the editor, and names each shoulder's own press state beside its width, rather than leaving
// the reader to infer a press from a number that has a second meaning.
static void BallpadLogShoulderOutlineIfChanged(UIView *overlay)
{
    UIView *left = BallpadControlLabelled(overlay, @"L");
    UIView *right = BallpadControlLabelled(overlay, @"R");
    if (left == nil || right == nil)
        return;

    const BOOL editing = BallpadOverlayIsEditingLayout(overlay);
    const BOOL leftHeld = !CGAffineTransformIsIdentity(left.transform);
    const BOOL rightHeld = s_rightShoulderHeld;
    const CGFloat lw = left.layer.borderWidth;
    const CGFloat rw = right.layer.borderWidth;

    static BOOL s_editing = NO;
    static BOOL s_leftHeld = NO;
    static BOOL s_rightHeld = NO;
    static CGFloat s_leftWidth = -1.0;
    static CGFloat s_rightWidth = -1.0;
    if (editing == s_editing && leftHeld == s_leftHeld && rightHeld == s_rightHeld &&
        lw == s_leftWidth && rw == s_rightWidth)
        return;
    s_editing = editing;
    s_leftHeld = leftHeld;
    s_rightHeld = rightHeld;
    s_leftWidth = lw;
    s_rightWidth = rw;

    NSString *reading = nil;
    if (editing)
        reading = @"the layout editor is open, so both outlines are the editor's own and neither is "
                  @"a press";
    else if (leftHeld && rightHeld)
        reading = @"both shoulders are held, and each carries its own press state";
    else if (leftHeld)
        reading = @"the left shoulder is held at the at-rest width, which is the whole of what a "
                  @"plain button draws";
    else if (rightHeld && rw > lw)
        reading = @"the right trigger is held past its detent, the one press a shoulder draws as a "
                  @"wider outline";
    else if (rightHeld)
        reading = @"the right trigger is held below its detent, so it keeps the at-rest width";
    else
        reading = @"neither shoulder is held, so both are at rest";

    BallpadLog(@"shoulder outline: editing %d | L held %d border %.1f | R held %d border %.1f -- %@",
               editing ? 1 : 0, leftHeld ? 1 : 0, (double)lw, rightHeld ? 1 : 0, (double)rw,
               reading);
}


// ── SunPad's menu, under a Ballpad header ─────────────────────────────────────
// Declaring the vendored class's private methods is what makes the overrides below legal while the
// vendored file keeps its bytes. -buildMenu, -refreshMenuButton, -confirmGameDataRemoval and
// -reportProblem are the four this file reaches; each is overridden or called, never redefined.
@interface SunPadGameOverlay (BallpadMenuHooks)
- (UIMenu *)buildMenu;
- (void)refreshMenuButton;
- (void)confirmGameDataRemoval;
- (void)reportProblem;
@end

@interface BallpadGameOverlay : SunPadGameOverlay
// The right shoulder's own press and appearance, wired and applied from -layoutSubviews; the flags
// they read and set are above, next to the reason they exist.
- (void)ballpadRightShoulderGesture:(UILongPressGestureRecognizer *)gesture;
- (void)ballpadApplySafeAreaContainment;
- (void)ballpadApplyShoulderRepair;
- (void)ballpadScheduleShoulderRepair;
- (void)ballpadWireRightShoulder:(UIView *)right;
@end

@implementation BallpadGameOverlay

#pragma mark - The menu

// The vendored -buildMenu is still the composer and still decides the order. This override takes
// its children and swaps only the rows doc 36's R1 list names, matching them by the title the
// vendored method gave them -- every vendored identifier is nil, so the title is the only handle
// that exists -- and passing anything unmatched straight through. That is what keeps the untouched
// rows (the FPS toggle, Touch Control Settings) exactly as the vendored file built them, which is
// the difference between adapting a menu and rewriting one.
- (UIMenu *)buildMenu
{
    UIMenu *vendored = [super buildMenu];
    if (vendored == nil)
        return nil;

    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    for (UIMenuElement *element in vendored.children)
    {
        NSString *title = element.title;
        if ([title isEqualToString:@"Render Resolution"])
            [children addObject:[self ballpadRenderMenu]];
        else if ([title isEqualToString:@"Aspect Ratio"])
            [children addObject:[self ballpadAspectMenu]];
        else if ([title isEqualToString:@"Experimental Performance Mode (Restart Required)"])
            [children addObject:[self ballpadAudioRecordingAction]];
        else if ([title isEqualToString:@"Experimental 60 FPS (Restart Required)"])
            [children addObject:[self ballpadFrameLimitAction]];
        else if ([title isEqualToString:@"Game Data & Saves"])
            [children addObject:[self ballpadGameDataMenu]];
        else
            [children addObject:element];
    }

    // Item 15, appended last and never first: About belongs after the things a player uses.
    [children addObject:[self ballpadAboutAction]];

    // Spelled the way the Home screen spells it, because this is the same fact: the menu header
    // and the app icon read from one string. BallpadAppDisplayName reads the bundle rather than
    // repeating the literal, so the capital P cannot drift from the bundle's own spelling.
    return [UIMenu menuWithTitle:BallpadAppDisplayName() children:children];
}

#pragma mark - Render resolution (item 5)

// Same title, same rows, same order, same "N×" labels as the vendored submenu. What changes is what
// a row does: the vendored body stops at the setting, this one also pins the port's render scale,
// so the row is the one place a resolution can be chosen from and the choice reaches the renderer.
- (UIMenu *)ballpadRenderMenu
{
    return [UIMenu menuWithTitle:@"Render Resolution" children:@[
        [self ballpadRenderAction:@"1× (Native)" scale:1],
        [self ballpadRenderAction:@"2×" scale:2],
        [self ballpadRenderAction:@"3×" scale:3],
        [self ballpadRenderAction:@"4×" scale:4],
    ]];
}

- (UIAction *)ballpadRenderAction:(NSString *)title scale:(NSInteger)scale
{
    __weak BallpadGameOverlay *weakSelf = self;
    UIAction *action = [UIAction actionWithTitle:title
                                          image:nil
                                     identifier:nil
                                        handler:^(__kindof UIAction *selected) {
        (void)selected;
        [SunPadSettings sharedSettings].renderScale = scale;
        [[SunPadSettings sharedSettings] synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        // The read-back is the point: "the setting reached the renderer" is a logged fact here
        // rather than an assumption. The new target lands on the next frame, where main() turns the
        // change into the swapchain resize that Aurora's own window-resize path never sees.
        PortSetRenderScale((float)scale);
        BallpadLog(@"menu: render scale %ld; port pin now %.2f",
                   (long)scale, (double)PortRenderScale());
        BallpadLogSettingsSnapshot(@"menu render scale");
        [weakSelf refreshMenuButton];
    }];
    action.state = [SunPadSettings sharedSettings].renderScale == scale ?
        UIMenuElementStateOn : UIMenuElementStateOff;
    return action;
}

#pragma mark - Aspect ratio (item 5)

- (UIMenu *)ballpadAspectMenu
{
    return [UIMenu menuWithTitle:@"Aspect Ratio" children:@[
        [self ballpadAspectAction:@"Original 4:3" mode:SunPadAspectRatioOriginal],
        [self ballpadAspectAction:@"16:9 (Experimental)" mode:SunPadAspectRatioWidescreen],
        [self ballpadAspectAction:@"Fill Screen (Experimental)" mode:SunPadAspectRatioFillScreen],
    ]];
}

- (UIAction *)ballpadAspectAction:(NSString *)title mode:(SunPadAspectRatioMode)mode
{
    __weak BallpadGameOverlay *weakSelf = self;
    UIAction *action = [UIAction actionWithTitle:title
                                          image:nil
                                     identifier:nil
                                        handler:^(__kindof UIAction *selected) {
        (void)selected;
        [SunPadSettings sharedSettings].aspectRatioMode = mode;
        [[SunPadSettings sharedSettings] synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        // Three rows, three different destinations, because pinning all three to one value would
        // make two of them a lie. 4:3 pins the shape the game was tuned at; 16:9 pins the wide
        // value the port's own aspect code knows (640 -> 854 logical pixels, with the gameplay
        // camera blend, the locked aspect and the front end moving together); Fill Screen hands the
        // aspect back to the window, which is what filling the screen means on a device whose
        // window is not 16:9 -- an iPad, or a phone at its own corner radius.
        switch (mode)
        {
            case SunPadAspectRatioOriginal:
                PortSetTargetAspect(4.0f / 3.0f);
                break;
            case SunPadAspectRatioWidescreen:
                PortSetTargetAspect(16.0f / 9.0f);
                break;
            case SunPadAspectRatioFillScreen:
                PortSetTargetAspect(-1.0f);
                break;
        }
        // The pinned value, not the framebuffer width: the width is re-derived from the new aspect
        // on the next frame, so reading it here would log the value that is on its way out.
        BallpadLog(@"menu: aspect %@; port pin now %.3f, follows window %d",
                   title, (double)PortTargetAspect(), PortAspectFollowsWindow());
        BallpadLogSettingsSnapshot(@"menu aspect ratio");
        [weakSelf refreshMenuButton];
    }];
    action.state = [SunPadSettings sharedSettings].aspectRatioMode == mode ?
        UIMenuElementStateOn : UIMenuElementStateOff;
    return action;
}

#pragma mark - Frame rate limit (items 11 and 12)

// Item 12 is why there is no performance row here: the vendored one toggled a 90% emulated CPU
// clock, and a native port has no emulated clock to slow, so the row would be a switch that does
// nothing -- the placeholder doc 33 forbids shipping. The one action below is what stands where
// item 11's row was, and it is named for what it does on this runtime.
- (UIAction *)ballpadFrameLimitAction
{
    __weak BallpadGameOverlay *weakSelf = self;
    UIAction *action =
        [UIAction actionWithTitle:@"Experimental 60 FPS (BallPad's frame rate limit)"
                            image:[UIImage systemImageNamed:@"speedometer"]
                       identifier:nil
                          handler:^(__kindof UIAction *selected) {
        (void)selected;
        BOOL unlimited = !BallpadFrameLimitIsUnlimited();
        [NSUserDefaults.standardUserDefaults setBool:unlimited
                                             forKey:BallpadFrameLimitUnlimitedKey];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];

        // No "Restart Required" in here, because nothing restarts: the limiter re-derives its period
        // on the next frame. And no promise of a faster game either -- the port's logic still
        // advances once per retrace, so lifting the cap lets frames be produced as fast as they can
        // be, which is a property of the machine, not a speed-up of the game. The alert therefore
        // reports what the port reports rather than restating the title.
        PortSetFrameLimit(unlimited ? 0.0 : -1.0);
        double limitHz = 0.0;
        double displayHz = 0.0;
        int vsync = 0;
        int pinned = 0;
        PortFrameLimitInfo(&limitHz, &displayHz, &vsync, &pinned);
        NSString *now = limitHz > 0.0
            ? [NSString stringWithFormat:@"capped to %.0f Hz", limitHz]
            : @"uncapped";
        BallpadLog(@"menu: frame limit %@; port reports %@ (display %.1f Hz, vsync %d, pinned %d)",
                   unlimited ? @"uncapped" : @"display-following", now, displayHz, vsync, pinned);
        BallpadLogSettingsSnapshot(@"menu frame rate limit");

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Frame Rate Limit"
                                               message:[NSString stringWithFormat:
                @"The port's own limiter is now %@. Frames are still produced once per retrace, so "
                 "this changes what the limiter allows rather than the game's speed; the display "
                 "reports %.1f Hz%@.",
                now, displayHz, vsync ? @" and is paced by vsync as well" : @" with no vsync reported"]
                                        preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
    }];
    action.state = BallpadFrameLimitIsUnlimited() ? UIMenuElementStateOn : UIMenuElementStateOff;
    return action;
}

#pragma mark - Audio recording (R2)

// Where the row writes. Ballpad's own log directory, because that is the one place this app owns
// that a person can reach through Files, and a recording nobody can get at is not a recording. The
// name carries the start time, so two takes in one run do not collide, and it is spelled with a
// POSIX formatter: the file name is a timestamp rather than a sentence, and a locale that writes a
// date differently would otherwise change the name of a file other tools read.
static NSString *BallpadAudioRecordingPath(void)
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [BallpadLogPath().stringByDeletingLastPathComponent
            stringByAppendingPathComponent:[NSString stringWithFormat:@"audio-%@.wav",
                                            [formatter stringFromDate:NSDate.date]]];
}

// What the file the row just closed actually holds, read back out of the file rather than
// remembered from what the row asked for. The dump's own bookkeeping -- "dumping 1" and a rising
// frame count -- is what the mixer handed to the device, and it says nothing about whether any of
// it was audible: a silent transport hands over silent frames. The bytes are the only thing that
// says, so the stop alert is built from this reading, and it can say "silent" when the take is.
typedef struct
{
    BOOL readable;          // a RIFF/WAVE file whose fmt and data chunks both parsed
    unsigned long frames;   // the data chunk's own length, in frames
    unsigned int sampleRate;
    unsigned int channels;
    unsigned int peak;      // largest |sample| in the file, 0 when every sample is zero
} BallpadRecordingReading;

// The path the current take is being written to. The stop tap has to read that file back, and the
// engine keeps no record of where it was told to write.
static NSString *s_ballpadRecordingPath;

static unsigned int BallpadReadLE(const unsigned char *p, unsigned int bytes)
{
    unsigned int value = 0;
    for (unsigned int i = 0; i < bytes; ++i)
        value |= (unsigned int)p[i] << (8 * i);
    return value;
}

// The audible floor. A 32nd-magnitude step out of 32767 is about -60 dBFS: below the noise floor
// of anything a person would call a recording, and above the stray single-bit value a silent device
// buffer can still hand over.
static const unsigned int kBallpadAudiblePeak = 32;

static BallpadRecordingReading BallpadReadRecording(NSString *path)
{
    BallpadRecordingReading reading = { NO, 0, 0, 0, 0 };
    if (path.length == 0)
        return reading;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length < 44)
        return reading;

    const unsigned char *bytes = (const unsigned char *)data.bytes;
    if (memcmp(bytes, "RIFF", 4) != 0 || memcmp(bytes + 8, "WAVE", 4) != 0)
        return reading;

    // The chunks are walked the way any reader walks them rather than by the offsets this app's own
    // writer happens to use, so a file that reached disk with its chunks in another order still
    // reads as a file.
    BOOL haveFormat = NO;
    unsigned long offset = 12;
    while (offset + 8 <= (unsigned long)data.length)
    {
        const unsigned int chunkBytes = BallpadReadLE(bytes + offset + 4, 4);
        if (memcmp(bytes + offset, "fmt ", 4) == 0 && offset + 24 <= (unsigned long)data.length)
        {
            reading.channels = BallpadReadLE(bytes + offset + 10, 2);
            reading.sampleRate = BallpadReadLE(bytes + offset + 12, 4);
            haveFormat = YES;
        }
        else if (memcmp(bytes + offset, "data", 4) == 0)
        {
            reading.frames = chunkBytes / (2 * sizeof(short));   // 2 channels of 16-bit samples
            const unsigned char *pcm = bytes + offset + 8;
            unsigned long samples = (unsigned long)reading.frames * 2;
            const unsigned long available = ((unsigned long)data.length - (offset + 8)) / 2;
            if (samples > available)
                samples = available;                              // a short file reads short, not past its end
            for (unsigned long i = 0; i < samples; ++i)
            {
                const short sample = (short)BallpadReadLE(pcm + i * 2, 2);
                const unsigned int magnitude = sample < 0 ? (unsigned int)(-(int)sample)
                                                           : (unsigned int)sample;
                if (magnitude > reading.peak)
                    reading.peak = magnitude;
            }
            reading.readable = haveFormat;
            return reading;
        }
        offset += 8 + chunkBytes + (chunkBytes & 1);   // chunks are word-aligned
    }
    return reading;
}

// The slot the vendored menu spends on an emulated CPU clock, re-bound to the thing a native port
// can actually do with it. That row's switch slowed an emulator down by 10 per cent, and this
// runtime has no emulated clock to slow, so shipping it would be the inert switch doc 33 forbids
// and rebuilding it under another name would be the same switch with a better label. The port does
// have its own mixer and its own transport, though, and the honest experimental thing to expose
// from them is the one operation a player can check for themselves: record exactly the bytes the
// audio device is handed, so "the game is making a sound" and "the sound is the one the models on
// screen are making" stop being the same question. It writes a WAV into Ballpad's log directory,
// and every part of the row -- the alert, the checkmark, the log -- reads its state back from the
// mixer's own dump fields rather than remembering what the last tap asked for.
- (UIAction *)ballpadAudioRecordingAction
{
    __weak BallpadGameOverlay *weakSelf = self;
    UIAction *action =
        [UIAction actionWithTitle:@"Record Audio (Experimental)"
                            image:[UIImage systemImageNamed:@"waveform"]
                       identifier:nil
                          handler:^(__kindof UIAction *selected) {
        (void)selected;
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];

        // One read, for the three facts this handler needs: whether the mixer ever ran, whether it
        // is dumping now, and what the transport makes of the device.
        PortAudioMixInfo mix;
        PortAudioMixStats(&mix);
        const BOOL deviceOpen = PortAudioDeviceOpen() != 0;

        NSString *title = nil;
        NSString *message = nil;

        if (mix.dumping)
        {
            // The length is taken before the stop, because stopping is what hands the file its
            // header and the count afterwards belongs to no file.
            const unsigned long frames = mix.dumpFrames;
            PortAudioDumpStop();

            // Then the file is read back, because that counter is what the mixer handed over and
            // not what the take sounds like. The Simulator showed the difference: a run where the
            // transport was silent throughout wrote a well-formed WAV whose every sample was zero,
            // and a row that stopped at the count called it a recording.
            const BallpadRecordingReading file = BallpadReadRecording(s_ballpadRecordingPath);
            NSString *audibility = nil;
            if (!file.readable)
                audibility = @"The file could not be read back to check what is in it, so its "
                              "length is the mixer's alone.";
            else if (file.frames != frames)
                audibility = [NSString stringWithFormat:
                    @"The file holds %lu frames where the mixer reported %lu, so what reached the "
                     "disk is not the whole take.",
                    file.frames, frames];
            else if (file.peak < kBallpadAudiblePeak)
                audibility = @"Nothing audible was playing while it ran: no sample in it is louder "
                              "than 31 of 32767, so this take is silence rather than a failed "
                              "recording.";
            else
                audibility = [NSString stringWithFormat:@"Its loudest sample is %u of 32767.",
                                                        file.peak];

            title = @"Recording Stopped";
            message = [NSString stringWithFormat:
                @"%lu frames, %.1f seconds at 32000 Hz. %@ The file is complete and sits with "
                 "BallPad's own log, where the Files app can reach it.",
                frames, (double)frames / 32000.0, audibility];
            BallpadLog(@"menu: audio recording stopped after %lu frames; read back %lu frames, "
                        "peak %u, %u Hz",
                       frames, file.frames, file.peak, file.sampleRate);
        }
        else if (!deviceOpen)
        {
            // An audio-off run and a device that failed to open land here together, and both of
            // them are more useful said out loud than recorded as an empty file.
            title = @"Nothing to Record";
            message = @"The port has no audio device open, so there are no bytes to write. "
                       "Sound has to be on and working before this row can record it.";
            BallpadLog(@"menu: audio recording refused; the port has no audio device open");
        }
        else
        {
            NSString *path = BallpadAudioRecordingPath();
            // Kept because the stop tap reads this file back, and reading it back is the point:
            // the engine puts the length in the header when it closes, and only the bytes say
            // whether the take is audible.
            s_ballpadRecordingPath = path;
            if (PortAudioDumpStart(path.UTF8String))
            {
                title = @"Recording";
                message = [NSString stringWithFormat:
                    @"Now writing what the audio device is given to:\n%@\n\nTap this row again "
                     "to stop; the file is finished when the stop alert names its length.", path];
                BallpadLog(@"menu: audio recording started at %@", path);
            }
            else
            {
                title = @"Recording Failed";
                message = [NSString stringWithFormat:
                    @"BallPad could not open %@ for writing. This row needs no game data and no "
                     "setting, so a failure here is the file system's.", path];
                BallpadLog(@"menu: audio recording could not open %@", path);
            }
        }

        // Written after the action, so the line and the checkmark the rebuild below publishes
        // cannot disagree about which side of the toggle this run is on.
        BallpadLogAudioTarget(@"after the record row");

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title message:message
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert animated:YES completion:nil];
        [weakSelf refreshMenuButton];
    }];

    // Read from the mixer every time the menu is built, which -refreshMenuButton causes after every
    // tap. A flag remembered in this file would be a second opinion about a recording the port owns.
    PortAudioMixInfo mix;
    PortAudioMixStats(&mix);
    action.state = mix.dumping ? UIMenuElementStateOn : UIMenuElementStateOff;
    return action;
}

#pragma mark - Game data & saves (item 9)

// The three rows are the vendored ones with the vendored handlers and the vendored icons; the
// submenu is rebuilt rather than edited because a UIMenu's children cannot be replaced in place and
// the second row's title is what item 9 changes. "SunPad Folder" becomes "BallPad Folder" and the
// handler behind it is the same one, which is the whole of that item: the row names the app it is
// in.
- (UIMenu *)ballpadGameDataMenu
{
    __weak BallpadGameOverlay *weakSelf = self;
    return [UIMenu menuWithTitle:@"Game Data & Saves" children:@[
        [UIAction actionWithTitle:@"Import or Reimport Game Data"
                            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                       identifier:nil
                          handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsGameDataChange:weakSelf];
        }],
        [UIAction actionWithTitle:@"Import from BallPad Folder"
                            image:[UIImage systemImageNamed:@"folder"]
                       identifier:nil
                          handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsGameDataFolderImport:weakSelf];
        }],
        [UIAction actionWithTitle:@"Remove Stored Game Data"
                            image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil
                          handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf confirmGameDataRemoval];
        }],
    ]];
}

#pragma mark - About & Credits (item 15)

- (UIAction *)ballpadAboutAction
{
    __weak BallpadGameOverlay *weakSelf = self;
    return [UIAction actionWithTitle:@"About & Credits…"
                               image:[UIImage systemImageNamed:@"info.circle"]
                          identifier:nil
                             handler:^(__kindof UIAction *selected) {
        (void)selected;
        BallpadLog(@"menu: about & credits opened");
        BallpadPresentOverlayViewController(weakSelf,
            [BallpadCreditsViewController creditsViewController]);
    }];
}

#pragma mark - Report a problem (item 10)

// The vendored row calls this selector, so overriding it adapts the row's destination without
// touching the row: same title, same icon, same three questions. What is different is where the
// report goes. As vendored, a Ballpad report would open the interface project's issue tracker,
// which is wrong for this app, and this assignment does not authorise messaging maintainers. So the
// report is written on this device and offered two local endings -- share sheet, or Files -- and the
// prompt says so before the report is made.
- (void)reportProblem
{
    UIViewController *presenter = self.window.rootViewController;
    if (presenter == nil)
        return;

    NSString *reportID = BallpadNewReportID();
    UIAlertController *prompt =
        [UIAlertController alertControllerWithTitle:@"Report a Problem"
                                            message:[NSString stringWithFormat:
            @"Answer briefly and BallPad will add the technical details. Nothing is uploaded: the "
             "report is written on this device and this app sends it nowhere, so the buttons below "
             "either share the file you just created or put it in Files to attach it wherever you "
             "choose. It never includes your game image, extracted files, saves, signing material, "
             "or controller inputs. Report %@.", reportID]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"What went wrong?";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Area and what you were doing (optional)";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Every time, sometimes, once, or not sure?";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

    __weak BallpadGameOverlay *weakSelf = self;
    UIAlertAction *share = [UIAlertAction actionWithTitle:@"Share Report…"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf ballpadShareReportFromPrompt:prompt reportID:reportID];
    }];
    [prompt addAction:share];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Save to Files"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf ballpadExportReportFromPrompt:prompt reportID:reportID];
    }]];
    prompt.preferredAction = share;
    [presenter presentViewController:prompt animated:YES completion:nil];
}

// One report, built the same way for both endings so the two buttons differ only in destination.
// Returns nil after saying why, because a nil report is a failure the player has to be told about
// rather than a share sheet with nothing in it.
- (NSURL *)ballpadReportURLFromPrompt:(UIAlertController *)prompt reportID:(NSString *)reportID
{
    NSDictionary<NSString *, NSString *> *answers = @{
        @"problem": prompt.textFields.count > 0 ? (prompt.textFields[0].text ?: @"") : @"",
        @"context": prompt.textFields.count > 1 ? (prompt.textFields[1].text ?: @"") : @"",
        @"frequency": prompt.textFields.count > 2 ? (prompt.textFields[2].text ?: @"") : @"",
    };
    // Both delegate answers, because a report a reader cannot tell a Simulator run from a device run
    // is a report that cannot be acted on.
    NSString *technical = [NSString stringWithFormat:@"%@\nperformance=%@",
        [self.delegate gameOverlayDiagnosticContext:self],
        [self.delegate gameOverlayPerformanceProfile:self]];
    NSError *error = nil;
    NSURL *url = BallpadDiagnosticsReportURL(reportID, answers, technical, &error);
    BallpadLog(@"report %@ written=%@ file=%@", reportID, url != nil ? @"yes" : @"no",
               url.lastPathComponent ?: (error.localizedDescription ?: @"unknown error"));
    if (url != nil)
        return url;

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Diagnostic Report Unavailable"
                                            message:error.localizedDescription
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    return nil;
}

- (void)ballpadShareReportFromPrompt:(UIAlertController *)prompt reportID:(NSString *)reportID
{
    NSURL *url = [self ballpadReportURLFromPrompt:prompt reportID:reportID];
    if (url == nil)
        return;

    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    // The popover has to point at something on iPad; the three-dot button is what the vendored flow
    // used and it is still the control this came from.
    UIButton *anchor = BallpadMenuButton(self);
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    popover.sourceView = anchor ?: self;
    popover.sourceRect = anchor != nil ? anchor.bounds
                                       : CGRectMake(CGRectGetMidX(self.bounds),
                                                    CGRectGetMinY(self.bounds) + 24.0, 1.0, 1.0);
    [self.window.rootViewController presentViewController:share animated:YES completion:nil];
}

- (void)ballpadExportReportFromPrompt:(UIAlertController *)prompt reportID:(NSString *)reportID
{
    NSURL *url = [self ballpadReportURLFromPrompt:prompt reportID:reportID];
    if (url == nil)
        return;

    // A copy, not a move: the report stays in Ballpad's own folder as the record of the report, and
    // what lands in Files is the player's to keep or send.
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
    [self.window.rootViewController presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Layout

// SunPad lays its own controls out here, from its own bounds and insets, and that stays the only
// thing that decides where a control goes. Two of its decisions are Ballpad's to make on this game's
// behalf, and both are applied after the vendored pass so the vendored layout math keeps its
// authority:
//
//   * the three-dot button gets one explicit appearance, so dismissing a primary-action menu cannot
//     synthesize a rectangular highlight over it and a rebuilt surface cannot leave it with none;
//   * a control the vendored default pass drew outside the safe rect is put back inside it, for the
//     reason -ballpadApplySafeAreaContainment gives;
//   * the right shoulder is made L's twin, for the reason its flags are documented above.
- (void)layoutSubviews
{
    [super layoutSubviews];

    BallpadConfigureMenuButton(BallpadMenuButton(self));

    // The editor, where every vendored handler returns early. R follows them, and a press already in
    // flight when the editor opens is not held into it.
    const BOOL editing = BallpadOverlayIsEditingLayout(self);
    if (editing)
        s_rightShoulderHeld = false;
    s_rightShoulderInert = editing;

    [self ballpadApplySafeAreaContainment];
    [self ballpadApplyShoulderRepair];
    [self ballpadScheduleShoulderRepair];
}

// SunPad re-lays out a control whose bounds changed after this method returns, and the trigger's own
// layout pass re-derives its border and its accessibility value when it runs -- so a repair applied
// only here would be undone by the very pass it provoked. One turn later is when that pass has
// certainly happened, and the flag coalesces a burst of layouts into one pending turn.
- (void)ballpadScheduleShoulderRepair
{
    if (s_shoulderRepairPending)
        return;
    s_shoulderRepairPending = true;
    __weak BallpadGameOverlay *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        s_shoulderRepairPending = false;
        [weakSelf ballpadApplyShoulderRepair];
    });
}

// A control the vendored default pass drew outside the surface's safe rect. -placeControl: clamps a
// *saved* origin and does not clamp its own default, and the phone defaults are normalized centres
// captured at a control size scale of 1.0 -- Z's 0.97125 is one, and it sits exactly on the safe
// rect's right edge at that scale, which is why the constant has the value it has. The scale runs to
// 1.35 globally and to 1.75 for a single control, and a control already on the edge at 1.0 grows
// straight out of the rect when the scale is raised: on the iPhone 17e the layout read-back caught
// `judged 14 outside 1 (Z {{746.328125, 131.87}, {58.21875, 58.21875}})` against a safe rect ending
// at 797, which is 7.5pt of that button under the display's rounded corner. It survived a relaunch,
// because the scale that grew the control is persisted and nothing in the default pass puts a
// default back inside.
//
// The policy applied here is the vendored file's own rather than one invented for Ballpad:
// -controlDragged: and the saved-origin branch of -placeControl: both clamp a centre into the safe
// rect with these same half-extent numbers. A control the player placed is therefore already inside
// and is left alone, the vendored pass keeps deciding where every control goes, and the only thing
// this moves is a control the vendored default pass itself put outside -- by exactly as much as it
// takes to bring it back. It runs before the shoulders are repaired, so the right shoulder mirrors a
// left shoulder that has already been brought inside.
//
// The four directional buttons are governed as one control, by their group: the vendored pass lays
// them out around the group's clamped centre and their extent *is* the group's bounds, so clamping
// one button on its own would break the cross rather than fix it.
- (void)ballpadApplySafeAreaContainment
{
    CGRect safe = self.bounds;
    if (@available(iOS 11.0, *))
        safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
    if (safe.size.width <= 0.0 || safe.size.height <= 0.0)
        return;

    NSMutableArray<UIView *> *judged = [NSMutableArray array];
    for (UIView *control in BallpadTouchControlsInDrawOrder(self))
        if (![control.accessibilityIdentifier hasPrefix:@"D_"])
            [judged addObject:control];
    UIView *dPad = BallpadControlLabelled(self, @"D-pad");
    if (dPad != nil)
        [judged addObject:dPad];

    NSMutableArray<NSString *> *moved = [NSMutableArray array];
    for (UIView *control in judged)
    {
        const CGRect drawn = [control convertRect:control.bounds toView:self];
        if (CGRectContainsRect(safe, drawn))
            continue;
        // MIN against half the safe rect as well as half the control, which is the vendored editor's
        // own guard: a control larger than the whole safe rect is centred on it rather than given a
        // clamp range that has crossed over itself.
        const CGFloat halfWidth = MIN(CGRectGetWidth(drawn) * 0.5, safe.size.width * 0.5);
        const CGFloat halfHeight = MIN(CGRectGetHeight(drawn) * 0.5, safe.size.height * 0.5);
        const CGFloat minX = CGRectGetMinX(safe) + halfWidth, maxX = CGRectGetMaxX(safe) - halfWidth;
        const CGFloat minY = CGRectGetMinY(safe) + halfHeight, maxY = CGRectGetMaxY(safe) - halfHeight;
        const CGPoint centre = CGPointMake(MIN(MAX(CGRectGetMidX(drawn), minX), maxX),
                                           MIN(MAX(CGRectGetMidY(drawn), minY), maxY));
        // A control that is outside by a rounding error is inside for every purpose that matters
        // here, and re-centring it every pass would be churn without a picture to show for it.
        if (fabs(centre.x - CGRectGetMidX(drawn)) < 0.01 &&
            fabs(centre.y - CGRectGetMidY(drawn)) < 0.01)
            continue;
        [moved addObject:[NSString stringWithFormat:@"%@ %.1f,%.1f to %.1f,%.1f",
                          control.accessibilityIdentifier ?: @"?",
                          (double)CGRectGetMidX(drawn), (double)CGRectGetMidY(drawn),
                          (double)centre.x, (double)centre.y]];
        control.center = [control.superview convertPoint:centre fromView:self];
    }

    // Only a control that actually moved is written, and only when the set of them changes: this is
    // the line that says the defect was live, so on a layout that respects the safe rect it is
    // absent rather than repeating every pass.
    if (moved.count == 0)
        return;
    NSString *line = [moved componentsJoinedByString:@"; "];
    static NSString *s_lastMoved = nil;
    if ([line isEqualToString:s_lastMoved])
        return;
    s_lastMoved = line;
    BallpadLog(@"safe area: %lu control(s) were drawn outside the surface's safe rect and are back "
               @"inside it -- %@ | insets %.1f,%.1f,%.1f,%.1f",
               (unsigned long)moved.count, line, (double)self.safeAreaInsets.left,
               (double)self.safeAreaInsets.top, (double)self.safeAreaInsets.right,
               (double)self.safeAreaInsets.bottom);
}


// R as L's twin. The vendored width is 2*small + 24*scale wider than L's, which is the spray track's
// own geometry, and its border is re-derived on every layout pass; both are undone here from L's live
// values rather than from copies of them, so the two shoulders cannot drift apart as the vendored
// numbers change.
- (void)ballpadApplyShoulderRepair
{
    UIView *left = BallpadControlLabelled(self, @"L");
    UIView *right = BallpadControlLabelled(self, @"R");
    if (left == nil || right == nil)
        return;

    if (!CGSizeEqualToSize(right.bounds.size, left.bounds.size))
        right.bounds = (CGRect){ .origin = CGPointZero, .size = left.bounds.size };
    right.layer.cornerRadius =
        MIN(CGRectGetWidth(right.bounds), CGRectGetHeight(right.bounds)) * 0.5;
    right.layer.masksToBounds = YES;
    if (!BallpadOverlayIsEditingLayout(self))
    {
        // The border is copied only at rest, and "at rest" is decided two ways, because copying a
        // *live* border was this repair's own defect.
        //
        //   * The pair comes from L once -- captured on the first pass, which runs when the overlay
        //     is built and before any touch can reach it -- and every later pass applies that
        //     captured pair. Re-reading L on each pass copies whatever L is doing at that instant,
        //     and a pass during a press on L painted L's full-press outline onto R: the read-back
        //     caught exactly that as `border L 3.0 R 3.0` with only the left shoulder touched.
        //   * A held right shoulder keeps its own border. That outline *is* the trigger's press
        //     indicator, and a layout pass during a press (a rotation, the control-hide transition,
        //     the editor's own bar) would otherwise repaint R at the at-rest width on every pass --
        //     the same defect from the other side, R pressed and drawn as if it were not.
        //
        // The editor keeps its own outline for the reason it always did: the vendored pass draws a
        // wider one on whichever shoulder is selected, and copying over it would erase the answer
        // to "which control am I resizing". Both the direct and the deferred pass ask the same
        // question, so the editor also keeps the border it draws after a bounds change.
        if (s_shoulderRestBorderColor == NULL && left.layer.borderColor != NULL &&
            left.layer.borderWidth > 0.0)
        {
            s_shoulderRestBorderWidth = left.layer.borderWidth;
            s_shoulderRestBorderColor = CGColorRetain(left.layer.borderColor);
        }
        if (s_shoulderRestBorderColor != NULL && !s_rightShoulderHeld)
        {
            right.layer.borderColor = s_shoulderRestBorderColor;
            right.layer.borderWidth = s_shoulderRestBorderWidth;
        }
    }
    BallpadHideTriggerArtwork(right);
    // The nozzle's guidance is not this button's guidance, and L carries none.
    right.accessibilityHint = nil;
    right.accessibilityValue = nil;

    // Where R is drawn, not only how big: the size, corner and border above already match L, and the
    // two shoulders were still drawn as different things because the pair is not the same *shape of
    // placement*. The vendored layout gives each shoulder its own normalized centre -- 0.0906 and
    // 0.86875 on a phone, 0.1281 and 0.8960 on a pad -- and R's is neither L's mirror nor on L's
    // row, so R was measured on this build sitting 7pt lower than L with 54pt between it and its
    // edge where L had 24. The operator's reference is the left shoulder, so R is placed where L's
    // mirror is: its distance from the surface's right edge is L's distance from the left, and it is
    // drawn on L's row. Both numbers come from L's live frame and the surface's own width rather than
    // from copies of the vendored constants, so the pair cannot drift as the vendored numbers move.
    //
    // The editor is the exception, for the reason the border above has one: while it is open the
    // player is placing this control by hand, and a repair that kept pulling R back to L's mirror
    // would be a drag that undoes itself.
    if (!BallpadOverlayIsEditingLayout(self))
    {
        CGRect mirrored = right.frame;
        mirrored.origin.x = CGRectGetWidth(self.bounds) - CGRectGetMinX(left.frame)
                            - CGRectGetWidth(mirrored);
        mirrored.origin.y = CGRectGetMinY(left.frame);
        if (!CGRectEqualToRect(mirrored, right.frame))
            right.frame = mirrored;
    }

    [self ballpadWireRightShoulder:right];

    // From this pass rather than from -layoutSubviews: the repair has just run and no vendored pass
    // has run since, so the numbers read back here are the ones that were applied. The helper writes
    // only when the geometry moved, which is what makes it safe to ask on every pass.
    BallpadLogShoulderGeometry(self, @"after the repair");
}

// Wired once. A long-press recognizer with no delay, no movement limit and no touch cancellation:
// it fires on touch-down and on release wherever on the control the finger lands, and it leaves the
// vendored pressure tracking underneath it receiving every touch, which is what keeps the two
// mechanisms from fighting each other.
- (void)ballpadWireRightShoulder:(UIView *)right
{
    static const void *wiredKey = &wiredKey;
    if (objc_getAssociatedObject(right, wiredKey) != nil)
        return;
    objc_setAssociatedObject(right, wiredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                     action:@selector(ballpadRightShoulderGesture:)];
    press.minimumPressDuration = 0.0;
    press.allowableMovement = CGFLOAT_MAX;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesBegan = NO;
    press.delaysTouchesEnded = NO;
    [right addGestureRecognizer:press];
}

- (void)ballpadRightShoulderGesture:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateBegan)
    {
        s_rightShoulderHeld = true;
        s_rightShoulderPressEdge = true;
        BallpadLogShoulderGeometry(self, @"R pressed");
    }
    else if (gesture.state == UIGestureRecognizerStateEnded ||
             gesture.state == UIGestureRecognizerStateCancelled ||
             gesture.state == UIGestureRecognizerStateFailed)
    {
        s_rightShoulderHeld = false;
        // A release is one of the two moments the vendored control re-derives its own border and
        // accessibility value, so it is one of the two moments the repair has to follow.
        [self ballpadScheduleShoulderRepair];
    }
}

@end

// ── The FPS counter (item 5) ──────────────────────────────────────────────────
// The vendored "Show FPS Counter" row persists a setting and does nothing else -- there is no FPS
// label in the vendored set at all, its own header calling the setting an emulator overlay toggle.
// On this port the numbers exist and the row has to be backed by them, so the label is Ballpad's:
// a view the overlay carries, shown while the setting is on, filled from the port's own benchmark
// once a frame. Busy time is reported next to the frame rate because busy is the figure that says
// whether the machine has headroom: paced by the display, a machine that keeps up reports the
// refresh rate whatever it is doing.
static const void *BallpadFPSCounterKey = &BallpadFPSCounterKey;
// The overlay size the label was last positioned against. The label is positioned once per surface
// shape rather than once per frame, and this is what remembers the shape.
static const void *BallpadFPSCounterShapeKey = &BallpadFPSCounterShapeKey;

// The widest reading this label can ever print, measured once. Assigning a frame invalidates the
// overlay's layout, and the overlay's layout pass re-derives every vendored control's geometry --
// including the trigger's own border, which the R repair above then has to undo. Re-framing the
// label sixty times a second therefore re-laid out the whole overlay sixty times a second, which is
// both the work the frame budget cannot spare and the reason a drag on the overlay never settled:
// a pan recognizer whose view is re-laid out under it does not reach the state the layout editor
// reads. Reserving the width up front is what makes the per-frame update a text assignment. The
// placeholder is deliberately wider than any real reading so the reservation never has to grow.
static NSString * const kBallpadFPSWidestReading =
    @"99999x99999 @99.99x aspect 99.999 pinned logical 99999 blend 99.99"
    @"   •   999 fps   99.9 ms busy   p95 99.9";

static UILabel *BallpadFPSCounterLabel(SunPadGameOverlay *overlay)
{
    UILabel *label = objc_getAssociatedObject(overlay, BallpadFPSCounterKey);
    if (label != nil)
        return label;

    label = [UILabel new];
    label.userInteractionEnabled = NO;
    label.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.accessibilityIdentifier = @"BallpadFPSCounter";
    objc_setAssociatedObject(overlay, BallpadFPSCounterKey, label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return label;
}

// The label's own geometry: sized against the widest reading rather than the current one, so the
// frame this sets is the frame it keeps, and placed inside the surface's safe area. Called when the
// label appears and when the surface changes shape, which is the whole of its layout.
static void BallpadPositionFPSCounterLabel(SunPadGameOverlay *overlay, UILabel *label)
{
    NSString *shown = label.text;
    label.text = kBallpadFPSWidestReading;
    [label sizeToFit];
    label.text = shown;

    CGRect frame = label.frame;
    frame.size.width += 16.0;
    frame.size.height = MAX(frame.size.height, 22.0);
    UIEdgeInsets insets = overlay.safeAreaInsets;
    frame.origin = CGPointMake(insets.left + 10.0, insets.top + 10.0);
    label.frame = frame;
}

static void BallpadRefreshFPSCounter(SunPadGameOverlay *overlay)
{
    UILabel *label = objc_getAssociatedObject(overlay, BallpadFPSCounterKey);
    if (![SunPadSettings sharedSettings].showFPSCounter)
    {
        // Removed rather than hidden. A hidden view is still in the accessibility tree, so the row
        // that turns the counter off would read back as if it had not, and the label would keep a
        // frame in a hierarchy that is re-laid out every frame for nothing.
        if (label != nil)
        {
            [label removeFromSuperview];
            objc_setAssociatedObject(overlay, BallpadFPSCounterKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(overlay, BallpadFPSCounterShapeKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    if (label == nil)
    {
        label = BallpadFPSCounterLabel(overlay);
        [overlay addSubview:label];
        // Once, here, because the label is added after every vendored control: nothing is added to
        // the overlay afterwards, so there is no later sibling for it to fall behind.
        [overlay bringSubviewToFront:label];
    }

    PortBenchLive live;
    PortBenchGetLive(&live);
    // The rolling window is what moves; the run counters stay put until a match is live, so a title
    // screen reads as a rate rather than as a stalled zero.
    NSString *frames = live.frames > 0
        ? [NSString stringWithFormat:@"%.0f fps   %.1f ms busy   p95 %.1f",
                                     live.fps, live.busyMs, live.busyP95Ms]
        : [NSString stringWithFormat:@"%.0f fps   %.1f ms busy", live.fps, live.busyMs];
    label.text = [NSString stringWithFormat:@"%@   •   %@", BallpadDisplayReadBack(), frames];

    // Per frame, and only this: the text. See BallpadPositionFPSCounterLabel for why the frame is
    // not part of the per-frame work.
    const CGSize surface = overlay.bounds.size;
    NSValue *placed = objc_getAssociatedObject(overlay, BallpadFPSCounterShapeKey);
    if (placed == nil || !CGSizeEqualToSize(placed.CGSizeValue, surface))
    {
        BallpadPositionFPSCounterLabel(overlay, label);
        objc_setAssociatedObject(overlay, BallpadFPSCounterShapeKey,
                                 [NSValue valueWithCGSize:surface],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The overlay is retained by the view hierarchy it is added to. The bridge is not retained by the
// overlay, so this is what keeps the menu's actions connected. All three are process-lifetime
// singletons: this build presents one window and one overlay.
@class BallpadHostUIBridge;
static SunPadGameOverlay *s_overlay = nil;
static BallpadHostUIBridge *s_bridge = nil;
// The port's SDL window, kept so a foreground resume can re-resolve the UIKit window it is
// presenting into. A rebuilt surface means a rebuilt view controller view, and the overlay has to
// follow it; holding the pointer is what makes that possible after the overlay's own window
// reference has already gone nil.
static void *s_sdlWindow = nullptr;

// Both defined with the rest of the host-UI plumbing below, forward-declared here because the
// lifecycle notification that uses them is part of the bridge.
static UIWindow *BallpadWindowForSDLWindow(void *sdlWindow);
static void BallpadReattachOverlay(NSString *reason);

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
    return [NSString stringWithFormat:@"%@ %@ (%@) on %@ %@",
                                      BallpadAppDisplayName(), version, build,
                                      device.model, device.systemVersion];
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

// Three of these four actions are Ballpad's own work now, and all three land in BallpadGameData.mm
// on the same store and the same validation the launch path uses -- so a menu row and a cold start
// cannot disagree about what "imported" means. The rows themselves are the vendored ones; only
// their destinations changed, which is the whole reason the adaptation lives here.
- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    BallpadLog(@"host ui: game data change requested; opening BallPad's importer");
    BallpadGameDataPresentImport();
}

- (void)gameOverlayRequestsGameDataFolderImport:(SunPadGameOverlay *)overlay
{
    (void)overlay;
    BallpadLog(@"host ui: game data folder import requested; opening BallPad's importer");
    BallpadGameDataPresentFolderImport();
}

- (void)gameOverlayRequestsGameDataRemoval:(SunPadGameOverlay *)overlay
{
    // The overlay put up its own confirmation before calling this, so there is no second question
    // here; what is left is to do the work and say what happened. The running game keeps the disc
    // it already resolved, so the effect of this lands on the next launch -- which is only true
    // because PortHostUIGameDataPath stops answering as soon as the record names nothing.
    int removed = BallpadGameDataRemoveStoredData();
    BallpadLog(@"host ui: game data removal confirmed by the user; %d item(s) removed", removed);

    UIViewController *presenter = overlay.window.rootViewController;
    if (presenter == nil)
        return;
    NSString *message = removed > 0
        ? [NSString stringWithFormat:
               @"BallPad's stored disc was removed. The game keeps running on the disc it already "
                "loaded; quit and open %@ again to be asked for one. Save files and control "
                "settings are not affected.", BallpadAppDisplayName()]
        : @"There was nothing stored to remove. Save files and control settings are not affected.";
    // The alert this came from is still being dismissed, and a presentation started on top of a
    // dismissal in progress is dropped, so this waits it out rather than racing it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Game Data Removed"
                                               message:message
                                        preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

// The fourth delegate action, and the one that used to be log-only. Upstream answers it with its
// own narrow A/B/X/Y/Z remap store; on this port the physical map belongs to the rendering platform
// and is chosen at start-up from STRIKERS_PAD_*, so there is no remap table to route a row into and
// a row that wrote one would be the nonfunctional placeholder doc 33 forbids. What the row can do
// honestly is show the map the port actually resolved: PortPadMapping rebuilds its table on every
// call, so a controller connected a moment ago appears when the panel is reopened or refreshed.
- (void)gameOverlayRequestsControllerMapping:(SunPadGameOverlay *)overlay
{
    BallpadLog(@"host ui: controller mapping requested; presenting the port's own pad map");
    BallpadPresentOverlayViewController(overlay,
        [BallpadControllerMappingViewController mappingViewController]);
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
    // The right shoulder's press is tracked by this side of the seam, so clearing the mixer is not
    // enough: a touch that ends while the app is away may never reach the control, and a shoulder
    // left held would be held for the rest of the session.
    s_rightShoulderHeld = false;
    s_rightShoulderPressEdge = false;
    BallpadLog(@"host ui: background; touch input released at the mixer");
}

// Logged rather than acted on: the port resumes the frame loop from its own lifecycle, so the
// useful evidence is the ordering of the three notifications around a cycle.
- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    (void)notification;
    BallpadLog(@"host ui: foreground; frame loop resumes on the port's own lifecycle");
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    [self.overlay refreshControllerVisibility];
    // The touch controls' own settings are re-read here for the same reason the controller
    // enumeration is: a foreground resume is the point at which what the user changed elsewhere --
    // in the Files-visible store, or in another scene -- can differ from what this overlay holds.
    [self.overlay applySettings];
    // And the overlay itself is re-attached. SDL rebuilds its view controller's view when the
    // surface comes back, which leaves this overlay parented to a view that is no longer on screen:
    // the game renders, the menu button is gone, and nothing about the renderer would say so. This
    // is the one place that has to notice.
    BallpadReattachOverlay(@"active");
    // The rebuilt view can arrive one main-queue turn after the notification rather than during it,
    // so the same check runs once more when the queue has drained. The second pass is a check, not a
    // second attach: it does nothing when the first one already found the overlay in place.
    dispatch_async(dispatch_get_main_queue(), ^{
        BallpadReattachOverlay(@"active-deferred");
    });
    BallpadLog(@"host ui: active; controller visibility and settings re-checked, overlay re-attached");
}

@end

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

// Where the overlay belongs: the view controller's view of the window the port renders into, which
// is the same surface PortHostUIStart attached it to. An overlay parented here lays its controls out
// against the bounds the game is actually drawn into. One left on a discarded view lays the same
// controls out for a window nobody is looking at -- the game is visible, the menu button is not --
// and nothing in the renderer would report it, which is why the resume path asks this question
// rather than assuming.
static void BallpadReattachOverlay(NSString *reason)
{
    if (s_overlay == nil)
        return;

    UIWindow *window = BallpadWindowForSDLWindow(s_sdlWindow) ?: s_overlay.window;
    if (window == nil)
    {
        // Nothing to attach to yet: a resume that has not rebuilt its window will land here and the
        // deferred pass will ask again.
        BallpadLog(@"host ui: overlay re-attach (%@) has no window yet", reason);
        return;
    }

    UIView *container = window.rootViewController.view ?: (UIView *)window;
    BOOL moved = (s_overlay.superview != container);
    if (moved)
    {
        [s_overlay removeFromSuperview];
        [container addSubview:s_overlay];
    }
    else
    {
        // Already in the right place, and still able to be behind the surface the port draws into:
        // the z-order is the half of "attached" that a superview check cannot see.
        [container bringSubviewToFront:s_overlay];
    }

    // The player's bounds are the current surface's, not the one the overlay was born on.
    s_overlay.frame = container.bounds;
    // Neither of these is set anywhere else in this build, and both are what a control-hide
    // animation's leftovers would look like; restoring them here is what makes a resume end with
    // controls rather than with a blank surface.
    s_overlay.hidden = NO;
    s_overlay.alpha = 1.0;
    [s_overlay setNeedsLayout];
    [s_overlay layoutIfNeeded];

    // Whether or not the superview moved, the button is re-derived: SunPad rebuilds its menu after
    // any inherited setting changes, and a rebuilt button carries no explicit appearance.
    BallpadConfigureMenuButton(BallpadMenuButton(s_overlay));

    if (moved)
        BallpadLog(@"host ui: overlay re-attached (%@) to %@ %@", reason,
                   NSStringFromClass(container.class), NSStringFromCGRect(container.bounds));
}

// F04: what the engine did with a control, as opposed to what the overlay drew.
//
// doc 34's F04 asks for game response rather than hittability, and the two are different readings of
// the same touch. The overlay samplers above say a control was drawn pressed; this one says what the
// engine's own pad held, read back through PortPadEngineRead, which returns the bytes
// PadStatus::s_Current[0] carries -- the sample cPlatPad::IsPressed and the game's own tasks read.
// The host's own offer is printed on the same line because the claim is the pair: a control that
// reached the engine is what F04 wants, and an offer that never did is the failure this line has to
// be able to show.
//
// The one asymmetry, and it is arithmetic rather than assumption. The port builds a frame in this
// order (src/Game/main.cpp: PortUpdateSyntheticInput, then PortHostUIFrame, then
// PortInvokePadSamplingCallback): this host's poll, then this sampler, then the engine's own
// VBlankPadUpdate, which is the pass that clamps the assembled pad and swaps it into
// PadStatus::s_Current. So the sample read here during frame N is the one the engine assembled
// during frame N-1, and the offer it was made from is the poll of frame N-1 rather than the poll
// frame N has already made. Both are printed, "now" before "prev", because the difference between
// them is exactly the thing the line has to be able to show. The first run of this line printed the
// poll of the same frame alone, and every ramp in it disagreed in a way that looked like a fault:
// a main stick of 40 beside an offer of 75, a C-stick of 44 beside an offer of 84, a trigger of 150
// beside an offer of 255. None of those is a fault, and none is even a delay: each is the game's
// own clamp of the offer made one poll earlier. The clamp is PADClampCircle
// (extern/aurora/lib/dolphin/pad/pad.cpp), whose ClampRegion is stick min 15 radius 56, C-stick min
// 15 radius 44, trigger min 30 max 180, so a trigger of 255 becomes 150 and a stick of 127 becomes
// 56. With the pair stated, the button half is exact equality and the analog half is that clamp of a
// value the reader can see, which is a row that can be judged rather than explained away.
//
// There is one more difference between the sample and the offer, and it is the port's own, not the
// engine's. When the game enables its left-analog-to-d-pad map, the port reaches into the sample it
// has just published and ORs a compass bit into the buttons when the main stick's own normalized
// value reaches 0.6 of the clamp radius -- 33.6 of 56 (src/NL/plat/platpad.cpp, the
// m_isLeftAnalogToDPadMapEnabled branch of the VBlank swap). The bucket is a 45-degree step taken
// from a 16-bit tick of nlATan2f: angleU16 = (u16)(int)(angle * 10430.378f), scaled back by
// 0.005493164 and truncated to a multiple of 45. The cast is worth stating because it wraps rather
// than rounds -- an angle a hair below the positive X axis is negative before the cast, comes back
// just under 360 degrees, and lands in the 315 bucket, DOWN|RIGHT, rather than bucket 0 -- and
// because the bucket at exactly 180 degrees is LEFT, the map having zeroed a Y that never reached
// 0.6. Those bits are in the sample without ever being in an offer, so a reader who had only the
// offers would call them presses the host never made. They are why the read-back is judged as the
// previous offer PLUS the port's own map rather than as the previous offer alone.
//
// Written only when a field changes: the port's frame loop is not a place to write a line a frame.
// STRIKERS_LOG_CONSUME gates it, the convention the port's own STRIKERS_LOG_* variables use.
static PortHostPad s_offerThis;   // the poll this frame has made; the next sample will carry it
static PortHostPad s_offerPrev;   // the poll one frame back: what this frame's sample was made from
static BOOL s_haveOffer;

static void BallpadLogConsumptionIfChanged(void)
{
    static const int s_enabled = (getenv("STRIKERS_LOG_CONSUME") != NULL) ? 1 : 0;
    if (!s_enabled)
        return;

    PortPadEngineState engine;
    if (!PortPadEngineRead(0, &engine))
        return;

    static PortPadEngineState s_lastEngine;
    static BOOL s_haveEngine = NO;
    static int s_lastScene = -12345;

    // The engine's own front-end scene, from the label BaseGameSceneManager formats and pushes: the
    // scene a control was held in, and the scene it left. Without this the row could only say the
    // pad carried a bit, and a pad that carried a bit is exactly the reading an overlay drawing a
    // press would also produce. The number is the port's, not a re-parse here.
    const int scene = PortOverlaySceneNumber();
    if (s_haveEngine
        && engine.err == s_lastEngine.err
        && engine.buttons == s_lastEngine.buttons
        && engine.stickX == s_lastEngine.stickX
        && engine.stickY == s_lastEngine.stickY
        && engine.substickX == s_lastEngine.substickX
        && engine.substickY == s_lastEngine.substickY
        && engine.triggerLeft == s_lastEngine.triggerLeft
        && engine.triggerRight == s_lastEngine.triggerRight
        && scene == s_lastScene)
        return;

    s_lastEngine = engine;
    s_haveEngine = YES;
    s_lastScene = scene;

    // consume: is the tag the runner's read-back family greps for. Both offers are on the line, in
    // the order the paragraph above explains: "now" is the poll this frame made and "prev" is the
    // one whose clamp is what the engine's own pad holds here, so a reader can compare the sample
    // against the offer it was made from and against the one it was not. The scene label is last
    // because it carries spaces and is the only field a reader does not have to machine-parse; the
    // number in front of it is the one that is compared.
    BallpadLog(@"consume: frame %lu engine err %d buttons 0x%04x stick %d,%d sub %d,%d trig %d,%d"
                " now 0x%04x nstick %d,%d nsub %d,%d ntrig %d,%d"
                " prev 0x%04x pstick %d,%d psub %d,%d ptrig %d,%d scene %d -- %s",
               PortInputFrame(),
               engine.err, engine.buttons,
               engine.stickX, engine.stickY, engine.substickX, engine.substickY,
               engine.triggerLeft, engine.triggerRight,
               s_haveOffer ? s_offerThis.buttons : 0u,
               s_haveOffer ? s_offerThis.stickX : 0,
               s_haveOffer ? s_offerThis.stickY : 0,
               s_haveOffer ? s_offerThis.substickX : 0,
               s_haveOffer ? s_offerThis.substickY : 0,
               s_haveOffer ? s_offerThis.triggerLeft : 0,
               s_haveOffer ? s_offerThis.triggerRight : 0,
               s_haveOffer ? s_offerPrev.buttons : 0u,
               s_haveOffer ? s_offerPrev.stickX : 0,
               s_haveOffer ? s_offerPrev.stickY : 0,
               s_haveOffer ? s_offerPrev.substickX : 0,
               s_haveOffer ? s_offerPrev.substickY : 0,
               s_haveOffer ? s_offerPrev.triggerLeft : 0,
               s_haveOffer ? s_offerPrev.triggerRight : 0,
               scene, PortOverlaySceneName());
}

extern "C" void PortHostUIStart(void *sdlWindow)
{
    @autoreleasepool
    {
        if (s_overlay != nil)
            return;   // once per process; a second call is a port bug, not a second window

        // Kept for the resume path: the pointer is how a rebuilt surface's window is found again
        // after the overlay's own window reference has gone nil.
        s_sdlWindow = sdlWindow;
        UIWindow *window = BallpadWindowForSDLWindow(sdlWindow);
        if (window == nil)
        {
            BallpadLog(@"host ui: no UIWindow for the port's SDL window; no touch controls");
            s_sdlWindow = nullptr;
            return;
        }

        UIView *host = window.rootViewController.view ?: window;
        // BallpadGameOverlay, not the vendored class: the only difference is the menu, and
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

        // The overlay's own log is what makes a menu action visible after the fact, and those menu
        // actions write to SunPadDiagnostics' file. Ballpad keeps a log of its own as well (item
        // 13): the vendored component's directory is a static function inside its own .mm, so it
        // cannot be redirected without editing a file whose bytes are the fidelity claim, and the
        // component legitimately keeps a log of where it is. Both files are named for their owner
        // here so a reader knows which one they are holding.
        SunPadDiagnosticsStart();
        BallpadLogStart();
        BallpadLog(@"host ui: BallPad log %@; vendored interface log %@",
                   BallpadLogPath(), SunPadDiagnosticsLogPath());

        // The frame-limit row's state is Ballpad's own key (item 11), and the port reads
        // STRIKERS_FPS_LIMIT before this hook ever runs. Re-applying it here is what makes the row's
        // choice survive a cold start rather than only the run that set it.
        PortSetFrameLimit(BallpadFrameLimitIsUnlimited() ? 0.0 : -1.0);

        BallpadLog(@"host ui: overlay %@ over %@ (%@)",
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
        BallpadLog(@"host ui: first pad poll; the port is driving this adapter");
    }

    // Read the mixer exactly once per frame, as its header requires: it clears its latched button
    // edges as it is consumed, so a second read in the same frame finds them gone, and a frame
    // that skipped the read carries a tap past the frame it belonged to.
    SunPadInputState state = [[SunPadInputMixer sharedMixer] consumeMergedState];
    out->buttons = BallpadPortButtons(state.buttons);
    out->stickX = state.stickX;
    out->stickY = state.stickY;
    out->substickX = BallpadCStickX(state.cStickX);
    out->substickY = state.cStickY;
    // Read back where the flip lands rather than where the preference lives (R1 item 5).
    BallpadLogCStickIfTurned(state.cStickX, out->substickX);
    out->triggerLeft = state.triggerL;
    out->triggerRight = state.triggerR;

    // The right shoulder's press, which the vendored control reports only from the end of its spray
    // track (see the note on the flags above). L's own handler reports the top of its analog range
    // as well as its bit, so R reports the same pair: the bit the game reads, and 255. The control's
    // own continuous pressure keeps arriving through state.triggerR and is left alone whenever it is
    // the larger of the two readings, which is the same "strongest reading wins" rule the mixer uses.
    if (BallpadRightShoulderPressed())
    {
        out->buttons |= PORT_PAD_TRIGGER_R;
        if (out->triggerRight < 255)
            out->triggerRight = 255;
    }

    // The two offers the sampler above pairs with the engine's reading. Recorded here rather than in
    // that sampler because this is the only place the whole offer exists: this struct belongs to the
    // port's frame and is gone by the time the sampler runs, and the claim is about the pair. Both are
    // kept for the reason the block above records, and the shift is ordered so that the offer this
    // poll just made becomes the sampler's "now" while the previous poll becomes its "prev" -- the
    // one the engine's own VBlank pass has already clamped into the sample the sampler will read.
    s_offerPrev = s_offerThis;
    s_offerThis = *out;
    s_haveOffer = YES;
    return 1;
}

extern "C" void PortHostUIFrame(void)
{
    @autoreleasepool
    {
        // The frame clock the audio read-back is judged against: one count per port loop iteration,
        // incremented before anything can return early, because a frame that draws nothing is still
        // a frame the game ran.
        ++s_framesPolled;

        // Before the overlay check, because this is a bridge between the store and the port rather
        // than a piece of the interface: it has to run for the whole run, including the frames
        // before the overlay exists and the frames after a lifecycle rebuild has not put one back
        // yet. See the block above for why it lives here rather than in the menu's handlers.
        BallpadApplyDisplaySettings();

        // Cheap, bounded and next to the bridge above: six comparisons a frame, one log line on the
        // frame a setting actually moved. This is the path a panel change takes to the log, since
        // the panel's own controls belong to the vendored bytes and cannot be hooked.
        BallpadLogSettingsIfPanelChanged();

        // The audio read-back on its own clock, for the same reason it exists at all: the device
        // can fail to open before any row or setting exists to report it, and a line written only
        // when something changes would leave that failure in the log as an absence.
        BallpadLogAudioIfDue();

        // The engine's own pad, for F04: the overlay samplers say a control was drawn, and this one
        // says the game read it. It sits with the bridges above rather than below the overlay check
        // for the same reason they do -- the reading is of the engine, and it is the frames with no
        // overlay (a lifecycle rebuild) where an offer with no reader would otherwise be invisible.
        BallpadLogConsumptionIfChanged();

        if (s_overlay == nil)
            return;

        // The one per-frame job here, and it is a reading rather than an invention: the FPS row's
        // counter (item 5). The overlay's own layout stays where it is -- a resize is UIKit's to
        // report -- and the GameController re-check after a foreground resume is a lifecycle
        // notification rather than a per-frame poll (N4-C), because doing it here would restart the
        // control-hide animation sixty times a second. A counter updated only when something else
        // happens is not a counter, so this one is refreshed every frame while it is shown.
        BallpadRefreshFPSCounter(s_overlay);

        // And the touch settings as the overlay draws them, which is the half of R1 item 5 the
        // store cannot answer: a slider holds a number, this holds the control that was drawn with
        // it. On a settling clock, because a drag moves the tree on every frame of the touch.
        BallpadLogOverlayTouchIfSettled(s_overlay);

        // And the shoulders' press outlines, the reading the overlay line above cannot give: a
        // press does not re-lay the tree out, so only a per-frame sample sees it. See the sampler
        // for why the pair is the value rather than a count.
        BallpadLogShoulderOutlineIfChanged(s_overlay);

        // And the safe-area verdict (F06): the same settled pass over the drawn tree as the
        // overlay read-back above, measured against the overlay's own -safeAreaInsets, which is the
        // only thing that moves when the device is turned from one landscape side to the other.
        BallpadLogLayoutIfSettled(s_overlay);
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
        s_sdlWindow = nullptr;
        overlay.delegate = nil;
        [overlay removeFromSuperview];
        s_bridge = nil;
    }
}
