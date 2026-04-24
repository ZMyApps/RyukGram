// Story audio mute/unmute toggle.
// Flips IGAudioStatusAnnouncer private state then fans out to listeners
// via the two IGUltralightAnnouncer sub-forwarders (426 dropped the old
// mute-switch notification).

#import <AVFoundation/AVFoundation.h>
#import "StoryHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

extern "C" __weak UIViewController *sciActiveStoryViewerVC;
extern "C" void sciRefreshAllVisibleOverlays(UIViewController *);

static id sciAudioAnnouncer = nil;

static id sciReadIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    return object_getIvar(obj, iv);
}

static BOOL sciIGAudioEnabled(void) {
    if (!sciAudioAnnouncer) return NO;
    SEL s = NSSelectorFromString(@"isAudioEnabledForSoundBehavior:");
    if ([sciAudioAnnouncer respondsToSelector:s]) {
        typedef BOOL (*Fn)(id, SEL, NSInteger);
        return ((Fn)objc_msgSend)(sciAudioAnnouncer, s, 1);
    }
    Ivar ivar = class_getInstanceVariable([sciAudioAnnouncer class], "_audioEnabled");
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    return *(BOOL *)((char *)(__bridge void *)sciAudioAnnouncer + offset);
}

static void sciWriteAudioEnabled(BOOL value) {
    if (!sciAudioAnnouncer) return;
    Ivar ivar = class_getInstanceVariable([sciAudioAnnouncer class], "_audioEnabled");
    if (!ivar) return;
    ptrdiff_t offset = ivar_getOffset(ivar);
    *(BOOL *)((char *)(__bridge void *)sciAudioAnnouncer + offset) = value;
}

// ============ Volume KVO ============

@interface _SciVolumeObserver : NSObject
@end
@implementation _SciVolumeObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sciActiveStoryViewerVC) sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
    });
}
@end
static _SciVolumeObserver *sciVolumeObserver = nil;

// ============ Public API ============

extern "C" {

BOOL sciStoryAudioBypass = NO;

void sciToggleStoryAudio(void) {
    if (!sciAudioAnnouncer) return;

    BOOL on = sciIGAudioEnabled();
    BOOL wanted = !on;
    sciStoryAudioBypass = YES;

    sciWriteAudioEnabled(wanted);

    // 2 = user-enabled, 1 = user-disabled.
    Ivar stickIv = class_getInstanceVariable([sciAudioAnnouncer class], "_stickySoundState");
    if (stickIv) {
        ptrdiff_t off = ivar_getOffset(stickIv);
        NSInteger *p = (NSInteger *)((char *)(__bridge void *)sciAudioAnnouncer + off);
        *p = wanted ? 2 : 1;
    }

    SEL notify = NSSelectorFromString(@"audioStatusDidChangeIsAudioEnabled:forReason:");
    typedef void (*NotifyFn)(id, SEL, BOOL, NSInteger);
    id subA = sciReadIvar(sciAudioAnnouncer, "_announcerForDefaultBehaviors");
    id subB = sciReadIvar(sciAudioAnnouncer, "_announcerForIgnoreUserPreferenceAndMatchDeviceState");
    if (subA) ((NotifyFn)objc_msgSend)(subA, notify, wanted, 0);
    if (subB) ((NotifyFn)objc_msgSend)(subB, notify, wanted, 0);

    sciStoryAudioBypass = NO;
    if (sciActiveStoryViewerVC) sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
}

BOOL sciIsStoryAudioEnabled(void) {
    return sciIGAudioEnabled();
}

static BOOL sciKVORegistered = NO;

void sciInitStoryAudioState(void) {
    if (sciKVORegistered) return;
    if (!sciVolumeObserver) sciVolumeObserver = [_SciVolumeObserver new];
    @try {
        [[AVAudioSession sharedInstance] addObserver:sciVolumeObserver
                                         forKeyPath:@"outputVolume"
                                            options:NSKeyValueObservingOptionNew
                                            context:NULL];
        sciKVORegistered = YES;
    } @catch (__unused id e) {}
}

void sciResetStoryAudioState(void) {
    if (!sciKVORegistered) return;
    @try {
        [[AVAudioSession sharedInstance] removeObserver:sciVolumeObserver forKeyPath:@"outputVolume"];
        sciKVORegistered = NO;
    } @catch (__unused id e) {}
}

} // extern "C"

// ============ Announcer hooks ============

static id (*orig_announcerInit)(id, SEL);
static id new_announcerInit(id self, SEL _cmd) {
    id r = orig_announcerInit(self, _cmd);
    sciAudioAnnouncer = self;
    return r;
}

static void (*orig_announce)(id, SEL, BOOL, NSInteger);
static void new_announce(id self, SEL _cmd, BOOL enabled, NSInteger reason) {
    orig_announce(self, _cmd, enabled, reason);
    if (sciActiveStoryViewerVC) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sciActiveStoryViewerVC) sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
        });
    }
}

// ============ 3-dot menu item ============

extern "C" NSArray *sciMaybeAppendStoryAudioMenuItem(NSArray *items) {
    if (!sciActiveStoryViewerVC) return items;

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

    BOOL on = sciIGAudioEnabled();
    NSString *title = on ? SCILocalized(@"Mute story audio") : SCILocalized(@"Unmute story audio");
    void (^handler)(void) = ^{ sciToggleStoryAudio(); };

    id newItem = nil;
    @try {
        typedef id (*Init)(id, SEL, id, id, id);
        newItem = ((Init)objc_msgSend)([menuItemCls alloc],
            @selector(initWithTitle:image:handler:), title, nil, handler);
    } @catch (__unused id e) {}

    if (!newItem) return items;
    NSMutableArray *newItems = [items mutableCopy];
    [newItems addObject:newItem];
    return [newItems copy];
}

// ============ Ringer listener ============

static void sciRingerChanged(CFNotificationCenterRef center, void *observer,
                              CFNotificationName name, const void *object,
                              CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sciActiveStoryViewerVC) sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
    });
}

// ============ Init ============

__attribute__((constructor)) static void _storyAudioInit(void) {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        sciRingerChanged, CFSTR("com.apple.springboard.ringerstate"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    Class cls = NSClassFromString(@"IGAudioStatusAnnouncer");
    if (!cls) return;
    MSHookMessageEx(cls, @selector(init), (IMP)new_announcerInit, (IMP *)&orig_announcerInit);
    SEL s = NSSelectorFromString(@"_announceForDeviceStateChangesIfNeededForAudioEnabled:reason:");
    if (class_getInstanceMethod(cls, s))
        MSHookMessageEx(cls, s, (IMP)new_announce, (IMP *)&orig_announce);
}
