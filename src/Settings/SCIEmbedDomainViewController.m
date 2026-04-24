#import "SCIEmbedDomainViewController.h"
#import "../Utils.h"

#define SCI_CUSTOM_DOMAINS_KEY @"embed_custom_domains"

static NSArray *sciPresetDomains(void) {
    return @[@"eeinstagram.com", @"vxinstagram.com", @"kkinstagram.com", @"ddinstagram.com", @"d.ddinstagram.com", @"g.ddinstagram.com"];
}

@interface SCIEmbedDomainViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSString *> *customDomains;
@end

@implementation SCIEmbedDomainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Embed domain");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCustom)];

    [self reload];
}

- (void)reload {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:SCI_CUSTOM_DOMAINS_KEY];
    self.customDomains = stored ?: @[];
    [self.tableView reloadData];
}

- (void)addCustom {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add custom domain")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"example.com";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.keyboardType = UIKeyboardTypeURL;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *domain = alert.textFields.firstObject.text;
        domain = [domain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        domain = [domain stringByReplacingOccurrencesOfString:@"https://" withString:@""];
        domain = [domain stringByReplacingOccurrencesOfString:@"http://" withString:@""];
        while ([domain hasSuffix:@"/"]) domain = [domain substringToIndex:domain.length - 1];
        if (!domain.length || ![domain containsString:@"."]) return;
        NSMutableArray *all = [self.customDomains mutableCopy];
        if (![all containsObject:domain]) [all addObject:domain];
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:SCI_CUSTOM_DOMAINS_KEY];
        [[NSUserDefaults standardUserDefaults] setObject:domain forKey:@"embed_link_domain"];
        [self reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? SCILocalized(@"Presets") : SCILocalized(@"Custom");
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)sciPresetDomains().count : (NSInteger)self.customDomains.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    NSString *domain = indexPath.section == 0
        ? sciPresetDomains()[indexPath.row]
        : self.customDomains[indexPath.row];
    cell.textLabel.text = domain;
    NSString *current = [SCIUtils getStringPref:@"embed_link_domain"];
    if (!current.length) current = @"kkinstagram.com";
    cell.accessoryType = [domain isEqualToString:current] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    NSString *domain = indexPath.section == 0
        ? sciPresetDomains()[indexPath.row]
        : self.customDomains[indexPath.row];
    [[NSUserDefaults standardUserDefaults] setObject:domain forKey:@"embed_link_domain"];
    [tv reloadData];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return nil;
    NSString *domain = self.customDomains[indexPath.row];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive title:SCILocalized(@"Delete")
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        NSMutableArray *all = [self.customDomains mutableCopy];
        [all removeObject:domain];
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:SCI_CUSTOM_DOMAINS_KEY];
        // Reset to default if deleted domain was selected
        NSString *current = [SCIUtils getStringPref:@"embed_link_domain"];
        if ([current isEqualToString:domain])
            [[NSUserDefaults standardUserDefaults] setObject:@"kkinstagram.com" forKey:@"embed_link_domain"];
        [self reload];
        cb(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

@end
