// Objective-C++ glue: re-parent SDL's UIWindow root view into the host container.
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
    // SDL's backend keeps its own UIWindow key, which sits over the SwiftUI
    // window that hosts the EFB image + touch overlay (the SDL window shows as
    // opaque black and hides the game). Its view is re-parented here, so the
    // window itself is not needed — hide it and keep the SwiftUI window key
    // on every attach (SDL re-shows it on present).
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
    UIView* sdlView = win.rootViewController.view;
    if (sdlView == nil) return;
    if (sdlView.superview == g_container) return;
    NSLog(@"[ballpad] attach sdlWindow=%@ containerWindow=%@ keyWindow=%@ sceneWindows=%lu",
          win, g_container.window, UIApplication.sharedApplication.keyWindow,
          (unsigned long)win.windowScene.windows.count);
    sdlView.translatesAutoresizingMaskIntoConstraints = NO;
    [g_container insertSubview:sdlView atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
      [sdlView.leadingAnchor constraintEqualToAnchor:g_container.leadingAnchor],
      [sdlView.trailingAnchor constraintEqualToAnchor:g_container.trailingAnchor],
      [sdlView.topAnchor constraintEqualToAnchor:g_container.topAnchor],
      [sdlView.bottomAnchor constraintEqualToAnchor:g_container.bottomAnchor],
    ]];
    NSLog(@"[ballpad] attached SDL view into host container");
  } @catch (NSException* e) {
    NSLog(@"[ballpad] attach failed: %@", e);
  }
}
