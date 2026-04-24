// Story overlay buttons — action / audio / eye (tags 1339–1341).
// Early-exits in DM context; DMOverlayButtons.xm handles that surface.

#import "OverlayHelpers.h"
#import "SCIExcludedStoryUsers.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../Downloader/Download.h"

extern "C" BOOL sciSeenBypassActive;
extern "C" BOOL sciAdvanceBypassActive;
extern "C" void sciAllowSeenForPK(id);
extern "C" BOOL sciStorySeenToggleEnabled;
extern "C" void sciRefreshAllVisibleOverlays(UIViewController *storyVC);
extern "C" void sciTriggerStoryMarkSeen(UIViewController *storyVC);
extern "C" __weak UIViewController *sciActiveStoryViewerVC;
extern "C" NSDictionary *sciOwnerInfoForView(UIView *view);
extern "C" void sciShowStoryMentions(UIViewController *, UIView *);

// MARK: - Playback control

static void sciPauseStoryPlayback(UIView *sourceView) {
    UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
    if (!storyVC) return;
    id sc = sciFindSectionController(storyVC);

    SEL pauseSel = NSSelectorFromString(@"pauseWithReason:");
    if (sc && [sc respondsToSelector:pauseSel]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc, pauseSel, 10);
        return;
    }
    if ([storyVC respondsToSelector:pauseSel]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, pauseSel, 10);
    }
}

static void sciResumeStoryPlayback(UIView *sourceView) {
    UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
    if (!storyVC) return;
    id sc = sciFindSectionController(storyVC);

    SEL resumeSel1 = NSSelectorFromString(@"tryResumePlaybackWithReason:");
    SEL resumeSel2 = NSSelectorFromString(@"tryResumePlayback");
    if (sc && [sc respondsToSelector:resumeSel1]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc, resumeSel1, 0);
        return;
    }
    if ([storyVC respondsToSelector:resumeSel2]) {
        ((void(*)(id, SEL))objc_msgSend)(storyVC, resumeSel2);
        return;
    }
    if ([storyVC respondsToSelector:resumeSel1]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, resumeSel1, 0);
    }
}

// MARK: - Overlay hook

%group StoryOverlayGroup

%hook IGStoryFullscreenOverlayView

- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;

    // Strip stale tags up-front so nothing flashes when this overlay
    // turns out to belong to a DM viewer.
    UIView *sA = [self viewWithTag:SCI_STORY_ACTION_TAG]; if (sA) [sA removeFromSuperview];
    UIView *sE = [self viewWithTag:SCI_STORY_EYE_TAG];    if (sE) [sE removeFromSuperview];
    UIView *sU = [self viewWithTag:SCI_STORY_AUDIO_TAG];  if (sU) [sU removeFromSuperview];

    // Defer one tick — responder chain isn't complete yet, so the DM
    // context check needs to run after the current runloop iteration.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.superview) return;
        if (sciOverlayIsInDMContext(strongSelf)) return;
        ((void(*)(id, SEL))objc_msgSend)(strongSelf, @selector(sciInstallStoryOverlayButtons));
    });
}

