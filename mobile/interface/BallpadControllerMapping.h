// Ballpad's answer to the vendored "Controller Button Mapping..." row (doc 36 R1 item 7).
//
// The row in the vendored menu calls a delegate method that the desktop sibling answers with its
// own narrow A/B/X/Y/Z remap store. That store is not what decides this app's pad: on this port the
// physical map is Aurora's, chosen when the process starts from STRIKERS_PAD_*, and there is no
// runtime remap table to route a menu row into. So this panel is deliberately read-only, and it is
// read-only for a second reason: it asks the port what the map *is* rather than describing what it
// was hoped to be. `PortPadMapping` rebuilds the table on every call, so connecting a controller and
// reopening the panel shows the map the device actually has, including the trigger-axis and
// dead-zone lines.
//
// What it does not do is invent an edit. A row that wrote a remap the engine never reads would be
// the nonfunctional placeholder doc 33 forbids, which is exactly the failure mode item 7 exists to
// avoid.

#ifndef BALLPAD_CONTROLLER_MAPPING_H
#define BALLPAD_CONTROLLER_MAPPING_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BallpadControllerMappingViewController : UIViewController

// Built on demand from the port's own pad map; there is no state to carry between openings.
+ (instancetype)mappingViewController;

@end

NS_ASSUME_NONNULL_END

#endif // BALLPAD_CONTROLLER_MAPPING_H
