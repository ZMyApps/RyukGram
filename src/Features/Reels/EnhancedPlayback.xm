#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// When tap control is set to pause/play, these enhancements activate:
// - Mute sub-toggle hidden (only play/pause icon visible)
// - Audio forced on in reels tab
// - Play/pause indicator hidden when video plays (fixes IG bug after hold/zoom)
// - Playback toggle synced with overlay visibility during hold/zoom

static BOOL sciIsPausePlayMode() {
    return [[SCIUtils getStringPref:@"reels_tap_control"] isEqualToString:@"pause"];
}

static BOOL sciIsInReelsTab = NO;
static BOOL sciIsZooming = NO;

// ============ FIND PLAYBACK VIEW ============
// Handles two IG A/B test variants:
// 1. IGSundialPlaybackToggleView wrapper (contains play + mute subviews)
// 2. Standalone IGDSMediaIconButton (no wrapper)

static UIView * _Nullable sciFindPlaybackView(UIView *videoCell) {
    if (!videoCell) return nil;
    Class toggleClass = objc_getClass("IGSundialPlaybackToggle.IGSundialPlaybackToggleView");
    Class iconBtnClass = NSClassFromString(@"IGDSMediaIconButton");
    UIView *fallbackIconBtn = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:videoCell];
    for (int d = 0; d < 6; d++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in stack) {
            for (UIView *sub in v.subviews) {
                if (toggleClass && [sub isKindOfClass:toggleClass]) return sub;
                if (iconBtnClass && [sub isKindOfClass:iconBtnClass] &&
                    sub.frame.size.width > 50 && sub.frame.size.height > 50 &&
                    !sub.hidden && sub.frame.origin.x > 100) {
                    fallbackIconBtn = sub;
                }
                [next addObject:sub];
            }
        }
        stack = next;
    }
    return fallbackIconBtn;
}

// ============ KVO: SYNC PLAYBACK VIEW WITH OVERLAY ============
// IG animates the overlay container via Core Animation during hold/zoom.
// The download button (tag 1337) is inside the container so it hides automatically.
// The playback toggle is in a separate view branch — we KVO the download
// button's layer.opacity and sync the toggle to match.

@interface SCIOpacityObserver : NSObject
@end

@implementation SCIOpacityObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"opacity"]) return;
    CGFloat opacity = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
    CALayer *layer = (CALayer *)object;
    UIView *dlBtn = (layer.delegate && [layer.delegate isKindOfClass:[UIView class]]) ? (UIView *)layer.delegate : nil;
    if (!dlBtn) return;
    UIView *videoCell = dlBtn.superview;
    while (videoCell && ![NSStringFromClass([videoCell class]) containsString:@"VideoCell"])
        videoCell = videoCell.superview;
    UIView *playView = sciFindPlaybackView(videoCell);
    // Skip during zoom — zoom callbacks handle the play button directly
    if (sciIsZooming) return;
    if (playView) playView.layer.opacity = opacity;
}
@end

static SCIOpacityObserver *sciObserver = nil;
static NSHashTable *sciObservedLayers = nil;

static void sciSetupKVO(UIView *ufi) {
    UIView *parent = ufi.superview;
    if (!parent) return;
    UIView *dlBtn = [parent viewWithTag:1337];
    if (!dlBtn) return;
    if (!sciObserver) sciObserver = [[SCIOpacityObserver alloc] init];
    if (!sciObservedLayers) sciObservedLayers = [NSHashTable weakObjectsHashTable];
    if ([sciObservedLayers containsObject:dlBtn.layer]) return;
    [dlBtn.layer addObserver:sciObserver forKeyPath:@"opacity"
                     options:NSKeyValueObservingOptionNew context:NULL];
    [sciObservedLayers addObject:dlBtn.layer];
}

// ============ HIDE PLAY INDICATOR ON PLAY + ZOOM ============

// Use hidden for play/unpause (IG controls unhiding on next pause).
// Use layer.opacity for zoom/KVO (we control restore).
static void sciHidePlayView(id cell) {
    UIView *playView = sciFindPlaybackView(cell);
    if (playView) playView.hidden = YES;
    Ivar ivar = class_getInstanceVariable([cell class], "_playPauseMediaIndicator");
    if (ivar) {
        UIView *indicator = object_getIvar(cell, ivar);
        if (indicator) indicator.hidden = YES;
    }
}

static void sciSetPlayViewOpacity(id cell, CGFloat opacity) {
    UIView *playView = sciFindPlaybackView(cell);
    if (playView) playView.layer.opacity = opacity;
    Ivar ivar = class_getInstanceVariable([cell class], "_playPauseMediaIndicator");
    if (ivar) {
        UIView *indicator = object_getIvar(cell, ivar);
        if (indicator) indicator.layer.opacity = opacity;
    }
}

// Swallow IG's "no sound" toast and remember the media so we don't retry it.
static NSString * const SCINoSoundToastText = @"This reel has no sound.";
static BOOL sciSuppressNoSoundToast = NO;
static BOOL sciSawNoSoundDuringUnmute = NO;
static NSMutableSet<NSString *> *sciNoAudioMediaIds = nil;