%new - (void)sciInstallStoryOverlayButtons {
    if (!self.superview) return;

    // --- Action button (tag 1340) ---
    UIView *staleAction = [self viewWithTag:SCI_STORY_ACTION_TAG];
    if (staleAction) {
        @try { [staleAction removeObserver:self forKeyPath:@"highlighted"]; } @catch (__unused id e) {}
        [staleAction removeFromSuperview];
    }
    if ([SCIUtils getBoolPref:@"stories_action_button"]) {
        SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:@"ellipsis.circle" pointSize:18 diameter:36];
        btn.tag = SCI_STORY_ACTION_TAG;
        [self addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];

        SCIActionMediaProvider provider = ^id (UIView *sourceView) {
            sciPauseStoryPlayback(sourceView);
            id item = sciGetCurrentStoryItem(sourceView);
            if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;
            id extracted = sciExtractMediaFromItem(item);
            return extracted ?: (id)kCFNull;
        };

        [SCIActionButton configureButton:btn
                                 context:SCIActionContextStories
                                 prefKey:@"stories_action_default"
                           mediaProvider:provider];

        // Resume playback when the native UIMenu dismisses.
        [btn addObserver:self forKeyPath:@"highlighted"
                 options:NSKeyValueObservingOptionNew context:NULL];

        // Reel items provider — used by SCIMediaActions for "download all".
        static const void *kStoryReelItemsProvider = &kStoryReelItemsProvider;
        objc_setAssociatedObject(btn, kStoryReelItemsProvider, ^NSArray *(UIView *src) {
            UIViewController *storyVC = sciFindVC(src, @"IGStoryViewerViewController");
            if (!storyVC) return nil;
            id vm = sciCall(storyVC, @selector(currentViewModel));
            if (!vm) return nil;

            for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
                if ([vm respondsToSelector:NSSelectorFromString(sel)]) {
                    @try {
                        id val = ((id(*)(id,SEL))objc_msgSend)(vm, NSSelectorFromString(sel));
                        if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) return val;
                    } @catch (__unused id e) {}
                }
            }

            Class mc = NSClassFromString(@"IGMedia");
            unsigned int cnt = 0;
            Ivar *ivs = class_copyIvarList(object_getClass(vm), &cnt);
            for (unsigned int i = 0; i < cnt; i++) {
                const char *type = ivar_getTypeEncoding(ivs[i]);
                if (!type || type[0] != '@') continue;
                @try {
                    id val = object_getIvar(vm, ivs[i]);
                    if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) {
                        id first = [(NSArray *)val firstObject];
                        if (mc && [first isKindOfClass:mc]) { free(ivs); return val; }
                        IGMedia *extracted = sciExtractMediaFromItem(first);
                        if (extracted) { free(ivs); return val; }
                    }
                } @catch (__unused id e) {}
            }
            if (ivs) free(ivs);
            return nil;
        }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }

    // --- Audio toggle (tag 1341) ---
    UIView *staleAudio = [self viewWithTag:SCI_STORY_AUDIO_TAG];
    if (staleAudio) [staleAudio removeFromSuperview];
    sciInitStoryAudioState();
    if ([SCIUtils getBoolPref:@"story_audio_toggle"]) {
        NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
        SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:icon pointSize:14 diameter:28];
        btn.tag = SCI_STORY_AUDIO_TAG;
        [btn addTarget:self action:@selector(sciStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [btn.widthAnchor constraintEqualToConstant:28],
            [btn.heightAnchor constraintEqualToConstant:28]
        ]];
    }

    // --- Eye / mark-seen (tag 1339) ---
    // layoutSubviews can fire between the tick-0 strip and now, creating
    // the eye with fallback constraints before the action exists. Drop it
    // so the refresh rebuilds it anchored to the action button.
    UIView *staleEye = [self viewWithTag:SCI_STORY_EYE_TAG];
    if (staleEye) [staleEye removeFromSuperview];
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
}

// MARK: - Action button menu-dismiss resume

%new - (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                              change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"highlighted"]) {
        BOOL highlighted = [change[NSKeyValueChangeNewKey] boolValue];
        if (!highlighted) sciResumeStoryPlayback(self);
    }
}

// MARK: - Audio toggle

