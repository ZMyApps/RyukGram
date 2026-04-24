// View story mentions — list mentioned users for the current story item.
// Reachable via eye long-press menu and the 3-dot story menu.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "StoryHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern __weak UIViewController *sciActiveStoryViewerVC;

// Forward decl — defined below.
static id sciFieldCacheValue(id obj, NSString *key);

static NSString *sciUserPK(id userObj) {
    if (!userObj) return nil;
    id pk = sciFieldCacheValue(userObj, @"strong_id__");
    if (!pk) pk = sciFieldCacheValue(userObj, @"pk");
    if (!pk) {
        @try {
            Ivar pkIvar = class_getInstanceVariable([userObj class], "_pk");
            if (pkIvar) pk = object_getIvar(userObj, pkIvar);
        } @catch (__unused id e) {}
    }
    return pk ? [NSString stringWithFormat:@"%@", pk] : nil;
}

static void sciStyleFollowBtn(UIButton *btn, BOOL following) {
    [btn setTitle:following ? SCILocalized(@"Following") : SCILocalized(@"Follow") forState:UIControlStateNormal];
    btn.backgroundColor = following ? [UIColor tertiarySystemFillColor] : [UIColor systemBlueColor];
    [btn setTitleColor:following ? [UIColor labelColor] : [UIColor whiteColor] forState:UIControlStateNormal];
}

// ============ Mention extraction ============

static NSArray *sciCurrentStoryMentions(UIView *anchor) {
    UIViewController *storyVC = nil;
    if (anchor) storyVC = sciFindVC(anchor, @"IGStoryViewerViewController");
    if (!storyVC) storyVC = sciActiveStoryViewerVC;
    if (!storyVC) return nil;

    UIResponder *start = anchor ?: (UIResponder *)storyVC.view;
    id item = sciGetCurrentStoryItem(start);
    IGMedia *media = nil;
    if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) {
        media = (IGMedia *)item;
    } else {
        media = sciExtractMediaFromItem(item);
    }
    if (!media) {
        @try {
            id sc = sciFindSectionController(storyVC);
            if (sc) {
                SEL csi = NSSelectorFromString(@"currentStoryItem");
                if ([sc respondsToSelector:csi])
                    media = ((id(*)(id,SEL))objc_msgSend)(sc, csi);
            }
        } @catch (__unused id e) {}
    }
    if (!media) {
        @try {
            id vm = sciCall(storyVC, @selector(currentViewModel));
            id storyItem = sciCall1(storyVC, @selector(currentStoryItemForViewModel:), vm);
            if ([storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) {
                media = (IGMedia *)storyItem;
            } else {
                media = sciExtractMediaFromItem(storyItem);
            }
        } @catch (__unused id e) {}
    }
    if (!media) return nil;
    SEL sel = NSSelectorFromString(@"reelMentions");
    if (![media respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(media, sel);
}

// IGUser stores fields in a Pando-backed dictionary. KVC goes through a
// resolver that returns NSNull for many keys, so we read the dict directly.
static id sciFieldCacheValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    static Ivar fcIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGAPIStorableObject");
        if (c) fcIvar = class_getInstanceVariable(c, "_fieldCache");
    });
    if (!fcIvar) return nil;
    NSDictionary *fc = object_getIvar(obj, fcIvar);
    if (!fc) return nil;
    id val = fc[key];
    if (!val || [val isKindOfClass:[NSNull class]]) return nil;
    return val;
}

static NSDictionary *sciMentionUserInfo(id mention) {
    if (!mention) return nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    @try {
        id user = [mention valueForKey:@"user"];
        if (!user) return nil;
        info[@"userObj"] = user;

        NSString *username = sciFieldCacheValue(user, @"username");
        if (username.length) info[@"username"] = username;

        NSString *fullName = sciFieldCacheValue(user, @"full_name");
        if (fullName.length) info[@"fullName"] = fullName;

        NSString *picStr = sciFieldCacheValue(user, @"profile_pic_url");
        if (picStr.length) {
            NSURL *picURL = [NSURL URLWithString:picStr];
            if (picURL) info[@"picURL"] = picURL;
        }
    } @catch (__unused id e) {}
    return info.count > 1 ? [info copy] : nil;
}

