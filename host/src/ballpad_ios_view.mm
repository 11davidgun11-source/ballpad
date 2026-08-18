// Objective-C++ glue: keep SDL's auxiliary UIWindow out of the visible scene.
// Ballpad presents the EFB readback in SwiftUI; keep SDL's root view in its
// own hierarchy rather than introducing a second, unsupported re-parenting
// path. The hidden SDL window still owns the Metal bootstrap path used by
// Aurora.
#import <UIKit/UIKit.h>
#include "ballpad_ios_host.h"

static __weak UIView* g_container = nil;

extern "C" void ballpad_ios_host_set_container_view(void* uiView) {
  g_container = (__bridge UIView*)uiView;
}

extern "C" void ballpad_ios_host_attach_sdl_view(void* sdlWindowPtr) {
  if (g_container == nil) return;
  if (sdlWindowPtr == nullptr) return;
  @try {
    UIWindow* win = (__bridge UIWindow*)sdlWindowPtr;
    if (![win isKindOfClass:[UIWindow class]]) {
      NSLog(@"[ballpad] attach: window is not UIWindow (%@)", win);
      return;
    }
    // SDL's backend keeps its own UIWindow key, which can sit over the
    // SwiftUI window that hosts the EFB image + touch overlay. Hide the
    // auxiliary window and keep the SwiftUI window key. Do not re-parent the
    // SDL controller's root view: it remains owned by its own UIWindow.
    win.hidden = YES;
    UIWindow* swiftWindow = g_container.window;
    if (swiftWindow == nil) {
      for (UIWindow* w in win.windowScene.windows) {
        if (w != win && w.rootViewController != nil) {
          swiftWindow = w;
          break;
        }
      }
    }
    [swiftWindow makeKeyWindow];
    static BOOL didLog = NO;
    if (!didLog) {
      didLog = YES;
      NSLog(@"[ballpad] hid auxiliary SDL window; EFB readback owns visible output");
    }
  } @catch (NSException* e) {
    NSLog(@"[ballpad] attach failed: %@", e);
  }
}