%new - (void)sciStoryAudioToggleTapped:(SCIChromeButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    sciToggleStoryAudio();
    sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

%new - (void)sciRefreshStoryAudioButton {
    SCIChromeButton *btn = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];
    if (![btn isKindOfClass:[SCIChromeButton class]]) return;
    btn.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

// MARK: - Seen eye button

// Visible only when no_seen_receipt is on and the owner isn't excluded.
%new - (void)sciRefreshSeenButton {
    BOOL seenBlockingOn = [SCIUtils getBoolPref:@"no_seen_receipt"];
    if (!seenBlockingOn) { UIView *old = [self viewWithTag:SCI_STORY_EYE_TAG]; if (old) [old removeFromSuperview]; return; }

    NSDictionary *ownerInfo = sciOwnerInfoForView(self);
    NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
    BOOL excluded = ownerPK.length && [SCIExcludedStoryUsers isUserPKExcluded:ownerPK];
    SCIChromeButton *existing = (SCIChromeButton *)[self viewWithTag:SCI_STORY_EYE_TAG];
    if (![existing isKindOfClass:[SCIChromeButton class]]) existing = nil;

    if (excluded) { if (existing) [existing removeFromSuperview]; return; }

    BOOL toggleMode = [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
    NSString *symName;
    UIColor *tint;
    if (toggleMode) {
        symName = sciStorySeenToggleEnabled ? @"eye.fill" : @"eye";
        tint = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : [UIColor whiteColor];
    } else {
        symName = @"eye"; tint = [UIColor whiteColor];
    }

    if (existing) {
        existing.symbolName = symName;
        existing.iconTint = tint;
        return;
    }

    SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:symName pointSize:18 diameter:36];
    btn.tag = SCI_STORY_EYE_TAG;
    btn.iconTint = tint;
    [btn addTarget:self action:@selector(sciStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    // Long-press → context menu (positions itself next to the button).
    UIContextMenuInteraction *ix = [[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
    [btn addInteraction:ix];
    [self addSubview:btn];

    UIView *anchor = [self viewWithTag:SCI_STORY_ACTION_TAG];
    if (anchor) {
        [NSLayoutConstraint activateConstraints:@[
            [btn.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
            [btn.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];
    }
}

// MARK: - Owner / audio refresh on layout

- (void)layoutSubviews {
    %orig;
    static char kLastPKKey;
    static char kLastExclKey;
    static char kLastAudioKey;

    UIButton *audioBtn = (UIButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];
    if (audioBtn) {
        BOOL audioOn = sciIsStoryAudioEnabled();
        NSNumber *prevAudio = objc_getAssociatedObject(self, &kLastAudioKey);
        if (!prevAudio || [prevAudio boolValue] != audioOn) {
            objc_setAssociatedObject(self, &kLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryAudioButton));
        }
    }

    if (![SCIUtils getBoolPref:@"no_seen_receipt"]) return;
    NSDictionary *info = sciOwnerInfoForView(self);
    NSString *pk = info[@"pk"] ?: @"";
    BOOL excluded = pk.length && [SCIExcludedStoryUsers isUserPKExcluded:pk];
    NSString *prev = objc_getAssociatedObject(self, &kLastPKKey);
    NSNumber *prevExcl = objc_getAssociatedObject(self, &kLastExclKey);
    BOOL changed = ![pk isEqualToString:prev ?: @""] || (prevExcl && [prevExcl boolValue] != excluded);
    if (!changed) return;
    objc_setAssociatedObject(self, &kLastPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &kLastExclKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
}

// MARK: - Seen button tap handlers

%new - (void)sciStorySeenButtonTapped:(SCIChromeButton *)sender {
    if ([[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"]) {
        sciStorySeenToggleEnabled = !sciStorySeenToggleEnabled;
        sender.symbolName = sciStorySeenToggleEnabled ? @"eye.fill" : @"eye";
        sender.iconTint = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : [UIColor whiteColor];
        [SCIUtils showToastForDuration:2.0 title:sciStorySeenToggleEnabled ? SCILocalized(@"Story read receipts enabled") : SCILocalized(@"Story read receipts disabled")];
        return;
    }
    ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), sender);
}

// Long-press menu — rebuilt per display so owner/exclusion is always fresh.
%new - (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                             configurationForMenuAtLocation:(CGPoint)location {
    __weak __typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        NSDictionary *ownerInfo = sciOwnerInfoForView(strongSelf);
        NSString *pk = ownerInfo[@"pk"];
        NSString *username = ownerInfo[@"username"] ?: @"";
        NSString *fullName = ownerInfo[@"fullName"] ?: @"";
        BOOL inList = pk && [SCIExcludedStoryUsers isInList:pk];
        BOOL blockSelected = [SCIExcludedStoryUsers isBlockSelectedMode];

        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        [items addObject:[UIAction actionWithTitle:SCILocalized(@"Mark seen")
                                             image:[UIImage systemImageNamed:@"eye"]
                                        identifier:nil
                                           handler:^(UIAction *a) {
            ((void(*)(id, SEL, id))objc_msgSend)(strongSelf, @selector(sciStoryMarkSeenTapped:), nil);
        }]];
        if (pk) {
            NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen");
            NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen");
            NSString *t = inList ? removeLabel : addLabel;
            NSString *img = inList ? @"minus.circle" : @"eye.slash";
            UIAction *excl = [UIAction actionWithTitle:t
                                                 image:[UIImage systemImageNamed:img]
                                            identifier:nil
                                               handler:^(UIAction *a) {
                if (inList) {
                    [SCIExcludedStoryUsers removePK:pk];
                    [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded")];
                    if (blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
                } else {
                    [SCIExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
                    [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded")];
                    if (!blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
                }
                sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
            }];
            if (inList) excl.attributes = UIMenuElementAttributesDestructive;
            [items addObject:excl];
        }
        return [UIMenu menuWithTitle:@"" children:items];
    }];
}

%new - (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
     willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration
                            animator:(id<UIContextMenuInteractionAnimating>)animator {
    sciPauseStoryPlayback(self);
}

%new - (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
           willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                          animator:(id<UIContextMenuInteractionAnimating>)animator {
    __weak __typeof(self) weakSelf = self;
    void (^resume)(void) = ^{ if (weakSelf) sciResumeStoryPlayback(weakSelf); };
    if (animator) [animator addCompletion:resume];
    else          resume();
}

%new - (void)sciStoryMarkSeenTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    if (sender) {
        [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.8, 0.8); sender.alpha = 0.6; }
                         completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ sender.transform = CGAffineTransformIdentity; sender.alpha = 1.0; }]; }];
    }

    @try {
        UIViewController *storyVC = sciFindVC(self, @"IGStoryViewerViewController");
        if (!storyVC) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")]; return; }

        id sectionCtrl = sciFindSectionController(storyVC);
        id storyItem = sectionCtrl ? sciCall(sectionCtrl, NSSelectorFromString(@"currentStoryItem")) : nil;
        if (!storyItem) storyItem = sciGetCurrentStoryItem(self);
        IGMedia *media = (storyItem && [storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) ? storyItem : sciExtractMediaFromItem(storyItem);
        if (!media) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find story media")]; return; }

        sciAllowSeenForPK(media);
        sciSeenBypassActive = YES;

        SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);
        if ([storyVC respondsToSelector:delegateSel]) {
            typedef void (*Func)(id, SEL, id, id);
            ((Func)objc_msgSend)(storyVC, delegateSel, sectionCtrl, media);
        }
        if (sectionCtrl) {
            SEL markSel = NSSelectorFromString(@"markItemAsSeen:");
            if ([sectionCtrl respondsToSelector:markSel])
                ((SCIMsgSend1)objc_msgSend)(sectionCtrl, markSel, media);
        }
        id seenManager = sciCall(storyVC, @selector(viewingSessionSeenStateManager));
        id vm = sciCall(storyVC, @selector(currentViewModel));
        if (seenManager && vm) {
            SEL setSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");
            if ([seenManager respondsToSelector:setSel]) {
                id mediaPK = sciCall(media, @selector(pk));
                id reelPK = sciCall(vm, NSSelectorFromString(@"reelPK"));
                if (!reelPK) reelPK = sciCall(vm, @selector(pk));
                if (mediaPK && reelPK) {
                    typedef void (*SetFunc)(id, SEL, id, id);
                    ((SetFunc)objc_msgSend)(seenManager, setSel, mediaPK, reelPK);
                }
            }
        }
        sciSeenBypassActive = NO;
        [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Marked as seen") subtitle:SCILocalized(@"Will sync when leaving stories")];

        if (sender && [SCIUtils getBoolPref:@"advance_on_mark_seen"] && sectionCtrl) {
            __block id secCtrl = sectionCtrl;
            __weak __typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sciAdvanceBypassActive = YES;
                SEL advSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
                if ([secCtrl respondsToSelector:advSel])
                    ((void(*)(id, SEL, NSInteger))objc_msgSend)(secCtrl, advSel, 1);

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong __typeof(weakSelf) strongSelf = weakSelf;
                    UIViewController *vc2 = strongSelf ? sciFindVC(strongSelf, @"IGStoryViewerViewController") : nil;
                    id sc2 = vc2 ? sciFindSectionController(vc2) : nil;
                    if (sc2) {
                        SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");
                        if ([sc2 respondsToSelector:resumeSel])
                            ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc2, resumeSel, 0);
                    }
                    sciAdvanceBypassActive = NO;
                });
            });
        }
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Error: %@"), e.reason]];
    }
}

%end

// MARK: - Chrome alpha sync (story only)

static void sciSyncStoryButtonsAlpha(UIView *self_, CGFloat alpha) {
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) return;
    UIView *cur = self_;
    while (cur) {
        for (UIView *sib in cur.superview.subviews) {
            if (![sib isKindOfClass:overlayCls]) continue;
            UIView *seen  = [sib viewWithTag:SCI_STORY_EYE_TAG];
            UIView *act   = [sib viewWithTag:SCI_STORY_ACTION_TAG];
            UIView *audio = [sib viewWithTag:SCI_STORY_AUDIO_TAG];
            if (seen)  seen.alpha  = alpha;
            if (act)   act.alpha   = alpha;
            if (audio) audio.alpha = alpha;
            return;
        }
        cur = cur.superview;
    }
}

%hook IGStoryFullscreenHeaderView
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    sciSyncStoryButtonsAlpha((UIView *)self, alpha);
}
%end

%end // StoryOverlayGroup

%ctor {
    if ([SCIUtils getBoolPref:@"stories_action_button"] ||
        [SCIUtils getBoolPref:@"story_audio_toggle"] ||
        [SCIUtils getBoolPref:@"no_seen_receipt"]) {
        %init(StoryOverlayGroup);
    }
}
