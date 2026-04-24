// Messages-only mode — no-op the tab creators we don't want, force inbox at launch.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL sciMsgOnly(void) { return [SCIUtils getBoolPref:@"messages_only"]; }
static BOOL sciMsgOnlyHideTabBar(void) {
    return sciMsgOnly() && [SCIUtils getBoolPref:@"messages_only_hide_tabbar"];
}

%hook IGTabBarController

// Block tab creation entirely so they never enter the buttons array (no gaps).
- (void)_createAndConfigureTimelineButtonIfNeeded   { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureReelsButtonIfNeeded      { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureExploreButtonIfNeeded    { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureCameraButtonIfNeeded     { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureDynamicTabButtonIfNeeded { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureNewsButtonIfNeeded       { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureStreamsButtonIfNeeded    { if (sciMsgOnly()) return; %orig; }

// Force initial selection to inbox once after the tab bar has fully laid out.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static BOOL launched = NO;
    if (sciMsgOnly() && !launched) {
        launched = YES;
        SEL s = NSSelectorFromString(@"_directInboxButtonPressed");
        if ([self respondsToSelector:s])
            ((void(*)(id, SEL))objc_msgSend)(self, s);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!sciMsgOnlyHideTabBar()) return;
    Ivar tbIv = class_getInstanceVariable([self class], "_tabBar");
    UIView *tabBar = tbIv ? object_getIvar(self, tbIv) : nil;
    if (tabBar) {
        tabBar.hidden = YES;
        tabBar.alpha = 0.0;
    }
    UIViewController *selected = [self valueForKey:@"selectedViewController"];
    if (selected.isViewLoaded) {
        selected.view.frame = self.view.bounds;
    }
}

// Surface enum no longer maps cleanly to the trimmed _buttons array, so flip
// the selected state ourselves and nudge the liquid-glass indicator.
%new - (void)sciSyncTabBarSelection:(NSString *)which {
    Class c = [self class];
    Ivar ibIv = class_getInstanceVariable(c, "_directInboxButton");
    Ivar pbIv = class_getInstanceVariable(c, "_profileButton");
    UIButton *inbox = ibIv ? object_getIvar(self, ibIv) : nil;
    UIButton *profile = pbIv ? object_getIvar(self, pbIv) : nil;
    BOOL profileActive = [which isEqualToString:@"profile"];
    if ([inbox respondsToSelector:@selector(setSelected:)]) inbox.selected = !profileActive;
    if ([profile respondsToSelector:@selector(setSelected:)]) profile.selected = profileActive;

    // No-op on classic tab bar (selector only exists on IGLiquidGlassInteractiveTabBar).
    Ivar tbIv = class_getInstanceVariable(c, "_tabBar");
    id tabBar = tbIv ? object_getIvar(self, tbIv) : nil;
    NSInteger idx = profileActive ? 1 : 0;
    SEL setIdx = NSSelectorFromString(@"setSelectedTabBarItemIndex:animateIndicator:");
    if ([tabBar respondsToSelector:setIdx])
        ((void(*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tabBar, setIdx, idx, YES);
}

- (void)_directInboxButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"inbox");
}
- (void)_profileButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"profile");
}

%end

// Floating settings button — long-press on tab bar is gone when it's hidden.
static const void *kSCIMsgOnlyBtnKey = &kSCIMsgOnlyBtnKey;

static void sciMsgOnlyInjectSettingsButton(UIViewController *vc) {
    if (!sciMsgOnlyHideTabBar() || !vc || !vc.isViewLoaded) return;
    if (objc_getAssociatedObject(vc, kSCIMsgOnlyBtnKey)) return;

    SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:@"gearshape"
                                                         pointSize:18
                                                          diameter:36];
    btn.iconTint = [UIColor labelColor];
    btn.bubbleColor = [UIColor clearColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:vc action:@selector(sciMsgOnlyOpenSettings)
          forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:btn];

    UILayoutGuide *sa = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.leadingAnchor constraintEqualToAnchor:sa.leadingAnchor constant:12],
        [btn.topAnchor constraintEqualToAnchor:sa.topAnchor constant:6],
        [btn.widthAnchor constraintEqualToConstant:36],
        [btn.heightAnchor constraintEqualToConstant:36],
    ]];

    objc_setAssociatedObject(vc, kSCIMsgOnlyBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGDirectInboxViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sciMsgOnlyInjectSettingsButton((UIViewController *)self);
}

%new - (void)sciMsgOnlyOpenSettings {
    UIViewController *vc = (UIViewController *)self;
    [SCIUtils showSettingsVC:vc.view.window];
}
%end
