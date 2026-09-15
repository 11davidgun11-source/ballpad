// Ballpad's offline About & Credits surface. The design notes are in BallpadCredits.h.

#import "BallpadCredits.h"

#import "BallpadLog.h"

#import <objc/runtime.h>

// The directory scripts/native/lib/notice_resources.py places, and scripts/native/verify-notices.sh
// checks against the dependency manifest. One name, read in three places below.
static NSString *const BallpadNoticesDirectoryName = @"notices";
static NSString *const BallpadNoticeListName = @"resources.txt";
static NSString *const BallpadNoticeManifestName = @"manifest.json";

static NSString *BallpadNoticesDirectory(void)
{
    return [NSBundle.mainBundle.bundlePath
            stringByAppendingPathComponent:BallpadNoticesDirectoryName];
}

static NSString *BallpadStringFromFile(NSString *path)
{
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

// The credit text doc 35 fixes, with only the app name adapted, followed by the local-contribution
// boundary. It is one string so that the sentence a reader sees on screen is the sentence the doc
// specifies rather than a paraphrase assembled from parts.
static NSString *BallpadCreditParagraph(void)
{
    return @"BallPad's native iOS/iPadOS engine is based on new-coke/strikers, a native desktop "
            "port of Super Mario Strikers. The native port builds on the community decompilation "
            "by Yannick Suter and contributors, and uses Aurora and its contributors' work for "
            "platform and graphics support. BallPad adds the iOS/iPadOS application integration, "
            "touch interface, and mobile build/test work. See the bundled third-party notices for "
            "dependency licenses and provenance.\n\n"
            "This is an unofficial project, unaffiliated with and not endorsed by Nintendo or Next "
            "Level Games. Supply your own lawfully obtained game data. The project grants no rights "
            "to redistribute game assets or disc images. Attribution does not grant rights to "
            "reconstructed game code or other third-party material.";
}

// The notice files the bundle actually carries, in the order the generated list gives them. The list
// is generated from what was copied, so reading it here is what makes this screen's inventory the
// bundle's inventory instead of a second copy that could drift.
static NSArray<NSString *> *BallpadNoticeFiles(void)
{
    NSString *listPath = [BallpadNoticesDirectory()
        stringByAppendingPathComponent:BallpadNoticeListName];
    NSString *list = BallpadStringFromFile(listPath);
    if (list.length == 0)
        return @[];

    // A row is a notice only if the bundle actually carries the file it names. The generated list
    // is a tab-separated table with a header row, so the leading '#' test and the existence test are
    // both load-bearing: without them this screen advertises an inventory the folder does not have,
    // and a row the reader cannot open renders as "this notice could not be read" -- a worse answer
    // to "what does this build bundle" than a list that simply matches the directory.
    NSString *directory = BallpadNoticesDirectory();
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *line in [list componentsSeparatedByCharactersInSet:
                            NSCharacterSet.newlineCharacterSet]) {
        if (line.length == 0 || [line hasPrefix:@"#"])
            continue;
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
        NSString *relative = fields.lastObject;
        if (relative.length == 0)
            continue;
        if (![NSFileManager.defaultManager
                fileExistsAtPath:[directory stringByAppendingPathComponent:relative]])
            continue;
        [files addObject:relative];
    }
    return files;
}

static NSDictionary *BallpadNoticeManifest(void)
{
    NSString *manifestPath = [BallpadNoticesDirectory()
        stringByAppendingPathComponent:BallpadNoticeManifestName];
    NSString *text = BallpadStringFromFile(manifestPath);
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil)
        return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
}

#pragma mark - One notice, in full

@interface BallpadNoticeViewController : UIViewController
@property(nonatomic, copy) NSString *noticeText;
@property(nonatomic, copy) NSString *noticeTitle;
@end

@implementation BallpadNoticeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.noticeTitle;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 2;
    title.accessibilityIdentifier = @"BallpadNoticeTitle";

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.accessibilityIdentifier = @"BallpadNoticeClose";
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    UITextView *body = [UITextView new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.editable = NO;
    body.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1.0];
    body.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    body.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    body.text = self.noticeText;
    body.accessibilityIdentifier = @"BallpadNoticeBody";

    [self.view addSubview:title];
    [self.view addSubview:done];
    [self.view addSubview:body];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [done.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:12.0],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [body.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [body.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [body.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16.0],
    ]];
}

- (void)close
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - The screen

@interface BallpadCreditsViewController ()
@property(nonatomic, strong) UIStackView *stack;
@end

@implementation BallpadCreditsViewController

+ (instancetype)creditsViewController
{
    return [[self alloc] init];
}

- (UILabel *)headingLabel:(NSString *)text
{
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = [UIColor colorWithWhite:0.68 alpha:1.0];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    return label;
}

