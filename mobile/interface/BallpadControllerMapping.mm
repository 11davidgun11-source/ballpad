// Ballpad's controller-mapping surface. The design notes are in BallpadControllerMapping.h.

#import "BallpadControllerMapping.h"

#import "BallpadLog.h"

// The port's read-back surface for the physical map. include/port/input.h is plain C with no engine
// dependency on purpose, which is why the adapter can include it directly in a UIKit translation
// unit.
#include "port/input.h"

// Which port the panel describes. The engine has four; this app's pad, touch controls and
// controller all land on the first, and a panel that listed three empty ports would be noise.
static unsigned int const BallpadMappedPort = 0;

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

    // The two buttons are one row because Refresh is what makes this panel honest after a
    // controller is plugged in: the port rebuilds its table on every call, so asking again is the
    // way to see the device that was just connected.
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[refresh, close]];
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

    [_stack addArrangedSubview:[self label:
        @"This panel only reports. The physical map belongs to the rendering platform and is "
         "chosen when the app starts, from the STRIKERS_PAD_* environment; nothing here changes "
         "it, and no row here claims to. BallPad's own touch controls are configured under "
         "Touch Control Settings."
                                      font:[UIFont systemFontOfSize:12.0
                                            weight:UIFontWeightRegular]
                              identifier:@"BallpadMappingNote"]];
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

- (void)close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
