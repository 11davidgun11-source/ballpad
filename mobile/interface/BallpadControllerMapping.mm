// Ballpad's controller-mapping surface. The design notes are in BallpadControllerMapping.h.

#import "BallpadControllerMapping.h"

#import "BallpadLog.h"
#import "BallpadPhysicalControllers.h"

// The port's read-back surface for the physical map. include/port/input.h is plain C with no engine
// dependency on purpose, which is why the adapter can include it directly in a UIKit translation
// unit.
#include "port/input.h"

// Which port the panel describes. The engine has four; this app's pad, touch controls and
// controller all land on the first, and a panel that listed three empty ports would be noise.
static unsigned int const BallpadMappedPort = 0;

// The five GameCube buttons the vendored store remaps, as the store's own keys in the store's own
// order (`SunPadControllerMapping.mm`, `SunPadMappingKeys`), so the panel's rows and the persisted
// keys stay one list rather than two that have to be kept in agreement.
static NSArray<NSNumber *> *BallpadRemappableGameButtons(void)
{
    return @[ @(SunPadButtonA), @(SunPadButtonB), @(SunPadButtonX), @(SunPadButtonY),
              @(SunPadButtonZ) ];
}

static NSArray<NSString *> *BallpadRemappableGameButtonNames(void)
{
    return @[ @"A", @"B", @"X", @"Y", @"Z" ];
}

// The five physical buttons the map may bind to, in the vendored order:
// `SunPadControllerButtonMappingIsValid` accepts exactly this set, once each, and nothing else.
static NSArray<NSNumber *> *BallpadPhysicalButtonChoices(void)
{
    return @[ @(SunPadPhysicalControllerButtonA),
              @(SunPadPhysicalControllerButtonB),
              @(SunPadPhysicalControllerButtonX),
              @(SunPadPhysicalControllerButtonY),
              @(SunPadPhysicalControllerButtonLeftShoulder) ];
}

@interface BallpadControllerMappingViewController ()
@property(nonatomic, strong) UIStackView *stack;
@end

@implementation BallpadControllerMappingViewController

+ (instancetype)mappingViewController
{
    return [self new];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.97];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Controller Button Mapping";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    title.accessibilityIdentifier = @"BallpadMappingTitle";

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset setTitle:@"Reset" forState:UIControlStateNormal];
    reset.accessibilityIdentifier = @"BallpadMappingReset";
    [reset addTarget:self action:@selector(resetMapping)
        forControlEvents:UIControlEventTouchUpInside];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    [refresh setTitle:@"Refresh" forState:UIControlStateNormal];
    refresh.accessibilityIdentifier = @"BallpadMappingRefresh";
    [refresh addTarget:self action:@selector(rebuild) forControlEvents:UIControlEventTouchUpInside];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"Done" forState:UIControlStateNormal];
    close.accessibilityIdentifier = @"BallpadMappingClose";
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    // Reset sits first because it is the way back from the one thing this panel changes: the
    // vendored store is what decides the app's own map, and clearing its key is the interface's own
    // definition of the default. Refresh is what makes the platform table honest after a controller
    // is plugged in -- the port rebuilds that table on every call, so asking again is the way to see
    // the device that was just connected -- and it re-reads the store at the same time, which is
    // also the way to see a map that was stored by another device or another run.
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[reset, refresh, close]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 16.0;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.showsVerticalScrollIndicator = YES;

    _stack = [UIStackView new];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 6.0;
    [scroll addSubview:_stack];

    [self.view addSubview:title];
    [self.view addSubview:actions];
    [self.view addSubview:scroll];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [actions.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [actions.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20.0],
        [_stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20.0],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20.0],
    ]];

    [self rebuild];
}

