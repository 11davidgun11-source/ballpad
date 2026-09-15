// Ballpad's offline About & Credits surface (doc 36 R1 row 15, doc 34 F13).
//
// The requirement is specific: the About screen names upstream contributors, opens the relevant
// links, and displays the full bundled notices with no network. So this screen has three parts and
// all three are read out of the shipped bundle rather than retyped here:
//
//   * the credit text from doc 35, with the app name adapted and nothing else changed;
//   * the pinned revisions, listed from notices/manifest.json, which is the same inventory
//     scripts/native/verify-notices.sh checks the bundle against -- so a component that is in the
//     notice list but not on this screen, or the reverse, is a visible disagreement rather than a
//     silent one;
//   * every notice file the bundle carries, listed from notices/resources.txt (itself generated
//     from what was actually copied) and openable to its full verbatim text.
//
// What it deliberately does not do is claim more than that. There is no all-code-CC0 statement, no
// affiliation, and no rights claim over reconstructed material; the closing paragraph says so, and
// it is the doc 35 text rather than a paraphrase.

#ifndef BALLPAD_CREDITS_H
#define BALLPAD_CREDITS_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BallpadCreditsViewController : UIViewController

// Builds the screen from the running bundle's notices/ directory.
+ (instancetype)creditsViewController;

@end

NS_ASSUME_NONNULL_END

#endif // BALLPAD_CREDITS_H
