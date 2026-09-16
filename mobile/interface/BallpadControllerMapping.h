// Native controller settings. Edits use the shared mapping store and apply immediately.
#ifndef BALLPAD_CONTROLLER_MAPPING_H
#define BALLPAD_CONTROLLER_MAPPING_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BallpadControllerMappingViewController : UIViewController

+ (instancetype)mappingViewController;

@end

NS_ASSUME_NONNULL_END

#endif // BALLPAD_CONTROLLER_MAPPING_H
