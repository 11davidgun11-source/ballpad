// Ballpad's answer to the vendored "Controller Button Mapping..." row (doc 36 R1 item 7).
//
// Two maps decide a physical controller on this app, and the panel shows both rather than picking
// one and describing it as the mapping. The rendering platform's table is Aurora's, chosen when the
// process starts from STRIKERS_PAD_*, and it is read-only here because no running menu row can reach
// it; `PortPadMapping` rebuilds that table on every call, so connecting a controller and reopening
// the panel shows the device's real map including its trigger-axis and dead-zone lines.
//
// The second map is Ballpad's own and it is editable, which is the part worth stating rather than
// assuming. The vendored interface ships a narrow A/B/X/Y/Z remap store
// (`SunPadControllerMappingStore`) whose validity rule is that the five physical buttons are used
// exactly once, and Ballpad's bridge reads that store per sample when it translates a controller. So
// a rebind here is in force on the next sample rather than on the next launch, the store is the only
// place the value lives, and every row is redrawn from it -- there is no second copy for the panel to
// drift from and no edit the engine ignores. Assigning is a swap, so the valid set stays the reachable
// set by construction.
//
// Below both maps the panel prints two readings: what Ballpad's bridge last published into the
// vendored mixer's controller half, and the engine's own pad one pad-assembly boundary later. They
// are the pair doc 34's F12 is taken at, and having both on one screen is what lets a reader tell a
// connected controller apart from one the game is reading.

#ifndef BALLPAD_CONTROLLER_MAPPING_H
#define BALLPAD_CONTROLLER_MAPPING_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BallpadControllerMappingViewController : UIViewController

// Built on demand. Every value it shows is read when it opens -- the platform's table, Ballpad's
// own map and the two pad read-backs -- so there is no state to carry between openings.
+ (instancetype)mappingViewController;

@end

NS_ASSUME_NONNULL_END

#endif // BALLPAD_CONTROLLER_MAPPING_H
