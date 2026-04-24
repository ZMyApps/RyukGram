#import "SCIProfileAnalyzerListViewController.h"
#import "SCIProfileAnalyzerStorage.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../../SCIImageCache.h"
#import "../../Settings/SCISearchBarStyler.h"
#import "../../Localization/SCILocalization.h"

// IG throttles /friendships/ aggressively — 50/session + a 1.5s cushion
// between calls keeps us well inside the soft limit.
static const NSInteger kSCIPABatchCap = 50;
static const NSTimeInterval kSCIPABatchDelay = 1.5;

typedef NS_ENUM(NSInteger, SCIPASortMode) {
    SCIPASortModeDefault,   // original order from the snapshot
    SCIPASortModeAZ,        // username ascending
    SCIPASortModeZA,        // username descending
};

#pragma mark - Cell

@interface SCIPAUserCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadge;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToButton;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToEdge;
@property (nonatomic, copy) void(^onActionTap)(SCIPAUserCell *);
@end

@implementation SCIPAUserCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return self;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _avatar = [UIImageView new];
    _avatar.translatesAutoresizingMaskIntoConstraints = NO;
    _avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _avatar.layer.cornerRadius = 24;
    _avatar.layer.masksToBounds = YES;
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    [self.contentView addSubview:_avatar];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _usernameLabel.textColor = [UIColor labelColor];
    [_usernameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_usernameLabel];

    _verifiedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
    _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedBadge.tintColor = [UIColor systemBlueColor];
    _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
    _verifiedBadge.hidden = YES;
    [_verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_verifiedBadge];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:13];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    _subtitleLabel.numberOfLines = 2;
    [self.contentView addSubview:_subtitleLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _actionButton.layer.cornerRadius = 8;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(onAction) forControlEvents:UIControlEventTouchUpInside];
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_actionButton];

    _usernameTrailingToButton = [_verifiedBadge.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10];
    _usernameTrailingToEdge = [_verifiedBadge.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatar.widthAnchor constraintEqualToConstant:48],
        [_avatar.heightAnchor constraintEqualToConstant:48],

        [_usernameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
        [_usernameLabel.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],

        [_verifiedBadge.leadingAnchor constraintEqualToAnchor:_usernameLabel.trailingAnchor constant:4],
        [_verifiedBadge.centerYAnchor constraintEqualToAnchor:_usernameLabel.centerYAnchor],
        [_verifiedBadge.widthAnchor constraintEqualToConstant:14],
        [_verifiedBadge.heightAnchor constraintEqualToConstant:14],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_usernameLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_usernameLabel.bottomAnchor constant:2],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],

        [_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        _usernameTrailingToButton,
    ]];
    return self;
}

- (void)setActionVisible:(BOOL)visible {
    self.actionButton.hidden = !visible;
    self.usernameTrailingToButton.active = visible;
    self.usernameTrailingToEdge.active = !visible;
}

- (void)onAction { if (self.onActionTap) self.onActionTap(self); }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.avatar.image = nil;
    self.onActionTap = nil;
    self.verifiedBadge.hidden = YES;
}
@end

#pragma mark - VC

@interface SCIProfileAnalyzerListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *allUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *filteredUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *allChanges;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *filteredChanges;
@property (nonatomic, assign) SCIPAListKind kind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingPKs;

// Multi-select state
@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPKs;
@property (nonatomic, strong) UIView *batchBar;
@property (nonatomic, strong) UIButton *batchActionButton;

// Filter / sort state
@property (nonatomic, assign) SCIPASortMode sortMode;
@property (nonatomic, assign) BOOL filterVerifiedOnly;
@property (nonatomic, assign) BOOL filterNotVerifiedOnly;
@property (nonatomic, assign) BOOL filterPrivateOnly;
@property (nonatomic, copy) NSString *currentQuery;
@end

@implementation SCIProfileAnalyzerListViewController

- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SCIProfileAnalyzerUser *> *)users
                         kind:(SCIPAListKind)kind {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.kind = kind;
    self.allUsers = users ?: @[];
    self.filteredUsers = self.allUsers;
    self.pendingPKs = [NSMutableSet set];
    self.selectedPKs = [NSMutableSet set];
    return self;
}

