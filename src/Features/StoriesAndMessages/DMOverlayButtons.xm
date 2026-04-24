// DM disappearing-media overlay buttons — action / eye / audio (tags 1342–1344).
// Hooks IGDirectVisualMessageViewerController directly; reads only dm_visual_* prefs.

#import "OverlayHelpers.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIMediaViewer.h"

// Per-button weak ref to the owning DM VC so handlers skip the responder walk.
static const void *kSCIDMOwnerVCKey = &kSCIDMOwnerVCKey;

// MARK: - Menu item builders

static NSArray<UIMenuElement *> *sciDMActionMenuItems(UIViewController *dmVC, UIView *sourceView) {
    __weak UIView *weakSource = sourceView;
    return @[
        [UIAction actionWithTitle:SCILocalized(@"Expand")
                            image:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]
                       identifier:nil
                          handler:^(UIAction *a) { sciDMExpandMedia(dmVC); }],
        [UIAction actionWithTitle:SCILocalized(@"Messages settings")
                            image:[UIImage systemImageNamed:@"gearshape"]
                       identifier:nil
                          handler:^(UIAction *a) { sciOpenMessagesSettings(weakSource); }],
        [UIAction actionWithTitle:SCILocalized(@"Download and share")
                            image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                       identifier:nil
                          handler:^(UIAction *a) { sciDMShareMedia(dmVC); }],
        [UIAction actionWithTitle:SCILocalized(@"Download to Photos")
                            image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                       identifier:nil
                          handler:^(UIAction *a) { sciDMDownloadMedia(dmVC); }],
    ];
}

static NSArray<UIMenuElement *> *sciDMEyeMenuItems(UIViewController *dmVC, UIView *sourceView) {
    __weak UIView *weakSource = sourceView;
    return @[
        [UIAction actionWithTitle:SCILocalized(@"Mark as viewed")
                            image:[UIImage systemImageNamed:@"eye"]
                       identifier:nil
                          handler:^(UIAction *a) { sciDMMarkCurrentAsViewed(dmVC); }],
        [UIAction actionWithTitle:SCILocalized(@"Messages settings")
                            image:[UIImage systemImageNamed:@"gearshape"]
                       identifier:nil
                          handler:^(UIAction *a) { sciOpenMessagesSettings(weakSource); }],
    ];
}

static void sciDMApplyTapMenu(UIButton *btn, __weak UIViewController *weakDMVC) {
    __weak UIButton *weakBtn = btn;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:
        ^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        UIViewController *dmVC = weakDMVC;
        UIButton *strongBtn = weakBtn;
        if (!dmVC || !strongBtn) { completion(@[]); return; }
        completion(sciDMActionMenuItems(dmVC, strongBtn));
    }];
    btn.menu = [UIMenu menuWithChildren:@[deferred]];
    btn.showsMenuAsPrimaryAction = YES;
}

// MARK: - Button delegate (tap handlers)

@interface SCIDMButtonDelegate : NSObject
+ (instancetype)shared;
- (void)actionTapped:(UIButton *)sender;
- (void)eyeTapped:(UIButton *)sender;
- (void)audioTapped:(UIButton *)sender;
@end

@implementation SCIDMButtonDelegate

+ (instancetype)shared {
    static SCIDMButtonDelegate *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIDMButtonDelegate new]; });
    return s;
}

- (UIViewController *)ownerForButton:(UIView *)btn {
    return objc_getAssociatedObject(btn, kSCIDMOwnerVCKey);
}

// Default-tap path (pref != menu).
- (void)actionTapped:(UIButton *)sender {
    UIViewController *dmVC = [self ownerForButton:sender];
    if (!dmVC) return;
    NSString *tap = [SCIUtils getStringPref:@"dm_visual_action_default"];
    if ([tap isEqualToString:@"expand"])               sciDMExpandMedia(dmVC);
    else if ([tap isEqualToString:@"download_share"])  sciDMShareMedia(dmVC);
    else if ([tap isEqualToString:@"download_photos"]) sciDMDownloadMedia(dmVC);
}

- (void)eyeTapped:(UIButton *)sender {
    UIViewController *dmVC = [self ownerForButton:sender];
    if (!dmVC) return;
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.8, 0.8); sender.alpha = 0.6; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ sender.transform = CGAffineTransformIdentity; sender.alpha = 1.0; }]; }];
    sciDMMarkCurrentAsViewed(dmVC);
}

- (void)audioTapped:(SCIChromeButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    sciToggleStoryAudio();
    sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

@end

// MARK: - Long-press menu builder

// UIButton.menu + showsMenuAsPrimaryAction=NO is iOS's native pattern for
// "tap fires action, long-press shows menu". Compose a UIDeferredMenuElement
// so the menu rebuilds per presentation — owner lookup stays fresh.
static void sciDMAttachLongPressMenu(SCIChromeButton *btn, NSInteger tag) {
    __weak SCIChromeButton *weakBtn = btn;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:
        ^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        SCIChromeButton *strongBtn = weakBtn;
        UIViewController *dmVC = strongBtn ? objc_getAssociatedObject(strongBtn, kSCIDMOwnerVCKey) : nil;
        if (!dmVC) { completion(@[]); return; }
        NSArray<UIMenuElement *> *items = (tag == SCI_DM_ACTION_TAG)
            ? sciDMActionMenuItems(dmVC, strongBtn)
            : sciDMEyeMenuItems(dmVC, strongBtn);
        completion(items);
    }];
    btn.menu = [UIMenu menuWithChildren:@[deferred]];
    btn.showsMenuAsPrimaryAction = NO;
}

