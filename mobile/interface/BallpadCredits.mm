// Ballpad's offline About & Credits surface. The design notes are in BallpadCredits.h.

#import "BallpadCredits.h"

#import "BallpadLog.h"

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
            "reconstructed game code or other third-party material.\n\n"
            "The touch overlay, layout editor, and input support build on SunPad, with its "
            "GPL-3.0 license preserved. BallPad adaptations are maintained separately from "
            "the vendored SunPad interface.";
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

#pragma mark - Readable offline documents

@interface BallpadNoticeViewController : UIViewController
@property(nonatomic, copy) NSString *noticeText;
@property(nonatomic, copy) NSString *noticeTitle;
@property(nonatomic, copy) NSString *bodyIdentifier;
@end

@implementation BallpadNoticeViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.noticeTitle;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *title = [UILabel new];
    title.text = self.noticeTitle;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory = YES;
    title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    title.accessibilityIdentifier = @"BallpadNoticeTitle";
    self.navigationItem.titleView = title;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"BallpadNoticeClose";

    UITextView *body = [UITextView new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.editable = NO;
    body.selectable = YES;
    body.backgroundColor = UIColor.systemBackgroundColor;
    body.textColor = UIColor.labelColor;
    body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    body.adjustsFontForContentSizeCategory = YES;
    body.textContainerInset = UIEdgeInsetsMake(20, 20, 28, 20);
    body.text = self.noticeText;
    body.accessibilityIdentifier = self.bodyIdentifier ?: @"BallpadNoticeBody";
    [self.view addSubview:body];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [body.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [body.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}
- (void)close { [self.navigationController popViewControllerAnimated:YES]; }
@end

// The same grouped list is used for project details and the offline notice library.
// Full revisions stay in project details, leaving the main screen readable.
@interface BallpadCreditsListController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *sections;
@property(nonatomic) BOOL rootPage;
@end

static NSDictionary *BallpadCreditRow(NSString *title, NSString *subtitle,
                                    NSString *icon, NSString *identifier,
                                    NSString *kind, id value)
{
    return @{@"title":title, @"subtitle":subtitle ?: @"", @"icon":icon ?: @"",
             @"identifier":identifier ?: @"", @"kind":kind ?: @"", @"value":value ?: @""};
}

static NSArray *BallpadNoticeRows(NSArray<NSString *> *files)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *relative in files) {
        [rows addObject:BallpadCreditRow(relative.lastPathComponent,
            relative.stringByDeletingLastPathComponent, @"doc.text",
            [@"BallpadNotice." stringByAppendingString:relative], @"notice", relative)];
    }
    return rows;
}

@implementation BallpadCreditsListController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    self.tableView.accessibilityIdentifier = self.rootPage ? @"BallpadAboutScroll" : @"BallpadCreditsDetailList";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.rootPage) {
        UILabel *title = [UILabel new];
        title.text = self.title;
        title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        title.adjustsFontForContentSizeCategory = YES;
        title.accessibilityIdentifier = @"BallpadAboutTitle";
        self.navigationItem.titleView = title;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
        self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"BallpadAboutClose";
    }
}
- (void)close { [self.navigationController.parentViewController dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{ return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{ return self.sections[section][@"footer"]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
    NSDictionary *row = self.sections[path.section][@"rows"][path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.text = row[@"title"];
    content.secondaryText = row[@"subtitle"];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:row[@"icon"]];
    content.imageProperties.tintColor = UIColor.systemBlueColor;
    cell.contentConfiguration = content;
    cell.accessibilityIdentifier = row[@"identifier"];
    BOOL actionable = [row[@"kind"] length] > 0;
    cell.accessoryType = actionable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = actionable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if ([row[@"kind"] isEqualToString:@"url"] || [row[@"kind"] isEqualToString:@"notice"])
        cell.accessibilityValue = row[@"value"];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *row = self.sections[path.section][@"rows"][path.row];
    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"url"]) {
        NSURL *url = [NSURL URLWithString:row[@"value"]];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) BallpadLog(@"about: could not open %@", url);
        }];
    } else if ([kind isEqualToString:@"list"]) {
        BallpadCreditsListController *detail = [BallpadCreditsListController new];
        detail.title = row[@"title"];
        detail.sections = row[@"value"];
        [self.navigationController pushViewController:detail animated:YES];
    } else if ([kind isEqualToString:@"notice"] || [kind isEqualToString:@"text"]) {
        BallpadNoticeViewController *detail = [BallpadNoticeViewController new];
        detail.noticeTitle = [kind isEqualToString:@"notice"] ? row[@"value"] : row[@"title"];
        detail.noticeText = [kind isEqualToString:@"notice"]
            ? BallpadStringFromFile([BallpadNoticesDirectory() stringByAppendingPathComponent:row[@"value"]])
            : row[@"value"];
        if (!detail.noticeText.length) detail.noticeText = @"This document could not be read from the bundle.";
        if ([row[@"identifier"] isEqualToString:@"BallpadAboutAttribution"])
            detail.bodyIdentifier = @"BallpadAboutBody";
        [self.navigationController pushViewController:detail animated:YES];
    }
}
@end