- (instancetype)initWithTitle:(NSString *)title
              profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.kind = SCIPAListKindProfileUpdate;
    self.allChanges = updates ?: @[];
    self.filteredChanges = self.allChanges;
    self.pendingPKs = [NSMutableSet set];
    self.selectedPKs = [NSMutableSet set];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self setupTable];
    [self setupSearch];
    [self setupEmptyState];
    [self setupBatchBar];
    [self updateNavBar];
    [self refreshCounts];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 72;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0);
    self.tableView.allowsMultipleSelection = NO;
    [self.tableView registerClass:[SCIPAUserCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];
}

- (void)setupSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = SCILocalized(@"Search username or name");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self sciStyleSearchBar];
}

- (void)sciStyleSearchBar {
    [SCISearchBarStyler styleSearchBar:self.searchController.searchBar];
}

- (void)willPresentSearchController:(UISearchController *)searchController { [self sciStyleSearchBar]; }
- (void)didPresentSearchController:(UISearchController *)searchController {
    [self sciStyleSearchBar];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sciStyleSearchBar];
    });
}

- (void)setupEmptyState {
    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = SCILocalized(@"No results");
    self.emptyLabel.textColor = [UIColor tertiaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
    ]];
}

- (void)setupBatchBar {
    // Floating capsule above the home indicator.
    self.batchActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.batchActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.batchActionButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.batchActionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.batchActionButton.backgroundColor = [UIColor systemRedColor];
    self.batchActionButton.layer.cornerRadius = 26;
    self.batchActionButton.contentEdgeInsets = UIEdgeInsetsMake(0, 28, 0, 28);
    self.batchActionButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.batchActionButton.layer.shadowOffset = CGSizeMake(0, 6);
    self.batchActionButton.layer.shadowOpacity = 0.22;
    self.batchActionButton.layer.shadowRadius = 12;
    [self.batchActionButton addTarget:self action:@selector(batchActionTapped) forControlEvents:UIControlEventTouchUpInside];
    self.batchActionButton.hidden = YES;
    [self.view addSubview:self.batchActionButton];

    self.batchBar = self.batchActionButton;

    [NSLayoutConstraint activateConstraints:@[
        [self.batchActionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.batchActionButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.batchActionButton.heightAnchor constraintEqualToConstant:52],
        [self.batchActionButton.widthAnchor constraintGreaterThanOrEqualToConstant:220],
        [self.batchActionButton.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
    ]];
}

- (BOOL)supportsBatchAction {
    return self.kind == SCIPAListKindUnfollow || self.kind == SCIPAListKindFollow;
}

- (void)updateNavBar {
    NSMutableArray *rights = [NSMutableArray array];
    if (self.supportsBatchAction) {
        NSString *t = self.selectionMode ? SCILocalized(@"Done") : SCILocalized(@"Select");
        UIBarButtonItem *sel = [[UIBarButtonItem alloc] initWithTitle:t
                                                                style:UIBarButtonItemStylePlain
                                                               target:self action:@selector(toggleSelectionMode)];
        [rights addObject:sel];
    }
    // Filled variant signals "filter/sort active".
    NSString *symbol = [self hasActiveFilterOrSort]
        ? @"line.3.horizontal.decrease.circle.fill"
        : @"line.3.horizontal.decrease.circle";
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol]
                                                                menu:[self buildFilterMenu]];
    [rights addObject:filter];
    self.navigationItem.rightBarButtonItems = rights;
}