// The whole body is regenerated rather than edited: the port's rows are rebuilt on every call and
// the strings belong to its static table only until the next one, so a view that cached them would
// be showing text that no longer exists.
- (void)rebuild
{
    for (UIView *view in _stack.arrangedSubviews.copy)
        [view removeFromSuperview];

    const PortPadRow *rows = NULL;
    int count = PortPadMapping(BallpadMappedPort, &rows);
    const char *device = PortPadName(BallpadMappedPort);
    const char *detail = PortPadDetail(BallpadMappedPort);

    // Copied now, while they are still valid.
    NSString *deviceName = device != NULL ? @(device) : nil;
    NSString *deviceDetail = detail != NULL ? @(detail) : nil;

    if (deviceName.length > 0)
    {
        [_stack addArrangedSubview:[self label:deviceName
                                          font:[UIFont systemFontOfSize:15.0
                                                weight:UIFontWeightSemibold]
                                  identifier:@"BallpadMappingDevice"]];
        if (deviceDetail.length > 0)
            [_stack addArrangedSubview:[self label:deviceDetail
                                              font:[UIFont systemFontOfSize:12.0
                                                    weight:UIFontWeightRegular]
                                      identifier:@"BallpadMappingDetail"]];
    }
    else
    {
        // An empty port is what the port's own API answers with, so it is reported as itself
        // rather than dressed up as a map with nothing in it. The number is the human one for
        // BallpadMappedPort, so the sentence cannot disagree with the port actually queried.
        NSString *emptyPort =
            [NSString stringWithFormat:@"This device reports no pad map for port %u.",
                                       BallpadMappedPort + 1];
        [_stack addArrangedSubview:[self label:emptyPort
                                          font:[UIFont systemFontOfSize:15.0
                                                weight:UIFontWeightRegular]
                                  identifier:@"BallpadMappingDevice"]];
    }

    [_stack addArrangedSubview:[self label:@"GameCube control  →  this device"
                                      font:[UIFont monospacedSystemFontOfSize:12.0
                                            weight:UIFontWeightSemibold]
                              identifier:@"BallpadMappingHeading"]];

    for (int i = 0; i < count; i++)
    {
        const char *pad = rows[i].pad != NULL ? rows[i].pad : "?";
        const char *native = rows[i].native != NULL ? rows[i].native : "(none)";
        NSString *text = [NSString stringWithFormat:@"%s  →  %s", pad, native];
        NSString *identifier = [@"BallpadMappingRow." stringByAppendingString:@(pad)];
        [_stack addArrangedSubview:[self label:text
                                          font:[UIFont monospacedSystemFontOfSize:13.0
                                                weight:UIFontWeightRegular]
                                  identifier:identifier]];
    }

    // ── The map BallPad's own bridge applies, and it is editable ────────────────────────────
    //
    // Two maps decide a physical controller here and the panel shows both: the rendering platform's
    // table above, which this app cannot reach, and this one, which is the app's own. The vendored
    // store is the single source for the second -- the bridge reads the store per sample when it
    // translates a controller, so an edit is in force on the next sample rather than on the next
    // launch -- and every row below is drawn from the store rather than from what the row last
    // wrote.
    [_stack addArrangedSubview:[self label:@"BallPad's map: GameCube button  ←  physical button"
                                      font:[UIFont monospacedSystemFontOfSize:12.0
                                            weight:UIFontWeightSemibold]
                              identifier:@"BallpadMappingBridgeHeading"]];

    SunPadControllerButtonMapping map = [SunPadControllerMappingStore mapping];
    NSArray<NSNumber *> *gameButtons = BallpadRemappableGameButtons();
    NSArray<NSString *> *gameNames = BallpadRemappableGameButtonNames();
    for (NSUInteger index = 0; index < gameButtons.count; index++)
    {
        uint16_t gameButton = (uint16_t)gameButtons[index].unsignedShortValue;
        NSString *gameName = gameNames[index];
        NSString *boundName = SunPadPhysicalControllerButtonName(
            [self physicalButtonForGameButton:gameButton inMapping:map]);
        UIButton *binding = [UIButton buttonWithType:UIButtonTypeSystem];
        binding.translatesAutoresizingMaskIntoConstraints = NO;
        [binding setTitle:[NSString stringWithFormat:@"%@  ←  %@", gameName, boundName]
                 forState:UIControlStateNormal];
        binding.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        binding.titleLabel.font = [UIFont monospacedSystemFontOfSize:13.0
                                                             weight:UIFontWeightRegular];
        binding.accessibilityIdentifier = [@"BallpadMappingBind." stringByAppendingString:gameName];
        binding.tag = (NSInteger)index;
        [binding addTarget:self action:@selector(choosePhysicalButton:)
          forControlEvents:UIControlEventTouchUpInside];
        [_stack addArrangedSubview:binding];
    }

    [_stack addArrangedSubview:[self label:
        @"Tap a row to rebind it. The button that held the binding takes the one it swaps with, so "
         "the five physical buttons map to the five GameCube buttons one for one and there is no "
         "binding that can leave another unbound. The map is stored on this device under the "
         "interface's own key and survives relaunch. Sticks, D-pad, Start, the right shoulder and "
         "both analog triggers keep their direct mappings, which is the scope the store itself "
         "declares."
                                      font:[UIFont systemFontOfSize:12.0
                                            weight:UIFontWeightRegular]
                              identifier:@"BallpadMappingBridgeNote"]];

    // ── What the bridge published, and what the game holds ──────────────────────────────────
    //
    // A map describes what should happen; these two are readings of what did. The first is the last
    // state BallPad's bridge pushed into the vendored mixer's controller half, the second is the
    // engine's own pad one pad-assembly boundary later. They are the pair doc 34's F12 is taken at,
    // and printing both is what lets a reader tell "a controller is connected" apart from "the game
    // is reading one": the second is the pad the game's own tasks read.
    BallpadPhysicalControllers *bridge = [BallpadPhysicalControllers sharedControllers];
    SunPadInputState published = (SunPadInputState){0};
    BOOL havePublished = [bridge readPlayer:0 state:&published];
    NSString *bridgeLine =
        havePublished
            ? [NSString stringWithFormat:
                   @"controllers connected %lu | slot 1 last published: buttons 0x%04x stick %d,%d "
                    "cstick %d,%d triggers %u,%u connected %d",
                   (unsigned long)bridge.connectedControllerCount, published.buttons,
                   published.stickX, published.stickY, published.cStickX, published.cStickY,
                   published.triggerL, published.triggerR, published.connected]
            : [NSString stringWithFormat:@"controllers connected %lu | slot 1 has published nothing",
                                       (unsigned long)bridge.connectedControllerCount];
    [_stack addArrangedSubview:[self label:bridgeLine
                                      font:[UIFont monospacedSystemFontOfSize:12.0
                                            weight:UIFontWeightRegular]
                              identifier:@"BallpadMappingBridgeState"]];

    PortPadEngineState engine = (PortPadEngineState){0};
    if (PortPadEngineRead(BallpadMappedPort, &engine) != 0)
    {
        // `cPlatPad::IsConnected` reads PAD_ERR_NONE (0) and -3 as connected, so the word beside the
        // number is the port's own rule rather than a second opinion about the same field.
        BOOL engineConnected = (engine.err == 0 || engine.err == -3);
        NSString *engineLine = [NSString stringWithFormat:
            @"the game's own pad, port %u: err %d (%@) buttons 0x%04x stick %d,%d cstick %d,%d "
             "triggers %d,%d",
            BallpadMappedPort + 1, engine.err, engineConnected ? @"connected" : @"no pad",
            engine.buttons, engine.stickX, engine.stickY, engine.substickX, engine.substickY,
            engine.triggerLeft, engine.triggerRight];
        [_stack addArrangedSubview:[self label:engineLine
                                          font:[UIFont monospacedSystemFontOfSize:12.0
                                                weight:UIFontWeightRegular]
                                  identifier:@"BallpadMappingEngineState"]];
    }

    [_stack addArrangedSubview:[self label:
        @"The table at the top is the rendering platform's and is read-only here: it is chosen when "
         "the app starts, from the STRIKERS_PAD_* environment, and no running menu row can change "
         "it. The map and the two readings under it are BallPad's own. BallPad's touch controls are "
         "configured under Touch Control Settings."
                                      font:[UIFont systemFontOfSize:12.0
                                            weight:UIFontWeightRegular]
                              identifier:@"BallpadMappingNote"]];

    BallpadLog(@"mapping panel: read the platform table (%d rows) and BallPad's map "
                @"(a 0x%02x b 0x%02x x 0x%02x y 0x%02x z 0x%02x)",
               count, (unsigned)map.gameA, (unsigned)map.gameB, (unsigned)map.gameX,
               (unsigned)map.gameY, (unsigned)map.gameZ);
}

