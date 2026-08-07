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
    UIView* sdlView = win.rootViewController.view;
    if (sdlView == nil) return;
    if (sdlView.superview == g_container) return;
    sdlView.translatesAutoresizingMaskIntoConstraints = NO;
    [g_container addSubview:sdlView];
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