@implementation BallpadCreditsViewController
+ (instancetype)creditsViewController { return [self new]; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.preferredContentSize = CGSizeMake(620, 720);
    NSDictionary *manifest = BallpadNoticeManifest();
    NSArray *components = [manifest[@"components"] isKindOfClass:NSArray.class] ? manifest[@"components"] : @[];
    NSArray *notices = BallpadNoticeFiles();
    NSMutableArray *projects = [NSMutableArray array];
    NSDictionary *roles = @{@"strikers":@"Native Strikers engine and desktop port",
        @"smstrikers-decomp":@"Yannick Suter and community contributors",
        @"aurora":@"Platform and graphics support", @"sunpad":@"Touch controls, layout editor, and input support",
        @"dawn":@"WebGPU graphics backend", @"sdl3":@"Windowing, input, and haptics",
        @"musyx":@"Audio middleware", @"ode":@"Physics library", @"ffmpeg":@"THP movie decoding",
        @"aurora-vendored-libs":@"Additional graphics and platform libraries", @"googletest":@"Development tests; not shipped in the app"};
    NSDictionary *names = @{@"strikers":@"new-coke / strikers", @"smstrikers-decomp":@"Strikers decompilation",
        @"aurora":@"Aurora", @"sunpad":@"SunPad", @"dawn":@"Dawn", @"sdl3":@"SDL 3",
        @"musyx":@"MusyX", @"ode":@"Open Dynamics Engine", @"ffmpeg":@"FFmpeg",
        @"aurora-vendored-libs":@"Aurora dependencies", @"googletest":@"GoogleTest"};
    // Keep the primary credited projects together, independent of inventory ordering.
    NSArray *order = @[@"strikers", @"smstrikers-decomp", @"aurora", @"sunpad", @"dawn", @"sdl3",
                       @"musyx", @"ode", @"ffmpeg", @"aurora-vendored-libs", @"googletest"];
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSString *key in order)
        for (NSDictionary *component in components)
            if ([component[@"id"] isEqualToString:key]) [ordered addObject:component];
    for (NSDictionary *component in components)
        if (![order containsObject:component[@"id"]]) [ordered addObject:component];
    for (NSDictionary *component in ordered) {
        NSString *key = component[@"id"] ?: @"unknown";
        NSString *name = names[key] ?: component[@"name"] ?: key;
        NSMutableArray *detailRows = [NSMutableArray array];
        [detailRows addObject:BallpadCreditRow(@"License and attribution", component[@"license"],
            @"doc.text", nil, nil, nil)];
        [detailRows addObject:BallpadCreditRow(@"Source revision", component[@"revision"],
            @"chevron.left.forwardslash.chevron.right", @"BallpadAboutRevisions", nil, nil)];
        NSString *url = component[@"upstream"];
        if ([url isKindOfClass:NSString.class] && [url hasPrefix:@"https://"])
            [detailRows addObject:BallpadCreditRow(@"Open upstream project", url, @"arrow.up.right.square",
                [@"BallpadAboutLink." stringByAppendingString:key], @"url", url)];
        NSMutableArray *files = [NSMutableArray array];
        for (NSString *file in component[@"notices"])
            if ([notices containsObject:file]) [files addObject:file];
        NSArray *sections = @[@{@"title":name, @"rows":detailRows},
            @{@"title":@"Offline notices", @"rows":BallpadNoticeRows(files),
              @"footer":files.count ? @"Full license texts included with this build." : @"No separate notice files are bundled for this component."}];
        [projects addObject:BallpadCreditRow(name, roles[key] ?: component[@"name"], @"shippingbox",
            [@"BallpadAboutProject." stringByAppendingString:key], @"list", sections)];
    }
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = [NSString stringWithFormat:@"Version %@ · Build %@", info[@"CFBundleShortVersionString"] ?: @"—", info[@"CFBundleVersion"] ?: @"—"];
    NSDictionary *pin = manifest[@"engine_pin"];
    NSString *engine = [NSString stringWithFormat:@"Native Strikers engine %@", pin[@"version"] ?: @""];
    NSArray *noticeSections = @[@{@"title":@"Bundled license texts", @"rows":BallpadNoticeRows(notices),
        @"footer":notices.count ? @"Available offline. Select a document to read its full text." : @"No notices were found in this build."}];
    BallpadCreditsListController *list = [BallpadCreditsListController new];
    list.title = @"About & Credits";
    list.rootPage = YES;
    list.sections = @[
        @{@"title":@"BallPad", @"rows":@[
            BallpadCreditRow(@"Super Mario Strikers on iPhone and iPad", version, @"soccerball", @"BallpadAboutVersion", nil, nil),
            BallpadCreditRow(engine, @"Apple integration, touch adaptation, and mobile build tools by BallPad.", @"cpu", @"BallpadAboutEnginePin", nil, nil)]},
        @{@"title":@"Community", @"rows":@[
            BallpadCreditRow(@"Join the Discord", @"Updates, discussion, and testing feedback", @"bubble.left.and.bubble.right", @"BallpadAboutLink.discord", @"url", @"https://discord.gg/xwHfUD2bxW"),
            BallpadCreditRow(@"BallPad on GitHub", @"Source code, documentation, and issues", @"chevron.left.forwardslash.chevron.right", @"BallpadAboutLink.ballpad", @"url", @"https://github.com/chrissotraidis/ballpad")]},
        @{@"title":@"Built with", @"rows":projects, @"footer":@"Select a project for its source, revision, and license notices."},
        @{@"title":@"Attribution & licenses", @"rows":@[
            BallpadCreditRow(@"Full attribution", @"Contributors, local work, and rights information", @"person.2", @"BallpadAboutAttribution", @"text", BallpadCreditParagraph()),
            BallpadCreditRow(@"Bundled notices", [NSString stringWithFormat:@"%lu documents · available offline", (unsigned long)notices.count], @"doc.text", @"BallpadAboutNotices", @"list", noticeSections)],
          @"footer":@"Unofficial project. Not affiliated with Nintendo or Next Level Games. Game data is not included."}
    ];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:list];
    [self addChildViewController:navigation];
    navigation.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:navigation.view];
    [NSLayoutConstraint activateConstraints:@[
        [navigation.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [navigation.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [navigation.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navigation.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [navigation didMoveToParentViewController:self];
}
@end