- (UIMenu *)buildFilterMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *az = [UIAction actionWithTitle:SCILocalized(@"Username A → Z")
                                        image:[UIImage systemImageNamed:@"arrow.up"]
                                   identifier:nil
                                      handler:^(__kindof UIAction *_) {
        weakSelf.sortMode = weakSelf.sortMode == SCIPASortModeAZ ? SCIPASortModeDefault : SCIPASortModeAZ;
        [weakSelf applyFiltersAndSort];
    }];
    az.state = (self.sortMode == SCIPASortModeAZ) ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *za = [UIAction actionWithTitle:SCILocalized(@"Username Z → A")
                                        image:[UIImage systemImageNamed:@"arrow.down"]
                                   identifier:nil
                                      handler:^(__kindof UIAction *_) {
        weakSelf.sortMode = weakSelf.sortMode == SCIPASortModeZA ? SCIPASortModeDefault : SCIPASortModeZA;
        [weakSelf applyFiltersAndSort];
    }];
    za.state = (self.sortMode == SCIPASortModeZA) ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *sortGroup = [UIMenu menuWithTitle:SCILocalized(@"Sort")
                                        image:nil identifier:nil
                                      options:UIMenuOptionsDisplayInline
                                     children:@[az, za]];

    UIAction *verified = [UIAction actionWithTitle:SCILocalized(@"Verified only")
                                              image:[UIImage systemImageNamed:@"checkmark.seal.fill"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
        weakSelf.filterVerifiedOnly = !weakSelf.filterVerifiedOnly;
        if (weakSelf.filterVerifiedOnly) weakSelf.filterNotVerifiedOnly = NO;
        [weakSelf applyFiltersAndSort];
    }];
    verified.state = self.filterVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *notVerified = [UIAction actionWithTitle:SCILocalized(@"Not verified only")
                                                 image:[UIImage systemImageNamed:@"seal"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
        weakSelf.filterNotVerifiedOnly = !weakSelf.filterNotVerifiedOnly;
        if (weakSelf.filterNotVerifiedOnly) weakSelf.filterVerifiedOnly = NO;
        [weakSelf applyFiltersAndSort];
    }];
    notVerified.state = self.filterNotVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *priv = [UIAction actionWithTitle:SCILocalized(@"Private only")
                                          image:[UIImage systemImageNamed:@"lock.fill"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        weakSelf.filterPrivateOnly = !weakSelf.filterPrivateOnly;
        [weakSelf applyFiltersAndSort];
    }];
    priv.state = self.filterPrivateOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *filterGroup = [UIMenu menuWithTitle:SCILocalized(@"Filter")
                                          image:nil identifier:nil
                                        options:UIMenuOptionsDisplayInline
                                       children:@[verified, notVerified, priv]];

    NSMutableArray *children = [NSMutableArray arrayWithObjects:sortGroup, filterGroup, nil];
    if ([self hasActiveFilterOrSort]) {
        UIAction *clear = [UIAction actionWithTitle:SCILocalized(@"Clear")
                                              image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
            weakSelf.sortMode = SCIPASortModeDefault;
            weakSelf.filterVerifiedOnly = NO;
            weakSelf.filterNotVerifiedOnly = NO;
            weakSelf.filterPrivateOnly = NO;
            [weakSelf applyFiltersAndSort];
        }];
        clear.attributes = UIMenuElementAttributesDestructive;
        [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                           options:UIMenuOptionsDisplayInline children:@[clear]]];
    }
    return [UIMenu menuWithChildren:children];
}

- (void)refreshCounts {
    NSUInteger total = self.kind == SCIPAListKindProfileUpdate ? self.allChanges.count : self.allUsers.count;
    NSUInteger shown = self.kind == SCIPAListKindProfileUpdate ? self.filteredChanges.count : self.filteredUsers.count;
    self.navigationItem.prompt = [NSString stringWithFormat:SCILocalized(@"%lu of %lu"),
                                  (unsigned long)shown, (unsigned long)total];
    self.emptyLabel.hidden = shown > 0;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.currentQuery = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [self applyFiltersAndSort];
}

// Pipeline: search → verified/private filter → sort.
- (void)applyFiltersAndSort {
    NSString *q = self.currentQuery;
    BOOL hasQuery = q.length > 0;
    BOOL verified = self.filterVerifiedOnly;
    BOOL notVerified = self.filterNotVerifiedOnly;
    BOOL priv = self.filterPrivateOnly;

    NSArray *(^applyToUsers)(NSArray *) = ^NSArray *(NSArray *src) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:src.count];
        for (SCIProfileAnalyzerUser *u in src) {
            if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
                         && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
            if (verified && !u.isVerified) continue;
            if (notVerified && u.isVerified) continue;
            if (priv && !u.isPrivate) continue;
            [out addObject:u];
        }
        return [self sortUsers:out];
    };

    if (self.kind == SCIPAListKindProfileUpdate) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.allChanges.count];
        for (SCIProfileAnalyzerProfileChange *c in self.allChanges) {
            SCIProfileAnalyzerUser *u = c.current;
            if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
                         && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
            if (verified && !u.isVerified) continue;
            if (notVerified && u.isVerified) continue;
            if (priv && !u.isPrivate) continue;
            [out addObject:c];
        }
        self.filteredChanges = [self sortChanges:out];
    } else {
        self.filteredUsers = applyToUsers(self.allUsers);
    }
    [self refreshCounts];
    [self updateNavBar];  // refresh filter-icon "active" state
    [self.tableView reloadData];
}

