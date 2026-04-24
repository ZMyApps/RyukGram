#import "SCIBackupScopePickerVC.h"
#import "SCIBackupDetailVC.h"
#import "../Utils.h"
#import "../Localization/SCILocalization.h"

#pragma mark - Row model

typedef NS_ENUM(NSInteger, SCIPickerRowKind) {
    SCIPickerRowKindScope,
    SCIPickerRowKindJSON,
};

@interface SCIPickerRow : NSObject
@property (nonatomic, assign) SCIPickerRowKind kind;
@property (nonatomic, assign) SCIBackupScopePickerMask scope;   // only for Scope
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIColor *iconColor;
@end
@implementation SCIPickerRow @end

#pragma mark - Cell

@interface SCIPickerCell : UITableViewCell
@property (nonatomic, strong) UIButton *checkboxButton;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, copy) void(^onToggle)(void);
@end

@implementation SCIPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (!self) return self;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    _checkboxButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _checkboxButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_checkboxButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_checkboxButton];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:12];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    _subtitleLabel.numberOfLines = 2;
    [self.contentView addSubview:_subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_checkboxButton.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_checkboxButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_checkboxButton.widthAnchor constraintEqualToConstant:30],
        [_checkboxButton.heightAnchor constraintEqualToConstant:30],

        [_iconView.leadingAnchor constraintEqualToAnchor:_checkboxButton.trailingAnchor constant:12],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:22],
        [_iconView.heightAnchor constraintEqualToConstant:22],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)toggleTapped { if (self.onToggle) self.onToggle(); }

- (void)setChecked:(BOOL)checked enabled:(BOOL)enabled {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    NSString *name = checked ? @"checkmark.circle.fill" : @"circle";
    UIImage *img = [[UIImage systemImageNamed:name] imageByApplyingSymbolConfiguration:cfg];
    [self.checkboxButton setImage:img forState:UIControlStateNormal];
    self.checkboxButton.tintColor = checked ? ([SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor])
                                            : [UIColor systemGray3Color];
    self.checkboxButton.enabled = enabled;
    self.contentView.alpha = enabled ? 1.0 : 0.45;
    self.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.userInteractionEnabled = enabled;
}
@end

#pragma mark - VC

@interface SCIBackupScopePickerVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, assign) SCIBackupScopePickerMask selection;
@property (nonatomic, copy) NSArray<SCIPickerRow *> *rows;   // section 1
@end

@implementation SCIBackupScopePickerVC

- (instancetype)init {
    self = [super init];
    if (!self) return self;
    _availableScopes = SCIBackupScopePickerSettings | SCIBackupScopePickerLists | SCIBackupScopePickerAnalyzer;
    _continueTitle = SCILocalized(@"Continue");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.selection = self.initialSelection & self.availableScopes;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:SCILocalized(@"Select all") style:UIBarButtonItemStylePlain
                target:self action:@selector(selectAllTapped)];

    [self buildRows];
    [self buildTable];
    [self buildCommitBar];
    [self refreshContinue];
}

- (void)buildRows {
    NSMutableArray *rows = [NSMutableArray array];
    if (self.availableScopes & SCIBackupScopePickerSettings) {
        SCIPickerRow *r = [SCIPickerRow new];
        r.kind = SCIPickerRowKindScope;
        r.scope = SCIBackupScopePickerSettings;
        r.title = SCILocalized(@"Settings");
        r.subtitle = [self summaryForSettings];
        r.symbol = @"slider.horizontal.3";
        r.iconColor = [UIColor systemBlueColor];
        [rows addObject:r];
    }
    if (self.availableScopes & SCIBackupScopePickerLists) {
        SCIPickerRow *r = [SCIPickerRow new];
        r.kind = SCIPickerRowKindScope;
        r.scope = SCIBackupScopePickerLists;
        r.title = SCILocalized(@"Excluded lists");
        r.subtitle = [self summaryForLists];
        r.symbol = @"person.crop.circle.badge.xmark";
        r.iconColor = [UIColor systemOrangeColor];
        [rows addObject:r];
    }
    if (self.availableScopes & SCIBackupScopePickerAnalyzer) {
        SCIPickerRow *r = [SCIPickerRow new];
        r.kind = SCIPickerRowKindScope;
        r.scope = SCIBackupScopePickerAnalyzer;
        r.title = SCILocalized(@"Profile Analyzer data");
        r.subtitle = [self summaryForAnalyzer];
        r.symbol = @"person.fill.viewfinder";
        r.iconColor = [UIColor systemPurpleColor];
        [rows addObject:r];
    }
    self.rows = rows;
}