- (UILabel *)bodyLabel:(NSString *)text identifier:(nullable NSString *)identifier
{
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    label.numberOfLines = 0;
    if (identifier != nil)
        label.accessibilityIdentifier = identifier;
    return label;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
    self.title = @"About & Credits";

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"About & Credits";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    title.accessibilityIdentifier = @"BallpadAboutTitle";

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.accessibilityIdentifier = @"BallpadAboutClose";
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.accessibilityIdentifier = @"BallpadAboutScroll";

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 10.0;
    _stack = stack;

    [self.view addSubview:title];
    [self.view addSubview:done];
    [self.view addSubview:scroll];
    [scroll addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [done.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:12.0],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24.0],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20.0],
    ]];

    [self buildContent];
}

- (void)buildContent
{
    NSDictionary *manifest = BallpadNoticeManifest();
    NSArray<NSString *> *notices = BallpadNoticeFiles();
    NSArray<NSDictionary *> *components = [manifest[@"components"] isKindOfClass:NSArray.class]
        ? manifest[@"components"] : @[];

    [_stack addArrangedSubview:[self bodyLabel:BallpadCreditParagraph()
                                    identifier:@"BallpadAboutBody"]];

    // The engine pin, quoted from the shipped inventory rather than typed here: the revision a
    // reader checks against the repository has to be the revision this build was made from.
    NSDictionary *enginePin = [manifest[@"engine_pin"] isKindOfClass:NSDictionary.class]
        ? manifest[@"engine_pin"] : nil;
    if (enginePin != nil) {
        NSString *pinned = [NSString stringWithFormat:@"Engine pin: %@ %@ (%@), patch series %@.",
                            enginePin[@"repository"] ?: @"?",
                            enginePin[@"version"] ?: @"?",
                            enginePin[@"revision"] ?: @"?",
                            enginePin[@"patch_series"] ?: @"?"];
        [_stack addArrangedSubview:[self bodyLabel:pinned identifier:@"BallpadAboutEnginePin"]];
    }

    [_stack addArrangedSubview:[self headingLabel:@"Contributors and their projects"]];
    for (NSDictionary *component in components) {
        NSString *url = component[@"upstream"];
        if (![url isKindOfClass:NSString.class] || ![url hasPrefix:@"http"])
            continue;
        NSString *identifier = [@"BallpadAboutLink." stringByAppendingString:
                                component[@"id"] ?: @"unknown"];
        UIButton *link = [self buttonWithTitle:component[@"name"] ?: url
                                    identifier:identifier
                                         value:url
                                        action:@selector(openLink:)];
        [_stack addArrangedSubview:link];
    }

    [_stack addArrangedSubview:[self headingLabel:@"Pinned revisions"]];
    NSMutableString *revisions = [NSMutableString string];
    for (NSDictionary *component in components) {
        [revisions appendFormat:@"%@ -- %@ -- %@\n",
         component[@"name"] ?: component[@"id"] ?: @"?",
         component[@"revision"] ?: @"?",
         component[@"license"] ?: @"?"];
    }
    [_stack addArrangedSubview:[self bodyLabel:revisions.length > 0 ? revisions : @"unavailable"
                                    identifier:@"BallpadAboutRevisions"]];

    // Every notice the bundle carries, each one openable to its verbatim text. An empty list is
    // reported as what it is: this app was built without its notices, which is a failure the screen
    // should show rather than a screen that quietly looks finished.
    NSString *heading = notices.count > 0
        ? [NSString stringWithFormat:@"Bundled notices (%lu, offline)", (unsigned long)notices.count]
        : @"Bundled notices (none found in this bundle)";
    [_stack addArrangedSubview:[self headingLabel:heading]];
    for (NSString *relative in notices) {
        NSString *identifier = [@"BallpadNotice." stringByAppendingString:relative];
        UIButton *notice = [self buttonWithTitle:relative
                                      identifier:identifier
                                           value:relative
                                          action:@selector(openNotice:)];
        [_stack addArrangedSubview:notice];
    }
}

- (UIButton *)buttonWithTitle:(NSString *)title
                   identifier:(NSString *)identifier
                        value:(NSString *)value
                       action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    button.titleLabel.numberOfLines = 2;
    button.accessibilityIdentifier = identifier;
    // The destination is published rather than only reachable by tapping: it is the part of an
    // "opens relevant links" claim that can be read back without leaving the app.
    button.accessibilityValue = value;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)openLink:(UIButton *)button
{
    NSString *url = button.accessibilityValue;
    if (url.length == 0)
        return;
    BallpadLog(@"about: opening %@", url);
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url]
                                     options:@{}
                           completionHandler:^(BOOL success) {
        if (!success)
            BallpadLog(@"about: could not open %@", url);
    }];
}

- (void)openNotice:(UIButton *)button
{
    NSString *relative = button.accessibilityValue;
    NSString *path = [BallpadNoticesDirectory() stringByAppendingPathComponent:relative];
    NSString *text = BallpadStringFromFile(path);
    BallpadNoticeViewController *notice = [BallpadNoticeViewController new];
    notice.noticeTitle = relative;
    notice.noticeText = text.length > 0 ? text : @"This notice could not be read from the bundle.";
    notice.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:notice animated:YES completion:nil];
}

- (void)close
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