- (NSArray *)sortUsers:(NSArray<SCIProfileAnalyzerUser *> *)src {
    if (self.sortMode == SCIPASortModeDefault) return src;
    BOOL asc = (self.sortMode == SCIPASortModeAZ);
    return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerUser *a, SCIProfileAnalyzerUser *b) {
        NSComparisonResult r = [a.username caseInsensitiveCompare:b.username ?: @""];
        return asc ? r : -r;
    }];
}

- (NSArray *)sortChanges:(NSArray<SCIProfileAnalyzerProfileChange *> *)src {
    if (self.sortMode == SCIPASortModeDefault) return src;
    BOOL asc = (self.sortMode == SCIPASortModeAZ);
    return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerProfileChange *a, SCIProfileAnalyzerProfileChange *b) {
        NSComparisonResult r = [a.current.username caseInsensitiveCompare:b.current.username ?: @""];
        return asc ? r : -r;
    }];
}

- (BOOL)hasActiveFilterOrSort {
    return self.filterVerifiedOnly || self.filterNotVerifiedOnly || self.filterPrivateOnly || self.sortMode != SCIPASortModeDefault;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.kind == SCIPAListKindProfileUpdate ? self.filteredChanges.count : self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIPAUserCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    SCIProfileAnalyzerUser *user;
    SCIProfileAnalyzerProfileChange *change = nil;
    if (self.kind == SCIPAListKindProfileUpdate) {
        change = self.filteredChanges[indexPath.row];
        user = change.current;
    } else {
        user = self.filteredUsers[indexPath.row];
    }

    cell.usernameLabel.text = user.username.length ? [NSString stringWithFormat:@"@%@", user.username] : @"(unknown)";
    cell.verifiedBadge.hidden = !user.isVerified;

    if (self.kind == SCIPAListKindProfileUpdate) {
        NSMutableArray *lines = [NSMutableArray array];
        if (change.usernameChanged) {
            [lines addObject:[NSString stringWithFormat:SCILocalized(@"Username: @%@ → @%@"),
                              change.previous.username ?: @"", change.current.username ?: @""]];
        }
        if (change.fullNameChanged) {
            [lines addObject:[NSString stringWithFormat:SCILocalized(@"Name: %@ → %@"),
                              change.previous.fullName.length ? change.previous.fullName : @"—",
                              change.current.fullName.length ? change.current.fullName : @"—"]];
        }
        if (change.profilePicChanged) [lines addObject:SCILocalized(@"Profile picture changed")];
        cell.subtitleLabel.text = [lines componentsJoinedByString:@"\n"];
        cell.subtitleLabel.numberOfLines = 3;
    } else {
        cell.subtitleLabel.text = user.fullName.length ? user.fullName : (user.isPrivate ? SCILocalized(@"Private account") : @"");
        cell.subtitleLabel.numberOfLines = 1;
    }

    [self configureActionForCell:cell user:user];

    // Selection-mode checkmark affordance
    if (self.selectionMode) {
        BOOL on = [self.selectedPKs containsObject:user.pk];
        cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    if (user.profilePicURL.length) {
        NSURL *url = [NSURL URLWithString:user.profilePicURL];
        NSString *pkTag = user.pk;
        cell.avatar.tag = pkTag.hash;
        [SCIImageCache loadImageFromURL:url completion:^(UIImage *image) {
            if (cell.avatar.tag == (NSInteger)pkTag.hash) cell.avatar.image = image;
        }];
    } else {
        cell.avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
        cell.avatar.tintColor = [UIColor systemGrayColor];
    }
    return cell;
}

- (void)configureActionForCell:(SCIPAUserCell *)cell user:(SCIProfileAnalyzerUser *)user {
    BOOL hasButton = !self.selectionMode
        && (self.kind == SCIPAListKindFollow || self.kind == SCIPAListKindUnfollow);
    [cell setActionVisible:hasButton];
    if (!hasButton) return;

    BOOL pending = [self.pendingPKs containsObject:user.pk];
    if (self.kind == SCIPAListKindUnfollow) {
        [cell.actionButton setTitle:SCILocalized(@"Unfollow") forState:UIControlStateNormal];
        cell.actionButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
        [cell.actionButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    } else {
        [cell.actionButton setTitle:SCILocalized(@"Follow") forState:UIControlStateNormal];
        cell.actionButton.backgroundColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
        [cell.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    cell.actionButton.enabled = !pending;
    cell.actionButton.alpha = pending ? 0.5 : 1.0;

    __weak typeof(self) weakSelf = self;
    cell.onActionTap = ^(SCIPAUserCell *c) { [weakSelf performActionForUser:user]; };
}

#pragma mark - Single-row action

- (void)performActionForUser:(SCIProfileAnalyzerUser *)user {
    if ([self.pendingPKs containsObject:user.pk]) return;
    if (self.kind == SCIPAListKindUnfollow) {
        NSString *msg = [NSString stringWithFormat:SCILocalized(@"Unfollow @%@?"), user.username ?: @""];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Unfollow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [self sendFriendshipForUser:user follow:NO reload:YES];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        [self sendFriendshipForUser:user follow:YES reload:YES];
    }
}

- (void)sendFriendshipForUser:(SCIProfileAnalyzerUser *)user follow:(BOOL)follow reload:(BOOL)reload {
    [self.pendingPKs addObject:user.pk];
    if (reload) [self.tableView reloadData];
    void(^done)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
        [self.pendingPKs removeObject:user.pk];
        BOOL success = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
        if (success) {
            [self persistFriendshipChangeForUser:user followed:follow];
            [self removeUserFromList:user];
        } else {
            [SCIUtils showErrorHUDWithDescription:err.localizedDescription ?: SCILocalized(@"Request failed")];
            [self.tableView reloadData];
        }
    };
    if (follow) [SCIInstagramAPI followUserPK:user.pk completion:done];
    else        [SCIInstagramAPI unfollowUserPK:user.pk completion:done];
}

// Mirror in-app follow/unfollow into the cached snapshot so category counts
// + header stats update live without a rescan.
- (void)persistFriendshipChangeForUser:(SCIProfileAnalyzerUser *)user followed:(BOOL)followed {
    NSString *pk = [SCIUtils currentUserPK];
    SCIProfileAnalyzerSnapshot *snap = [SCIProfileAnalyzerStorage currentSnapshotForUserPK:pk];
    if (!snap) return;
    NSMutableArray *following = [snap.following mutableCopy] ?: [NSMutableArray array];
    BOOL alreadyIn = [following containsObject:user];
    if (followed && !alreadyIn) {
        [following addObject:user];
        snap.followingCount = MAX(0, snap.followingCount + 1);
    } else if (!followed && alreadyIn) {
        [following removeObject:user];
        snap.followingCount = MAX(0, snap.followingCount - 1);
    } else {
        return;
    }
    snap.following = following;
    [SCIProfileAnalyzerStorage updateCurrentSnapshot:snap forUserPK:pk];
}

- (void)removeUserFromList:(SCIProfileAnalyzerUser *)user {
    NSMutableArray *all = [self.allUsers mutableCopy];
    [all removeObject:user];
    self.allUsers = all;
    NSMutableArray *filt = [self.filteredUsers mutableCopy];
    [filt removeObject:user];
    self.filteredUsers = filt;
    [self.selectedPKs removeObject:user.pk];
    [self refreshCounts];
    [self.tableView reloadData];
}

#pragma mark - Tap row

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    SCIProfileAnalyzerUser *user = self.kind == SCIPAListKindProfileUpdate
        ? self.filteredChanges[indexPath.row].current
        : self.filteredUsers[indexPath.row];

    if (self.selectionMode) {
        if ([self.selectedPKs containsObject:user.pk]) [self.selectedPKs removeObject:user.pk];
        else [self.selectedPKs addObject:user.pk];
        [self refreshBatchBar];
        [tv reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

    if (!user.username.length) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", user.username]];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Multi-select

- (void)toggleSelectionMode {
    self.selectionMode = !self.selectionMode;
    [self.selectedPKs removeAllObjects];
    self.batchActionButton.hidden = !self.selectionMode;
    // Leave room for the capsule so last-row cells don't sit under it.
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, self.selectionMode ? 96 : 0, 0);
    [self updateNavBar];
    [self refreshBatchBar];
    [self.tableView reloadData];
}

- (void)refreshBatchBar {
    NSUInteger n = self.selectedPKs.count;
    BOOL follow = (self.kind == SCIPAListKindFollow);
    NSString *t = follow
        ? [NSString stringWithFormat:SCILocalized(@"Follow %lu"), (unsigned long)n]
        : [NSString stringWithFormat:SCILocalized(@"Unfollow %lu"), (unsigned long)n];
    [self.batchActionButton setTitle:t forState:UIControlStateNormal];
    self.batchActionButton.backgroundColor = follow
        ? ([SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor])
        : [UIColor systemRedColor];
    self.batchActionButton.enabled = n > 0;
    self.batchActionButton.alpha = n > 0 ? 1.0 : 0.5;
}

- (void)batchActionTapped {
    NSUInteger n = self.selectedPKs.count;
    if (!n) return;
    BOOL follow = (self.kind == SCIPAListKindFollow);
    NSString *verb = follow ? SCILocalized(@"Follow") : SCILocalized(@"Unfollow");
    NSString *title = follow ? SCILocalized(@"Batch follow") : SCILocalized(@"Batch unfollow");
    NSString *msg;
    if (n > kSCIPABatchCap) {
        msg = [NSString stringWithFormat:SCILocalized(@"%@ %lu accounts? The first %ld will be processed to avoid rate limits."),
               verb, (unsigned long)n, (long)kSCIPABatchCap];
    } else {
        msg = [NSString stringWithFormat:SCILocalized(@"%@ %lu accounts? This runs sequentially with a short pause between each."),
               verb, (unsigned long)n];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertActionStyle style = follow ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive;
    [a addAction:[UIAlertAction actionWithTitle:verb style:style handler:^(UIAlertAction *_) {
        [self runBatchAction];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runBatchAction {
    NSMutableArray<SCIProfileAnalyzerUser *> *queue = [NSMutableArray array];
    for (SCIProfileAnalyzerUser *u in self.allUsers) {
        if ([self.selectedPKs containsObject:u.pk]) [queue addObject:u];
        if (queue.count >= kSCIPABatchCap) break;
    }
    [self.selectedPKs removeAllObjects];
    [self refreshBatchBar];
    [self batchStep:queue done:0 total:queue.count];
}

- (void)batchStep:(NSMutableArray<SCIProfileAnalyzerUser *> *)queue
             done:(NSUInteger)done
            total:(NSUInteger)total {
    BOOL follow = (self.kind == SCIPAListKindFollow);
    if (!queue.count) {
        NSString *finishedTitle = follow ? SCILocalized(@"Batch follow finished") : SCILocalized(@"Batch unfollow finished");
        NSString *finishedSub = follow
            ? [NSString stringWithFormat:SCILocalized(@"%lu accounts followed"), (unsigned long)total]
            : [NSString stringWithFormat:SCILocalized(@"%lu accounts unfollowed"), (unsigned long)total];
        [SCIUtils showToastForDuration:2.0 title:finishedTitle subtitle:finishedSub];
        self.navigationItem.prompt = nil;
        [self toggleSelectionMode];
        [self refreshCounts];
        return;
    }
    SCIProfileAnalyzerUser *u = queue.firstObject;
    [queue removeObjectAtIndex:0];
    __weak typeof(self) weakSelf = self;
    void(^handler)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSUInteger nextDone = done + 1;
        BOOL ok = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
        if (ok) {
            [strongSelf persistFriendshipChangeForUser:u followed:follow];
            [strongSelf removeUserFromList:u];
        }
        NSString *progressFmt = follow ? SCILocalized(@"Following… %lu / %lu") : SCILocalized(@"Unfollowing… %lu / %lu");
        strongSelf.navigationItem.prompt = [NSString stringWithFormat:progressFmt,
                                            (unsigned long)nextDone, (unsigned long)total];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSCIPABatchDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf batchStep:queue done:nextDone total:total];
        });
    };
    if (follow) [SCIInstagramAPI followUserPK:u.pk completion:handler];
    else        [SCIInstagramAPI unfollowUserPK:u.pk completion:handler];
}

@end
