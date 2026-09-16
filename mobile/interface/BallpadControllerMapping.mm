// Ballpad's controller-mapping surface. The design notes are in BallpadControllerMapping.h.

#import "BallpadControllerMapping.h"

#import "BallpadLog.h"
#import <GameController/GameController.h>
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

@interface BallpadControllerMappingViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *table;
@end

@implementation BallpadControllerMappingViewController

+ (instancetype)mappingViewController { return [self new]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UINavigationBar *bar = [UINavigationBar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:@"Controller Buttons"];
    item.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset"
        style:UIBarButtonItemStylePlain target:self action:@selector(resetMapping)];
    item.leftBarButtonItem.accessibilityIdentifier = @"BallpadMappingReset";
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
    item.rightBarButtonItem.accessibilityIdentifier = @"BallpadMappingClose";
    [bar setItems:@[item]];
    [self.view addSubview:bar];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 56.0;
    [self.view addSubview:self.table];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rebuild)
        name:GCControllerDidConnectNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rebuild)
        name:GCControllerDidDisconnectNotification object:nil];
    [self rebuild];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)rebuild { [self.table reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ return section == 0 ? 1 : section == 1 ? 5 : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{ return @[@"Controller", @"GameCube buttons", @"Other controls"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0 && GCController.controllers.count == 0)
        return @"Connect a controller in iPad or iPhone Settings. You can customize its buttons now.";
    if (section == 1)
        return @"Tap a row to change its controller button. Changes save automatically.";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
        reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (path.section == 0)
    {
        GCController *controller = GCController.controllers.firstObject;
        cell.textLabel.text = controller.vendorName ?: @"No controller connected";
        cell.imageView.image = [UIImage systemImageNamed:@"gamecontroller.fill"];
        cell.detailTextLabel.text = controller ? @"Connected" : nil;
        cell.accessibilityIdentifier = @"BallpadMappingDevice";
    }
    else if (path.section == 1)
    {
        NSString *name = BallpadRemappableGameButtonNames()[path.row];
        uint16_t button = BallpadRemappableGameButtons()[path.row].unsignedShortValue;
        NSString *bound = SunPadPhysicalControllerButtonName([self physicalButtonForGameButton:button
            inMapping:[SunPadControllerMappingStore mapping]]);
        cell.textLabel.text = [@"GameCube " stringByAppendingString:name];
        cell.detailTextLabel.text = bound;
        cell.imageView.image = [UIImage systemImageNamed:[name.lowercaseString stringByAppendingString:@".circle.fill"]];
        cell.imageView.tintColor = @[UIColor.systemGreenColor, UIColor.systemRedColor,
            UIColor.systemGrayColor, UIColor.systemGrayColor, UIColor.systemPurpleColor][path.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityIdentifier = [@"BallpadMappingBind." stringByAppendingString:name];
        cell.accessibilityValue = bound;
    }
    else
    {
        cell.textLabel.text = @[@"Move / C-stick", @"L / R triggers", @"D-pad / Start"][path.row];
        cell.detailTextLabel.text = @[@"Left / right stick", @"Left / right trigger", @"D-pad / Menu"][path.row];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1)
        [self choosePhysicalButtonAtIndex:path.row sourceView:[tableView cellForRowAtIndexPath:path]];
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
- (void)choosePhysicalButtonAtIndex:(NSInteger)index sourceView:(UIView *)sourceView
{
    NSArray<NSNumber *> *gameButtons = BallpadRemappableGameButtons();
    NSArray<NSString *> *gameNames = BallpadRemappableGameButtonNames();
    if (index < 0 || (NSUInteger)index >= gameButtons.count)
        return;
    uint16_t gameButton = (uint16_t)gameButtons[(NSUInteger)index].unsignedShortValue;
    NSString *gameName = gameNames[(NSUInteger)index];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Bind GameCube %@ to", gameName]
                         message:@"Choose a controller button. Existing assignments swap automatically."
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
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
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
