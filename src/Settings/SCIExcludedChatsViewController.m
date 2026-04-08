#import "SCIExcludedChatsViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedThreads.h"

@interface SCIExcludedChatsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy)   NSArray<NSDictionary *> *filtered;
@property (nonatomic, copy)   NSString *query;
@property (nonatomic, assign) NSInteger sortMode; // 0=added desc, 1=name asc
@end

@implementation SCIExcludedChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Excluded chats";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search by name or username";
    [self.searchBar sizeToFit];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIBarButtonItem *sortBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                style:UIBarButtonItemStylePlain target:self action:@selector(toggleSort)];
    self.navigationItem.rightBarButtonItem = sortBtn;

    [self reload];
}

- (void)toggleSort {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sort by"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Recently added", @"Name (A–Z)"];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIAlertAction *a = [UIAlertAction actionWithTitle:titles[i]
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *_) {
            self.sortMode = i;
            [self reload];
        }];
        if (i == self.sortMode) [a setValue:@YES forKey:@"checked"];
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)reload {
    NSArray *all = [SCIExcludedThreads allEntries];
    NSString *q = [self.query lowercaseString];
    if (q.length > 0) {
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
            if ([[e[@"threadName"] lowercaseString] containsString:q]) return YES;
            for (NSDictionary *u in (NSArray *)e[@"users"]) {
                if ([[u[@"username"] lowercaseString] containsString:q]) return YES;
                if ([[u[@"fullName"] lowercaseString] containsString:q]) return YES;
            }
            return NO;
        }]];
    }
    if (self.sortMode == 0) {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSNumber *na = a[@"addedAt"] ?: @0, *nb = b[@"addedAt"] ?: @0;
            return [nb compare:na];
        }];
    } else {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *na = a[@"threadName"] ?: @"", *nb = b[@"threadName"] ?: @"";
            return [na caseInsensitiveCompare:nb];
        }];
    }
    self.filtered = all;
    self.title = [NSString stringWithFormat:@"Excluded chats (%lu)", (unsigned long)self.filtered.count];
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText;
    [self reload];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"sciExclCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];

    NSDictionary *e = self.filtered[indexPath.row];
    NSString *name = e[@"threadName"] ?: @"(unknown)";
    BOOL isGroup = [e[@"isGroup"] boolValue];

    NSMutableArray *unames = [NSMutableArray array];
    for (NSDictionary *u in (NSArray *)e[@"users"]) {
        if (u[@"username"]) [unames addObject:[@"@" stringByAppendingString:u[@"username"]]];
    }
    NSString *subtitle = [unames componentsJoinedByString:@", "];

    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    NSString *kdLabel = (mode == SCIKeepDeletedOverrideExcluded) ? @"  • Keep-deleted: OFF"
                      : (mode == SCIKeepDeletedOverrideIncluded) ? @"  • Keep-deleted: ON"
                      : @"";
    if (kdLabel.length) subtitle = [subtitle stringByAppendingString:kdLabel];

    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", isGroup ? @"👥 " : @"", name];
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = isGroup ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *e = self.filtered[indexPath.row];
    NSArray *users = e[@"users"];
    if ([e[@"isGroup"] boolValue] || users.count != 1) return;
    NSString *username = users.firstObject[@"username"];
    if (!username) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", username]];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"Remove"
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        [SCIExcludedThreads removeThreadId:tid];
        [self reload];
        cb(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];

    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *_) {
        UIAction *(^kdAction)(NSString *, SCIKeepDeletedOverride) = ^UIAction *(NSString *title, SCIKeepDeletedOverride v) {
            UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil
                                            handler:^(__kindof UIAction *_) {
                [SCIExcludedThreads setKeepDeletedOverride:v forThreadId:tid];
                [self reload];
            }];
            if (v == mode) a.state = UIMenuElementStateOn;
            return a;
        };
        UIMenu *kdMenu = [UIMenu menuWithTitle:@"Keep-deleted override"
                                         image:[UIImage systemImageNamed:@"trash.slash"]
                                    identifier:nil
                                       options:0
                                      children:@[
            kdAction(@"Follow default", SCIKeepDeletedOverrideDefault),
            kdAction(@"Force ON (preserve unsends)", SCIKeepDeletedOverrideIncluded),
            kdAction(@"Force OFF (allow unsends)", SCIKeepDeletedOverrideExcluded),
        ]];
        UIAction *remove = [UIAction actionWithTitle:@"Remove from list"
                                               image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [SCIExcludedThreads removeThreadId:tid];
            [self reload];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithChildren:@[kdMenu, remove]];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    SCIKeepDeletedOverride next = (mode + 1) % 3;
    NSString *title = (next == SCIKeepDeletedOverrideExcluded) ? @"KD: OFF"
                    : (next == SCIKeepDeletedOverrideIncluded) ? @"KD: ON"
                    : @"KD: default";
    UIContextualAction *toggle = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        [SCIExcludedThreads setKeepDeletedOverride:next forThreadId:tid];
        [self reload];
        cb(YES);
    }];
    toggle.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[toggle]];
}

@end
