// Native grouped About & Credits, with project details and bundled offline notices.
// Source revisions come from the bundled manifest; full license text remains available
// through project details and the offline notice library.

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