#pragma mark - Summaries

- (NSDictionary *)settingsPayload {
    NSDictionary *p = self.payload;
    id s = p[@"settings"];
    if ([s isKindOfClass:[NSDictionary class]]) return s;
    if (p && !p[@"ryukgram_export"] && !p[@"settings"] && !p[@"lists"] && !p[@"analyzer"]) return p;
    return @{};
}
- (NSDictionary *)listsPayload { id v = self.payload[@"lists"]; return [v isKindOfClass:[NSDictionary class]] ? v : @{}; }
- (NSDictionary *)analyzerPayload { id v = self.payload[@"analyzer"]; return [v isKindOfClass:[NSDictionary class]] ? v : @{}; }

- (NSString *)summaryForSettings {
    NSUInteger n = [self settingsPayload].count;
    return [NSString stringWithFormat:SCILocalized(@"%lu preferences · tap to inspect"), (unsigned long)n];
}
- (NSString *)summaryForLists {
    NSDictionary *lists = [self listsPayload];
    NSUInteger total = 0;
    for (NSString *k in lists) {
        id v = lists[k];
        if ([v isKindOfClass:[NSArray class]]) total += [(NSArray *)v count];
    }
    return [NSString stringWithFormat:SCILocalized(@"%lu entries across %lu lists · tap to inspect"),
            (unsigned long)total, (unsigned long)lists.count];
}
- (NSString *)summaryForAnalyzer {
    NSDictionary *a = [self analyzerPayload];
    NSMutableSet *pks = [NSMutableSet set];
    NSUInteger snaps = 0;
    for (NSString *f in a) {
        NSArray *parts = [f componentsSeparatedByString:@"."];
        if (parts.count >= 2) [pks addObject:parts[0]];
        if ([f hasSuffix:@".current.json"] || [f hasSuffix:@".previous.json"]) snaps++;
    }
    return [NSString stringWithFormat:SCILocalized(@"%lu account(s) · %lu snapshot(s) · tap to inspect"),
            (unsigned long)pks.count, (unsigned long)snaps];
}

#pragma mark - UI

- (void)buildTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.estimatedRowHeight = 64;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.tableView registerClass:[SCIPickerCell class] forCellReuseIdentifier:@"scope"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildCommitBar {
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.view addSubview:bar];

    self.continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.continueButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.continueButton.backgroundColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.continueButton.layer.cornerRadius = 14;
    [self.continueButton addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:self.continueButton];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor],

        [self.continueButton.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [self.continueButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
        [self.continueButton.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10],
        [self.continueButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.continueButton.heightAnchor constraintEqualToConstant:48],
    ]];
}

#pragma mark - Actions

- (void)cancelTapped { [self dismissOrPopWithCompletion:nil]; }

- (void)selectAllTapped {
    BOOL all = (self.selection & self.availableScopes) == self.availableScopes && self.availableScopes != 0;
    self.selection = all ? 0 : self.availableScopes;
    [self.tableView reloadData];
    [self refreshContinue];
}

- (void)continueTapped {
    SCIBackupScopePickerMask chosen = self.selection;
    void (^block)(SCIBackupScopePickerMask) = self.onContinue;
    [self dismissOrPopWithCompletion:^{
        if (block && chosen) block(chosen);
    }];
}

- (void)dismissOrPopWithCompletion:(void(^)(void))completion {
    if (self.navigationController.viewControllers.firstObject == self) {
        [self dismissViewControllerAnimated:YES completion:completion];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    }
}

