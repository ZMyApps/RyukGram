#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// IGFeedPlayback.IGFeedPlaybackStrategy has a Swift-mangled name. Both init
// variants force shouldDisableAutoplay=YES when the pref is on.

static id (*orig_feedInit2)(id, SEL, BOOL, BOOL);
static id new_feedInit2(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale) {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) shouldDisable = YES;
    return orig_feedInit2(self, _cmd, shouldDisable, shouldClearStale);
}

static id (*orig_feedInit3)(id, SEL, BOOL, BOOL, BOOL);
static id new_feedInit3(id self, SEL _cmd, BOOL shouldDisable, BOOL shouldClearStale, BOOL bypassForVoiceover) {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) shouldDisable = YES;
    return orig_feedInit3(self, _cmd, shouldDisable, shouldClearStale, bypassForVoiceover);
}

// Carousel tap-to-play. The modern feed video cell receives single-taps via
// this delegate callback, but the Swift implementation skips resume when the
// cell sits inside a carousel. Force retryStartPlayback after orig.
static void (*orig_cellDidSingleTap)(id, SEL, id, id);
static void new_cellDidSingleTap(id self, SEL _cmd, id overlay, id gr) {
    orig_cellDidSingleTap(self, _cmd, overlay, gr);
    if (![SCIUtils getBoolPref:@"disable_feed_autoplay"]) return;
    UIView *sv = [(UIView *)self superview];
    if (!sv || !strstr(class_getName([sv class]), "Carousel")) return;
    if ([self respondsToSelector:@selector(retryStartPlayback)])
        ((void(*)(id, SEL))objc_msgSend)(self, @selector(retryStartPlayback));
}

static void sciHookFeedStrategy(void) {
    Class cls = objc_getClass("IGFeedPlayback.IGFeedPlaybackStrategy");
    if (!cls) return;
    SEL s2 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:);
    if ([cls instancesRespondToSelector:s2])
        MSHookMessageEx(cls, s2, (IMP)new_feedInit2, (IMP *)&orig_feedInit2);
    SEL s3 = @selector(initWithShouldDisableAutoplay:shouldClearStaleReservation:shouldBypassDisabledAutoplayForVoiceover:);
    if ([cls instancesRespondToSelector:s3])
        MSHookMessageEx(cls, s3, (IMP)new_feedInit3, (IMP *)&orig_feedInit3);
}

static void sciHookVideoCell(void) {
    static BOOL hooked = NO;
    if (hooked) return;
    Class cls = objc_getClass("IGModernFeedVideoCell.IGModernFeedVideoCell");
    if (!cls) return;
    SEL s = @selector(videoPlayerOverlayControllerDidSingleTap:gestureRecognizer:);
    if (![cls instancesRespondToSelector:s]) return;
    MSHookMessageEx(cls, s, (IMP)new_cellDidSingleTap, (IMP *)&orig_cellDidSingleTap);
    hooked = YES;
}

%ctor {
    sciHookFeedStrategy();
    sciHookVideoCell();
    // Swift cell class can load after dylib init; retry on main runloop.
    dispatch_async(dispatch_get_main_queue(), ^{ sciHookVideoCell(); });
}