static NSString *sciMediaIdFor(id media) {
    if (!media) return nil;
    for (NSString *k in @[@"pk", @"mediaPk", @"mediaID", @"mpk"]) {
        @try {
            id v = [media valueForKey:k];
            if (v) return [NSString stringWithFormat:@"%@", v];
        } @catch (__unused id e) {}
    }
    return nil;
}

static void sciForceUnmuteCell(id videoCell) {
    if (!videoCell) return;
    Ivar delegateIvar = class_getInstanceVariable([videoCell class], "_delegate");
    if (!delegateIvar) return;
    id sectionCtrl = object_getIvar(videoCell, delegateIvar);
    if (!sectionCtrl) return;

    Ivar mediaIvar = class_getInstanceVariable([sectionCtrl class], "_media");
    id media = mediaIvar ? object_getIvar(sectionCtrl, mediaIvar) : nil;
    NSString *mediaId = sciMediaIdFor(media);
    if (mediaId && [sciNoAudioMediaIds containsObject:mediaId]) return;

    SEL isAudioSel = NSSelectorFromString(@"isAudioEnabled");
    if (![sectionCtrl respondsToSelector:isAudioSel]) return;
    BOOL audioOn = ((BOOL(*)(id,SEL))objc_msgSend)(sectionCtrl, isAudioSel);
    if (audioOn) return;

    SEL tapSel = NSSelectorFromString(@"_didTapSoundButton");
    if (![sectionCtrl respondsToSelector:tapSel]) return;

    sciSuppressNoSoundToast = YES;
    sciSawNoSoundDuringUnmute = NO;
    ((void(*)(id,SEL))objc_msgSend)(sectionCtrl, tapSel);
    sciSuppressNoSoundToast = NO;

    if (sciSawNoSoundDuringUnmute && mediaId) {
        if (!sciNoAudioMediaIds) sciNoAudioMediaIds = [NSMutableSet new];
        [sciNoAudioMediaIds addObject:mediaId];
    }
}

%group ReelsPauseModeGroup

%hook IGSundialViewerVideoCell
// hidden=YES on play; IG resets it on the next pause.
- (void)sundialVideoPlaybackViewDidStartPlaying:(id)view {
    %orig;
    if (sciIsPausePlayMode()) {
        sciHidePlayView(self);
        if (sciIsInReelsTab) sciForceUnmuteCell(self);
    }
}

- (void)videoViewDidUnpause:(id)view {
    %orig;
    if (sciIsPausePlayMode()) sciHidePlayView(self);
}

// Zoom — use layer.opacity (we restore it ourselves on zoom end)
- (void)sundialVideoPlaybackView:(id)pbView willBeginZoomInteractionForView:(id)view withLogging:(id)logging {
    %orig;
    sciIsZooming = YES;
    if (sciIsPausePlayMode()) sciSetPlayViewOpacity(self, 0);
}

- (void)sundialVideoPlaybackView:(id)pbView didEndZoomInteractionForView:(id)view withLogging:(id)logging minScale:(CGFloat)minScale {
    %orig;
    sciIsZooming = NO;
    if (sciIsPausePlayMode()) {
        sciSetPlayViewOpacity(self, 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL playing = [self respondsToSelector:@selector(isPlaying)] ?
                ((BOOL(*)(id,SEL))objc_msgSend)(self, @selector(isPlaying)) : NO;
            if (playing) sciHidePlayView(self);
        });
    }
}
%end

// ============ PHOTO REELS: TAP-TO-MUTE ============
// Skip IG's single-tap delegate on photo cells and drive the mute via the
// same hardware-switch notification StoryAudioToggle uses.

extern "C" void sciToggleStoryAudio(void);

static BOOL sciIsPhotoMuteEnabled(void) {
    return sciIsPausePlayMode() && [SCIUtils getBoolPref:@"reels_photo_tap_mute"];
}

%hook IGSundialViewerPhotoCell
- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
    if (sciIsPhotoMuteEnabled()) { sciToggleStoryAudio(); return; }
    %orig;
}
%end

%hook IGSundialViewerCarouselPhotoCell
- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
    if (sciIsPhotoMuteEnabled()) { sciToggleStoryAudio(); return; }
    %orig;
}
%end

// Carousels route the tap through the outer cell, so hijack there too —
// but only when the visible page is a photo. Video pages keep %orig.
%hook IGSundialViewerCarouselCell
- (void)gestureController:(id)gc didObserveSingleTap:(id)tap {
    if (!sciIsPhotoMuteEnabled()) { %orig; return; }
    BOOL hasVideo = NO, hasPhoto = NO;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:self];
    for (int d = 0; d < 6 && stack.count && !hasVideo; d++) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *sub in stack) {
            NSString *cls = NSStringFromClass([sub class]);
            if ([cls isEqualToString:@"IGSundialViewerCarouselVideoCell"]) {
                if (!CGRectIsEmpty(CGRectIntersection(sub.bounds, self.bounds)) &&
                    sub.window) hasVideo = YES;
            } else if ([cls isEqualToString:@"IGSundialViewerCarouselPhotoCell"]) {
                if (!CGRectIsEmpty(CGRectIntersection(sub.bounds, self.bounds)) &&
                    sub.window) hasPhoto = YES;
            }
            for (UIView *s in sub.subviews) [next addObject:s];
        }
        stack = next;
    }
    if (hasPhoto && !hasVideo) { sciToggleStoryAudio(); return; }
    %orig;
}
%end

