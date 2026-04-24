// Follow indicator — shows whether the profile user follows you.
// Fetches via /api/v1/friendships/show/{pk}/, renders inside the stats container.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <objc/runtime.h>
#import <objc/message.h>

// IGProfileViewController declared in InstagramHeaders.h

static const NSInteger kFollowBadgeTag = 99788;

// Cache follow status on the VC to avoid re-fetching
static const char kFollowStatusKey;
static NSNumber *sciGetFollowStatus(id vc) {
    return objc_getAssociatedObject(vc, &kFollowStatusKey);
}
static void sciSetFollowStatus(id vc, NSNumber *status) {
    objc_setAssociatedObject(vc, &kFollowStatusKey, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void sciRenderBadge(UIViewController *vc) {
    NSNumber *status = sciGetFollowStatus(vc);
    if (!status) return;
    BOOL followedBy = [status boolValue];

    UIView *statContainer = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass([v class]) containsString:@"StatButtonContainerView"]) {
            statContainer = v;
            break;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    if (!statContainer) return;

    UIView *old = [statContainer viewWithTag:kFollowBadgeTag];
    if (old) [old removeFromSuperview];

    NSString *text = followedBy ? SCILocalized(@"Follows you") : SCILocalized(@"Doesn't follow you");
    SCIChromeLabel *badge = [[SCIChromeLabel alloc] initWithText:text];
    badge.tag = kFollowBadgeTag;
    badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    badge.textColor = followedBy
        ? [UIColor colorWithRed:0.3 green:0.75 blue:0.4 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.3 blue:0.3 alpha:1.0];
    [statContainer addSubview:badge];

    // Pinned to the leading edge so it sits flush-left on any device + RTL.
    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:statContainer.leadingAnchor],
        [badge.bottomAnchor constraintEqualToAnchor:statContainer.bottomAnchor constant:-8],
    ]];
}

%hook IGProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (![SCIUtils getBoolPref:@"follow_indicator"]) return;

    // Already fetched — just re-render
    if (sciGetFollowStatus(self)) {
        sciRenderBadge(self);
        return;
    }

    id igUser = nil;
    @try { igUser = [self valueForKey:@"user"]; } @catch (NSException *e) {}
    if (!igUser) return;

    NSString *profilePK = [SCIUtils pkFromIGUser:igUser];
    NSString *myPK = [SCIUtils currentUserPK];
    if (!profilePK || !myPK || [profilePK isEqualToString:myPK]) return;

    __weak UIViewController *weakSelf = self;
    NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", profilePK];
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error || !response) return;
        BOOL followedBy = [response[@"followed_by"] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = weakSelf;
            if (!vc) return;
            sciSetFollowStatus(vc, @(followedBy));
            sciRenderBadge(vc);
        });
    }];
}

%end