- (UILabel *)label:(NSString *)text font:(UIFont *)font identifier:(NSString *)identifier
{
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = [UIColor colorWithWhite:0.93 alpha:1.0];
    label.numberOfLines = 0;
    label.accessibilityIdentifier = identifier;
    return label;
}

// The physical button a GameCube button is bound to, read out of the mapping the store just
// returned rather than out of anything kept here, so a row cannot outlive the value it describes.
- (SunPadPhysicalControllerButton)physicalButtonForGameButton:(uint16_t)gameButton
                                                   inMapping:(SunPadControllerButtonMapping)mapping
{
    switch (gameButton)
    {
        case SunPadButtonA: return mapping.gameA;
        case SunPadButtonB: return mapping.gameB;
        case SunPadButtonX: return mapping.gameX;
        case SunPadButtonY: return mapping.gameY;
        case SunPadButtonZ: return mapping.gameZ;
        default: return (SunPadPhysicalControllerButton)0;
    }
}

// Which physical button the person wants, asked once per rebind. Every one of the five is offered
// including the one already bound, because choosing it is a no-op the store itself recognises rather
// than an edit that has to be filtered out here.
- (void)choosePhysicalButton:(UIButton *)sender
{
    NSArray<NSNumber *> *gameButtons = BallpadRemappableGameButtons();
    NSArray<NSString *> *gameNames = BallpadRemappableGameButtonNames();
    if (sender.tag < 0 || (NSUInteger)sender.tag >= gameButtons.count)
        return;
    uint16_t gameButton = (uint16_t)gameButtons[(NSUInteger)sender.tag].unsignedShortValue;
    NSString *gameName = gameNames[(NSUInteger)sender.tag];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Bind GameCube %@ to", gameName]
                         message:@"The button that holds this binding takes the one it is swapped "
                                  "with, so both stay bound."
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *choice in BallpadPhysicalButtonChoices())
    {
        SunPadPhysicalControllerButton physical =
            (SunPadPhysicalControllerButton)choice.unsignedCharValue;
        NSString *title = SunPadPhysicalControllerButtonName(physical);
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self assignPhysicalButton:physical toGameButton:gameButton named:gameName];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    // An action sheet is a popover on iPad and needs an anchor; the row that opened it is the
    // honest one, since that is what the person tapped.
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// Assigning is a swap rather than a write: `SunPadControllerButtonMappingByAssigning` moves whatever
// held the chosen physical button into the slot that was vacated, so the map stays a permutation of
// the five physical buttons and there is no state the store would have to reject.
- (void)assignPhysicalButton:(SunPadPhysicalControllerButton)physical
                toGameButton:(uint16_t)gameButton
                       named:(NSString *)gameName
{
    SunPadControllerButtonMapping after =
        SunPadControllerButtonMappingByAssigning([SunPadControllerMappingStore mapping], physical,
                                                 gameButton);
    // The store refuses anything that is not a permutation of the five physical buttons, so this
    // check exists to make such a result loud in the log rather than to guard a state the rows can
    // reach; nothing is stored when it fires.
    if (!SunPadControllerButtonMappingIsValid(after))
    {
        BallpadLog(@"mapping panel: refused GameCube %@ to physical %@ -- the result is not the five "
                    @"physical buttons once each",
                   gameName, SunPadPhysicalControllerButtonName(physical));
        return;
    }
    [SunPadControllerMappingStore setMapping:after];
    BallpadLog(@"mapping panel: bound GameCube %@ to physical %@ "
                @"(a 0x%02x b 0x%02x x 0x%02x y 0x%02x z 0x%02x)",
               gameName, SunPadPhysicalControllerButtonName(physical), (unsigned)after.gameA,
               (unsigned)after.gameB, (unsigned)after.gameX, (unsigned)after.gameY,
               (unsigned)after.gameZ);
    [self rebuild];
}

- (void)resetMapping
{
    [SunPadControllerMappingStore reset];
    SunPadControllerButtonMapping mapping = [SunPadControllerMappingStore mapping];
    BallpadLog(@"mapping panel: reset to the interface's default "
                @"(a 0x%02x b 0x%02x x 0x%02x y 0x%02x z 0x%02x)",
               (unsigned)mapping.gameA, (unsigned)mapping.gameB, (unsigned)mapping.gameX,
               (unsigned)mapping.gameY, (unsigned)mapping.gameZ);
    [self rebuild];
}

- (void)close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