// ============ UFI: SYNC DOWNLOAD BUTTON + SETUP KVO ============

%hook IGSundialViewerVerticalUFI
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    UIView *parent = self.superview;
    if (!parent) return;
    UIView *dlBtn = [parent viewWithTag:1337];
    if (dlBtn) dlBtn.alpha = alpha;
    sciSetupKVO(self);
}
%end

// ============ HIDE MUTE SUBVIEW IN PLAYBACK TOGGLE ============
// When pause/play mode is active, hide the mute sub-toggle (top subview)
// and keep only the play/pause button visible.

static void (*orig_playbackToggle_didMoveToSuperview)(id self, SEL _cmd);
static void (*orig_playbackToggle_layoutSubviews)(id self, SEL _cmd);

static void sciHideMuteSubview(UIView *toggleView) {
    if (!sciIsPausePlayMode()) {
        for (UIView *sub in toggleView.subviews) {
            if (sub.tag == 9999) {
                sub.hidden = NO; sub.alpha = 1; sub.userInteractionEnabled = YES; sub.tag = 0;
            }
        }
        return;
    }
    NSArray *subs = toggleView.subviews;
    if (subs.count < 2) return;
    UIView *topView = nil;
    CGFloat minY = CGFLOAT_MAX;
    int visibleCount = 0;
    for (UIView *sub in subs) {
        if (sub.frame.size.width < 1 || sub.frame.size.height < 1) continue;
        visibleCount++;
        if (sub.frame.origin.y < minY) { minY = sub.frame.origin.y; topView = sub; }
    }
    if (topView && visibleCount >= 2) {
        topView.hidden = YES; topView.alpha = 0; topView.userInteractionEnabled = NO; topView.tag = 9999;
    }
}

static void new_playbackToggle_didMoveToSuperview(id self, SEL _cmd) {
    orig_playbackToggle_didMoveToSuperview(self, _cmd);
    sciHideMuteSubview((UIView *)self);
}
static void new_playbackToggle_layoutSubviews(id self, SEL _cmd) {
    orig_playbackToggle_layoutSubviews(self, _cmd);
    sciHideMuteSubview((UIView *)self);
}

// ============ FORCE AUDIO IN REELS TAB ============

%hook IGSundialFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciIsInReelsTab = YES;
    // Retry-until-ready: the first reel's cell may not be wired up yet.
    if (sciIsPausePlayMode()) {
        id feedVC = self;
        for (int i = 0; i < 10; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.1 + i * 0.15) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!sciIsInReelsTab) return;
                SEL sel = NSSelectorFromString(@"_currentAudioCell");
                if (![feedVC respondsToSelector:sel]) return;
                id cell = ((id(*)(id,SEL))objc_msgSend)(feedVC, sel);
                if (cell) sciForceUnmuteCell(cell);
            });
        }
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sciIsInReelsTab = NO;
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    %orig;
    if (sciIsPausePlayMode() && sciIsInReelsTab) {
        SEL sel = NSSelectorFromString(@"_currentAudioCell");
        if ([self respondsToSelector:sel]) {
            id cell = ((id(*)(id,SEL))objc_msgSend)(self, sel);
            if (cell) sciForceUnmuteCell(cell);
        }
    }
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    if (sciSuppressNoSoundToast && [text isEqualToString:SCINoSoundToastText]) {
        sciSawNoSoundDuringUnmute = YES;
        %orig(@"");
        self.hidden = YES;
        // Container view is attached to a window after we return — detach the
        // topmost non-window ancestor on the next tick to remove the outline.
        __weak UILabel *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *s = weakSelf;
            if (!s) return;
            UIView *top = s;
            while (top.superview && ![top.superview isKindOfClass:[UIWindow class]]) {
                top = top.superview;
            }
            [top removeFromSuperview];
        });
        return;
    }
    %orig;
}
%end

%end // ReelsPauseModeGroup

// ============ RUNTIME HOOKS ============

%ctor {
    if (![[SCIUtils getStringPref:@"reels_tap_control"] isEqualToString:@"pause"]) return;

    %init(ReelsPauseModeGroup);

    Class toggleClass = objc_getClass("IGSundialPlaybackToggle.IGSundialPlaybackToggleView");
    if (toggleClass) {
        MSHookMessageEx(toggleClass, @selector(didMoveToSuperview),
                        (IMP)new_playbackToggle_didMoveToSuperview, (IMP *)&orig_playbackToggle_didMoveToSuperview);
        MSHookMessageEx(toggleClass, @selector(layoutSubviews),
                        (IMP)new_playbackToggle_layoutSubviews, (IMP *)&orig_playbackToggle_layoutSubviews);
    }
}