// MARK: - Overlay injection

static void sciDMInstallButtons(UIViewController *dmVC) {
    if (!dmVC || !dmVC.isViewLoaded) return;
    UIView *overlay = sciFindOverlayInView(dmVC.view);
    if (!overlay) return;

    // Kill any story-tag injections from the shared overlay hook.
    UIView *sA = [overlay viewWithTag:SCI_STORY_ACTION_TAG]; if (sA) [sA removeFromSuperview];
    UIView *sE = [overlay viewWithTag:SCI_STORY_EYE_TAG];    if (sE) [sE removeFromSuperview];
    UIView *sU = [overlay viewWithTag:SCI_STORY_AUDIO_TAG];  if (sU) [sU removeFromSuperview];

    SCIDMButtonDelegate *dg = [SCIDMButtonDelegate shared];

    // --- Action button (tag 1342) ---
    UIView *staleAction = [overlay viewWithTag:SCI_DM_ACTION_TAG];
    if (staleAction) [staleAction removeFromSuperview];
    if ([SCIUtils getBoolPref:@"dm_visual_action_button"]) {
        SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:@"ellipsis.circle" pointSize:18 diameter:36];
        btn.tag = SCI_DM_ACTION_TAG;
        objc_setAssociatedObject(btn, kSCIDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);
        [overlay addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];

        NSString *defaultTap = [SCIUtils getStringPref:@"dm_visual_action_default"];
        if (!defaultTap.length || [defaultTap isEqualToString:@"menu"]) {
            sciDMApplyTapMenu(btn, dmVC);
        } else {
            // Tap = default action, long-press = full menu.
            [btn addTarget:dg action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            sciDMAttachLongPressMenu(btn, SCI_DM_ACTION_TAG);
        }
    }

    // --- Eye / mark-as-viewed (tag 1343) ---
    UIView *staleEye = [overlay viewWithTag:SCI_DM_EYE_TAG];
    if (staleEye) [staleEye removeFromSuperview];
    if ([SCIUtils getBoolPref:@"dm_visual_seen_button"]) {
        SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:@"eye" pointSize:18 diameter:36];
        btn.tag = SCI_DM_EYE_TAG;
        objc_setAssociatedObject(btn, kSCIDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);
        [btn addTarget:dg action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
        sciDMAttachLongPressMenu(btn, SCI_DM_EYE_TAG);
        [overlay addSubview:btn];

        UIView *anchor = [overlay viewWithTag:SCI_DM_ACTION_TAG];
        if (anchor) {
            [NSLayoutConstraint activateConstraints:@[
                [btn.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
                [btn.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10],
                [btn.widthAnchor constraintEqualToConstant:36],
                [btn.heightAnchor constraintEqualToConstant:36]
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [btn.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-100],
                [btn.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-12],
                [btn.widthAnchor constraintEqualToConstant:36],
                [btn.heightAnchor constraintEqualToConstant:36]
            ]];
        }
    }

    // --- Audio toggle (tag 1344) ---
    UIView *staleAudio = [overlay viewWithTag:SCI_DM_AUDIO_TAG];
    if (staleAudio) [staleAudio removeFromSuperview];
    sciInitStoryAudioState();
    if ([SCIUtils getBoolPref:@"dm_visual_audio_toggle"]) {
        NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
        SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:icon pointSize:14 diameter:28];
        btn.tag = SCI_DM_AUDIO_TAG;
        [btn addTarget:dg action:@selector(audioTapped:) forControlEvents:UIControlEventTouchUpInside];
        [overlay addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:12],
            [btn.widthAnchor constraintEqualToConstant:28],
            [btn.heightAnchor constraintEqualToConstant:28]
        ]];
    }
}

// Rebuild only when an enabled button is missing — handles overlay recycling.
static void sciDMEnsureButtons(UIViewController *dmVC) {
    if (!dmVC || !dmVC.isViewLoaded) return;
    UIView *overlay = sciFindOverlayInView(dmVC.view);
    if (!overlay) return;

    BOOL needAction = [SCIUtils getBoolPref:@"dm_visual_action_button"] && ![overlay viewWithTag:SCI_DM_ACTION_TAG];
    BOOL needEye    = [SCIUtils getBoolPref:@"dm_visual_seen_button"]   && ![overlay viewWithTag:SCI_DM_EYE_TAG];
    BOOL needAudio  = [SCIUtils getBoolPref:@"dm_visual_audio_toggle"]  && ![overlay viewWithTag:SCI_DM_AUDIO_TAG];
    if (needAction || needEye || needAudio) sciDMInstallButtons(dmVC);
}

// MARK: - VC hook

%group DMOverlayGroup

%hook IGDirectVisualMessageViewerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciDMInstallButtons(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    sciDMEnsureButtons(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (!self.isViewLoaded) return;
    UIView *overlay = sciFindOverlayInView(self.view);
    if (!overlay) return;
    UIView *a = [overlay viewWithTag:SCI_DM_ACTION_TAG]; if (a) [a removeFromSuperview];
    UIView *e = [overlay viewWithTag:SCI_DM_EYE_TAG];    if (e) [e removeFromSuperview];
    UIView *u = [overlay viewWithTag:SCI_DM_AUDIO_TAG];  if (u) [u removeFromSuperview];
}

%end

%end // DMOverlayGroup

%ctor {
    if ([SCIUtils getBoolPref:@"dm_visual_action_button"] ||
        [SCIUtils getBoolPref:@"dm_visual_seen_button"] ||
        [SCIUtils getBoolPref:@"dm_visual_audio_toggle"]) {
        %init(DMOverlayGroup);
    }
}
