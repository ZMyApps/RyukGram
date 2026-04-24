#import "SCIBackupDetailVC.h"
#import "SCISearchBarStyler.h"
#import "../Utils.h"
#import "../Localization/SCILocalization.h"

@interface SCIBackupDetailVC () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *allSections;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleSections;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation SCIBackupDetailVC

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.allSections = sections ?: @[];
    self.visibleSections = self.allSections;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.estimatedRowHeight = 44;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:self.tableView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = SCILocalized(@"Search");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self sciStyleSearchBar];
}

- (void)sciStyleSearchBar { [SCISearchBarStyler styleSearchBar:self.searchController.searchBar]; }
- (void)willPresentSearchController:(UISearchController *)sc { [self sciStyleSearchBar]; }
- (void)didPresentSearchController:(UISearchController *)sc {
    [self sciStyleSearchBar];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sciStyleSearchBar];
    });
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    NSString *q = [sc.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!q.length) { self.visibleSections = self.allSections; [self.tableView reloadData]; return; }
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *section in self.allSections) {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSDictionary *r in section[@"rows"]) {
            NSString *t = r[@"title"] ?: @"";
            NSString *v = r[@"value"] ?: @"";
            if ([t localizedCaseInsensitiveContainsString:q] || [v localizedCaseInsensitiveContainsString:q]) {
                [matched addObject:r];
            }
        }
        if (matched.count) [out addObject:@{ @"title": section[@"title"] ?: @"", @"rows": matched }];
    }
    self.visibleSections = out;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.visibleSections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return [self.visibleSections[section][@"rows"] count];
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    NSString *t = self.visibleSections[section][@"title"];
    return t.length ? t : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"row";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:rid];
    NSDictionary *r = self.visibleSections[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = r[@"title"];
    cell.detailTextLabel.text = r[@"value"];
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    // Color on/off for quick visual scan
    NSString *v = r[@"value"] ?: @"";
    if ([v isEqualToString:@"on"]) cell.detailTextLabel.textColor = [UIColor systemGreenColor];
    else if ([v isEqualToString:@"off"]) cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
    else cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

@end