// ============ Bottom sheet VC ============

#define kAvatarSize 52.0
#define kRowHeight  72.0

@interface SCIStoryMentionsVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *userInfos;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *currentUsername;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *friendshipStatuses;
@end

@implementation SCIStoryMentionsVC

- (void)viewDidLoad {
    [super viewDidLoad];

    @try {
        id window = [[UIApplication sharedApplication] keyWindow];
        if ([window respondsToSelector:@selector(userSession)])
            self.currentUsername = ((IGUserSession *)[window valueForKey:@"userSession"]).user.username;
    } @catch (__unused id e) {}

    UIColor *bg = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1]
            : [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1];
    }];
    self.view.backgroundColor = bg;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = SCILocalized(@"Mentions");
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *closeImg = [UIImage systemImageNamed:@"xmark"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                            weight:UIImageSymbolWeightSemibold]];
    [closeBtn setImage:closeImg forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor secondaryLabelColor];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor separatorColor];
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor separatorColor];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16 + kAvatarSize + 14, 0, 0);
    self.tableView.rowHeight = kRowHeight;

    [self.view addSubview:titleLabel];
    [self.view addSubview:closeBtn];
    [self.view addSubview:sep];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [closeBtn.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:30],
        [closeBtn.heightAnchor constraintEqualToConstant:30],

        [sep.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14],
        [sep.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],

        [self.tableView.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Bulk-fetch friendship statuses for all mentions in one round trip.
    self.friendshipStatuses = [NSMutableDictionary dictionary];
    NSMutableArray *pks = [NSMutableArray array];
    for (NSDictionary *info in self.userInfos) {
        NSString *pk = sciUserPK(info[@"userObj"]);
        if (pk.length) [pks addObject:pk];
    }
    if (pks.count) {
        __weak typeof(self) weakSelf = self;
        [SCIInstagramAPI fetchFriendshipStatusesForPKs:pks completion:^(NSDictionary *statuses, NSError *error) {
            if (!statuses.count) return;
            [weakSelf.friendshipStatuses addEntriesFromDictionary:statuses];
            [weakSelf.tableView reloadData];
        }];
    }

    if (self.userInfos.count == 0) {
        UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"at"
              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36
                                                                                weight:UIImageSymbolWeightLight]]];
        emptyIcon.tintColor = [UIColor tertiaryLabelColor];
        emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.text = SCILocalized(@"No mentions in this story");
        emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        emptyLabel.textColor = [UIColor secondaryLabelColor];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *empty = [[UIStackView alloc] initWithArrangedSubviews:@[emptyIcon, emptyLabel]];
        empty.axis = UILayoutConstraintAxisVertical;
        empty.spacing = 12;
        empty.alignment = UIStackViewAlignmentCenter;
        empty.translatesAutoresizingMaskIntoConstraints = NO;

        [self.view addSubview:empty];
        [NSLayoutConstraint activateConstraints:@[
            [empty.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [empty.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        ]];
    }
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Resume story playback when mentions sheet dismisses
    if (sciActiveStoryViewerVC) {
        SEL sel = NSSelectorFromString(@"tryResumePlayback");
        if ([sciActiveStoryViewerVC respondsToSelector:sel]) {
            ((void(*)(id,SEL))objc_msgSend)(sciActiveStoryViewerVC, sel);
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.userInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"mention";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];

    UIImageView *avatar;
    UILabel *nameLabel, *subLabel;
    UIButton *followBtn;
    UIActivityIndicatorView *spinner;
    static const NSInteger kAvTag = 101, kNmTag = 102, kSbTag = 103, kFlTag = 104, kSpTag = 105;

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        avatar = [[UIImageView alloc] init];
        avatar.tag = kAvTag;
        avatar.layer.cornerRadius = kAvatarSize / 2.0;
        avatar.clipsToBounds = YES;
        avatar.contentMode = UIViewContentModeScaleAspectFill;
        avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
        avatar.translatesAutoresizingMaskIntoConstraints = NO;

        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = kNmTag;
        nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        nameLabel.textColor = [UIColor labelColor];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        subLabel = [[UILabel alloc] init];
        subLabel.tag = kSbTag;
        subLabel.font = [UIFont systemFontOfSize:14];
        subLabel.textColor = [UIColor secondaryLabelColor];
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;

        followBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        followBtn.tag = kFlTag;
        followBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        followBtn.layer.cornerRadius = 8;
        followBtn.clipsToBounds = YES;
        followBtn.translatesAutoresizingMaskIntoConstraints = NO;

        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.tag = kSpTag;
        spinner.hidesWhenStopped = YES;
        spinner.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, subLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 2;
        text.translatesAutoresizingMaskIntoConstraints = NO;

        [cell.contentView addSubview:avatar];
        [cell.contentView addSubview:text];
        [cell.contentView addSubview:followBtn];
        [followBtn addSubview:spinner];

        [NSLayoutConstraint activateConstraints:@[
            [avatar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [avatar.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [avatar.widthAnchor constraintEqualToConstant:kAvatarSize],
            [avatar.heightAnchor constraintEqualToConstant:kAvatarSize],
            [text.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:14],
            [text.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [text.trailingAnchor constraintLessThanOrEqualToAnchor:followBtn.leadingAnchor constant:-10],
            [followBtn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [followBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [followBtn.widthAnchor constraintGreaterThanOrEqualToConstant:90],
            [followBtn.heightAnchor constraintEqualToConstant:32],
            [spinner.centerXAnchor constraintEqualToAnchor:followBtn.centerXAnchor],
            [spinner.centerYAnchor constraintEqualToAnchor:followBtn.centerYAnchor],
        ]];
    } else {
        avatar    = [cell.contentView viewWithTag:kAvTag];
        nameLabel = [cell.contentView viewWithTag:kNmTag];
        subLabel  = [cell.contentView viewWithTag:kSbTag];
        followBtn = [cell.contentView viewWithTag:kFlTag];
        spinner   = [followBtn viewWithTag:kSpTag];
    }

    NSDictionary *info = self.userInfos[indexPath.row];
    NSString *username = info[@"username"] ?: @"Unknown";
    NSString *fullName = info[@"fullName"];
    NSURL *picURL = info[@"picURL"];

    nameLabel.text = username;
    subLabel.text = fullName ?: @"";
    subLabel.hidden = !fullName.length;

    avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
    avatar.tintColor = [UIColor tertiaryLabelColor];

    if (picURL) {
        NSInteger row = indexPath.row;
        [SCIImageCache loadImageFromURL:picURL completion:^(UIImage *img) {
            if (!img) return;
            UITableViewCell *c = [tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:row inSection:0]];
            if (!c) return;
            UIImageView *av = [c.contentView viewWithTag:kAvTag];
            if (av) { av.image = img; av.tintColor = nil; }
        }];
    }

    [followBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [spinner stopAnimating];
    spinner.color = [UIColor whiteColor];

    BOOL isMe = self.currentUsername && [username isEqualToString:self.currentUsername];
    if (isMe) {
        followBtn.hidden = YES;
    } else {
        followBtn.hidden = NO;
        id userObj = info[@"userObj"];

        BOOL following = NO;
        NSString *pk = sciUserPK(userObj);
        NSDictionary *status = pk ? self.friendshipStatuses[pk] : nil;
        if ([status isKindOfClass:[NSDictionary class]]) {
            following = [status[@"following"] boolValue];
        }
        sciStyleFollowBtn(followBtn, following);

        objc_setAssociatedObject(followBtn, "userObj", userObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [followBtn addTarget:self action:@selector(followTapped:) forControlEvents:UIControlEventTouchUpInside];
    }

    return cell;
}

- (void)followTapped:(UIButton *)sender {
    id userObj = objc_getAssociatedObject(sender, "userObj");
    if (!userObj) return;
    NSString *pk = sciUserPK(userObj);
    if (!pk.length) return;

    BOOL currentlyFollowing = [[sender titleForState:UIControlStateNormal] isEqualToString:@"Following"];

    void (^doIt)(void) = ^{
        UIActivityIndicatorView *spinner = [sender viewWithTag:105];
        NSString *savedTitle = [sender titleForState:UIControlStateNormal];
        [sender setTitle:@"" forState:UIControlStateNormal];
        sender.userInteractionEnabled = NO;
        [spinner startAnimating];

        __weak typeof(self) weakSelf = self;
        SCIAPICompletion done = ^(NSDictionary *response, NSError *error) {
            [spinner stopAnimating];
            sender.userInteractionEnabled = YES;
            BOOL ok = (response && [response[@"status"] isEqualToString:@"ok"]);
            if (ok) {
                sciStyleFollowBtn(sender, !currentlyFollowing);
                NSMutableDictionary *s = [weakSelf.friendshipStatuses[pk] mutableCopy] ?: [NSMutableDictionary dictionary];
                s[@"following"] = @(!currentlyFollowing);
                weakSelf.friendshipStatuses[pk] = [s copy];
            } else {
                [sender setTitle:savedTitle forState:UIControlStateNormal];
            }
        };

        if (currentlyFollowing) [SCIInstagramAPI unfollowUserPK:pk completion:done];
        else                    [SCIInstagramAPI followUserPK:pk   completion:done];
    };

    if (!currentlyFollowing && [SCIUtils getBoolPref:@"follow_confirm"]) {
        [SCIUtils showConfirmation:doIt];
    } else if (currentlyFollowing && [SCIUtils getBoolPref:@"unfollow_confirm"]) {
        [SCIUtils showConfirmation:doIt];
    } else {
        doIt();
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *info = self.userInfos[indexPath.row];
    NSString *username = info[@"username"];
    if (!username) return;
    [self dismissViewControllerAnimated:YES completion:^{
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", username]];
        if ([[UIApplication sharedApplication] canOpenURL:url])
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }];
}

@end

// ============ Entry points ============

void sciShowStoryMentions(UIViewController *presenter, UIView *anchor) {
    if (![SCIUtils getBoolPref:@"view_story_mentions"]) return;

    NSArray *mentions = sciCurrentStoryMentions(anchor);
    NSMutableArray *infos = [NSMutableArray array];
    for (id mention in mentions) {
        NSDictionary *info = sciMentionUserInfo(mention);
        if (info) [infos addObject:info];
    }

    SCIStoryMentionsVC *vc = [[SCIStoryMentionsVC alloc] init];
    vc.userInfos = [infos copy];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        @try { [sheet setValue:@YES forKey:@"prefersGrabberIndicator"]; } @catch (__unused id e) {}
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }

    [presenter presentViewController:vc animated:YES completion:nil];
}

NSArray *sciMaybeAppendStoryMentionsMenuItem(NSArray *items) {
    if (!sciActiveStoryViewerVC) return items;
    if (![SCIUtils getBoolPref:@"view_story_mentions"]) return items;

    BOOL looksLikeStoryHeader = NO;
    for (id it in items) {
        @try {
            NSString *t = [NSString stringWithFormat:@"%@", [it valueForKey:@"title"] ?: @""];
            if ([t isEqualToString:@"Report"] || [t isEqualToString:@"Mute"] ||
                [t isEqualToString:@"Unfollow"] || [t isEqualToString:@"Follow"] ||
                [t isEqualToString:@"Hide"]) { looksLikeStoryHeader = YES; break; }
        } @catch (__unused id e) {}
    }
    if (!looksLikeStoryHeader) return items;

    Class menuItemCls = NSClassFromString(@"IGDSMenuItem");
    if (!menuItemCls) return items;

    __weak UIViewController *weakVC = sciActiveStoryViewerVC;
    void (^handler)(void) = ^{
        UIViewController *vc = weakVC;
        if (!vc) return;
        sciShowStoryMentions(vc, vc.view);
    };

    id newItem = nil;
    @try {
        typedef id (*Init)(id, SEL, id, id, id);
        newItem = ((Init)objc_msgSend)([menuItemCls alloc],
            @selector(initWithTitle:image:handler:), @"View mentions", nil, handler);
    } @catch (__unused id e) {}

    if (!newItem) return items;
    NSMutableArray *newItems = [items mutableCopy];
    [newItems addObject:newItem];
    return [newItems copy];
}