- (void)refreshContinue {
    BOOL any = self.selection != 0;
    self.continueButton.enabled = any;
    self.continueButton.alpha = any ? 1.0 : 0.4;
    NSInteger n = __builtin_popcountll((unsigned long long)self.selection);
    [self.continueButton setTitle:any
        ? [NSString stringWithFormat:@"%@ (%ld)", self.continueTitle, (long)n]
        : self.continueTitle
        forState:UIControlStateNormal];
}

- (void)toggleScope:(SCIBackupScopePickerMask)scope {
    if (!(self.availableScopes & scope)) return;
    if (self.selection & scope) self.selection &= ~scope;
    else self.selection |= scope;
    [self.tableView reloadData];
    [self refreshContinue];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.rows.count : 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? SCILocalized(@"Include") : SCILocalized(@"Raw");
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return section == 0 ? self.headerMessage : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        static NSString *rid = @"json";
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
        cell.textLabel.text = SCILocalized(@"Raw JSON");
        cell.detailTextLabel.text = SCILocalized(@"Inspect the full payload");
        cell.imageView.image = [UIImage systemImageNamed:@"curlybraces"];
        cell.imageView.tintColor = [UIColor systemGrayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    SCIPickerCell *cell = [tv dequeueReusableCellWithIdentifier:@"scope" forIndexPath:indexPath];
    SCIPickerRow *r = self.rows[indexPath.row];
    cell.titleLabel.text = r.title;
    cell.subtitleLabel.text = r.subtitle;
    cell.iconView.image = [UIImage systemImageNamed:r.symbol];
    cell.iconView.tintColor = r.iconColor;
    BOOL enabled = (self.availableScopes & r.scope) != 0;
    BOOL checked = (self.selection & r.scope) != 0;
    [cell setChecked:checked enabled:enabled];
    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^{ [weakSelf toggleScope:r.scope]; };
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self pushRawJSON];
        return;
    }
    SCIPickerRow *r = self.rows[indexPath.row];
    [self pushDetailForScope:r.scope];
}

#pragma mark - Detail pushes

- (void)pushRawJSON {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(self.payload ?: @{})
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";

    UIViewController *vc = [UIViewController new];
    vc.title = SCILocalized(@"Raw JSON");
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.text = json;
    tv.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    tv.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
    ]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pushDetailForScope:(SCIBackupScopePickerMask)scope {
    NSArray<NSDictionary *> *sections = nil;
    NSString *title = nil;
    if (scope == SCIBackupScopePickerSettings) {
        title = SCILocalized(@"Settings");
        sections = [self detailSectionsForSettings:[self settingsPayload]];
    } else if (scope == SCIBackupScopePickerLists) {
        title = SCILocalized(@"Excluded lists");
        sections = [self detailSectionsForLists:[self listsPayload]];
    } else if (scope == SCIBackupScopePickerAnalyzer) {
        title = SCILocalized(@"Profile Analyzer data");
        sections = [self detailSectionsForAnalyzer:[self analyzerPayload]];
    } else return;
    SCIBackupDetailVC *vc = [[SCIBackupDetailVC alloc] initWithTitle:title sections:sections];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSString *)displayValue:(id)v {
    if ([v isKindOfClass:[NSNumber class]]) {
        NSNumber *n = v;
        const char *t = n.objCType;
        if (t && strcmp(t, "c") == 0) return n.boolValue ? @"on" : @"off";
        return n.stringValue;
    }
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"[%lu]", (unsigned long)[(NSArray *)v count]];
    if ([v isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"{%lu}", (unsigned long)[(NSDictionary *)v count]];
    return @"—";
}

- (NSString *)prettyKeyForList:(NSString *)k {
    if ([k isEqualToString:@"excluded_threads"]) return SCILocalized(@"Excluded chats");
    if ([k isEqualToString:@"included_threads"]) return SCILocalized(@"Included chats");
    if ([k isEqualToString:@"excluded_story_users"]) return SCILocalized(@"Excluded story users");
    if ([k isEqualToString:@"included_story_users"]) return SCILocalized(@"Included story users");
    if ([k isEqualToString:@"embed_custom_domains"]) return SCILocalized(@"Embed domains");
    return k;
}

- (NSArray<NSDictionary *> *)detailSectionsForSettings:(NSDictionary *)settings {
    NSArray *keys = [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *k in keys) {
        [rows addObject:@{ @"title": k, @"value": [self displayValue:settings[k]] }];
    }
    return @[@{ @"title": [NSString stringWithFormat:SCILocalized(@"All preferences (%lu)"), (unsigned long)rows.count],
                @"rows": rows }];
}

- (NSArray<NSDictionary *> *)detailSectionsForLists:(NSDictionary *)lists {
    NSMutableArray *sections = [NSMutableArray array];
    NSArray *keys = [[lists allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *k in keys) {
        id v = lists[k];
        NSArray *items = [v isKindOfClass:[NSArray class]] ? v : @[];
        NSMutableArray *rows = [NSMutableArray array];
        for (id item in items) {
            NSString *display = [item isKindOfClass:[NSString class]] ? item : [NSString stringWithFormat:@"%@", item];
            [rows addObject:@{ @"title": display, @"value": @"" }];
        }
        if (!rows.count) [rows addObject:@{ @"title": SCILocalized(@"(empty)"), @"value": @"" }];
        [sections addObject:@{ @"title": [self prettyKeyForList:k], @"rows": rows }];
    }
    if (!sections.count) sections = [@[@{ @"title": @"", @"rows": @[@{@"title": SCILocalized(@"(no lists)"), @"value": @""}] }] mutableCopy];
    return sections;
}

- (NSArray<NSDictionary *> *)detailSectionsForAnalyzer:(NSDictionary *)analyzer {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byPK = [NSMutableDictionary dictionary];
    for (NSString *file in analyzer) {
        NSArray *parts = [file componentsSeparatedByString:@"."];
        if (parts.count < 2) continue;
        NSMutableDictionary *slot = byPK[parts[0]] ?: [NSMutableDictionary dictionary];
        slot[parts[1]] = analyzer[file];
        byPK[parts[0]] = slot;
    }
    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *pk in [[byPK allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *slot = byPK[pk];
        NSDictionary *hdr = slot[@"header"];
        NSString *username = [hdr[@"username"] isKindOfClass:[NSString class]] ? hdr[@"username"] : nil;
        NSString *header = username.length ? [NSString stringWithFormat:@"@%@", username] : [NSString stringWithFormat:@"PK %@", pk];

        NSMutableArray *rows = [NSMutableArray array];
        if (hdr) {
            [rows addObject:@{ @"title": SCILocalized(@"Full name"), @"value": hdr[@"full_name"] ?: @"—" }];
            [rows addObject:@{ @"title": SCILocalized(@"Followers"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"follower_count"] integerValue]] }];
            [rows addObject:@{ @"title": SCILocalized(@"Following"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"following_count"] integerValue]] }];
            [rows addObject:@{ @"title": SCILocalized(@"Posts"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"media_count"] integerValue]] }];
        }
        [rows addObject:@{ @"title": SCILocalized(@"Current snapshot"), @"value": [self snapshotSummary:slot[@"current"]] }];
        [rows addObject:@{ @"title": SCILocalized(@"Previous snapshot"), @"value": [self snapshotSummary:slot[@"previous"]] }];
        [sections addObject:@{ @"title": header, @"rows": rows }];
    }
    if (!sections.count) sections = [@[@{ @"title": @"", @"rows": @[@{@"title": SCILocalized(@"(no analyzer data)"), @"value": @""}] }] mutableCopy];
    return sections;
}

- (NSString *)snapshotSummary:(NSDictionary *)snap {
    if (![snap isKindOfClass:[NSDictionary class]]) return @"—";
    NSArray *followers = snap[@"followers"];
    NSArray *following = snap[@"following"];
    NSTimeInterval ts = [snap[@"scan_date"] doubleValue];
    NSString *when = ts > 0 ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]
                                                              dateStyle:NSDateFormatterShortStyle
                                                              timeStyle:NSDateFormatterShortStyle]
                            : @"";
    return [NSString stringWithFormat:@"%lu / %lu — %@",
            (unsigned long)([followers isKindOfClass:[NSArray class]] ? followers.count : 0),
            (unsigned long)([following isKindOfClass:[NSArray class]] ? following.count : 0),
            when];
}

@end
