// Force-enable QuickSnap (Instants) surfaces. Gate: igt_quicksnap.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

#define QS_BOOL1_RETURN_YES(fnName) \
    static BOOL (*orig_##fnName)(id, SEL, id) = NULL; \
    static BOOL new_##fnName(id self, SEL _cmd, id arg) { return YES; }

QS_BOOL1_RETURN_YES(qs_enabled)
QS_BOOL1_RETURN_YES(qs_enabled_feed)
QS_BOOL1_RETURN_YES(qs_enabled_inbox)
QS_BOOL1_RETURN_YES(qs_enabled_stories)
QS_BOOL1_RETURN_YES(qs_enabled_peek)
QS_BOOL1_RETURN_YES(qs_enabled_tray)
QS_BOOL1_RETURN_YES(qs_enabled_tray_peek)
QS_BOOL1_RETURN_YES(qs_enabled_tray_pog)
QS_BOOL1_RETURN_YES(qs_enabled_empty_pog)
QS_BOOL1_RETURN_YES(qs_isqp)

static BOOL (*orig_qs_corner)(id, SEL) = NULL;
static BOOL new_qs_corner(id self, SEL _cmd) { return YES; }
static BOOL (*orig_qs_dialog)(id, SEL) = NULL;
static BOOL new_qs_dialog(id self, SEL _cmd) { return YES; }

static BOOL (*orig_peek)(id, SEL) = NULL;
static BOOL new_peek(id self, SEL _cmd) { return YES; }
static BOOL (*orig_recap)(id, SEL) = NULL;
static BOOL new_recap(id self, SEL _cmd) { return YES; }
static BOOL (*orig__recap)(id, SEL) = NULL;
static BOOL new__recap(id self, SEL _cmd) { return YES; }
static BOOL (*orig_recap_media)(id, SEL) = NULL;
static BOOL new_recap_media(id self, SEL _cmd) { return YES; }
static BOOL (*orig_recap_video)(id, SEL) = NULL;
static BOOL new_recap_video(id self, SEL _cmd) { return YES; }
static BOOL (*orig_hidden)(id, SEL) = NULL;
static BOOL new_hidden(id self, SEL _cmd) { return NO; }
static BOOL (*orig__hidden)(id, SEL) = NULL;
static BOOL new__hidden(id self, SEL _cmd) { return NO; }

static void hookClassMethod(NSString *cn, NSString *sn, IMP impl, IMP *orig) {
    Class cls = NSClassFromString(cn);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(sn);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, impl, orig);
}

static void hookInstance(NSString *cn, NSString *sn, IMP impl, IMP *orig) {
    Class cls = NSClassFromString(cn);
    if (!cls) return;
    SEL sel = NSSelectorFromString(sn);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, impl, orig);
}

static void hookZeroArgAcross(NSArray<NSString *> *classes, NSString *sn, IMP impl, IMP *orig) {
    SEL sel = NSSelectorFromString(sn);
    for (NSString *cn in classes) {
        Class cls = NSClassFromString(cn);
        if (!cls || !class_getInstanceMethod(cls, sel)) continue;
        MSHookMessageEx(cls, sel, impl, orig);
    }
}

%ctor {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return;

    NSString *helper = @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper";
    hookClassMethod(helper, @"isQuicksnapEnabled:",                       (IMP)new_qs_enabled,           (IMP *)&orig_qs_enabled);
    hookClassMethod(helper, @"isQuicksnapEnabledInFeed:",                 (IMP)new_qs_enabled_feed,      (IMP *)&orig_qs_enabled_feed);
    hookClassMethod(helper, @"isQuicksnapEnabledInInbox:",                (IMP)new_qs_enabled_inbox,     (IMP *)&orig_qs_enabled_inbox);
    hookClassMethod(helper, @"isQuicksnapEnabledInStories:",              (IMP)new_qs_enabled_stories,   (IMP *)&orig_qs_enabled_stories);
    hookClassMethod(helper, @"isQuicksnapEnabledInNotesTray:",            (IMP)new_qs_enabled_tray,      (IMP *)&orig_qs_enabled_tray);
    hookClassMethod(helper, @"isQuicksnapEnabledInNotesTrayWithPeek:",    (IMP)new_qs_enabled_tray_peek, (IMP *)&orig_qs_enabled_tray_peek);
    hookClassMethod(helper, @"isQuicksnapEnabledInNotesTrayWithPog:",     (IMP)new_qs_enabled_tray_pog,  (IMP *)&orig_qs_enabled_tray_pog);
    hookClassMethod(helper, @"isQuicksnapNotesTrayEmptyPogEnabled:",      (IMP)new_qs_enabled_empty_pog, (IMP *)&orig_qs_enabled_empty_pog);
    hookClassMethod(helper, @"isQuicksnapEnabledAsPeek:",                 (IMP)new_qs_enabled_peek,      (IMP *)&orig_qs_enabled_peek);

    NSString *tray = @"_TtC21IGNotesTrayController21IGNotesTrayController";
    hookInstance(tray, @"_isEligibleForQuicksnapCornerStackTransitionDialog", (IMP)new_qs_corner, (IMP *)&orig_qs_corner);
    hookInstance(tray, @"_isEligibleForQuicksnapDialog",                     (IMP)new_qs_dialog, (IMP *)&orig_qs_dialog);
    hookInstance(tray, @"isQPEnabled:",                                       (IMP)new_qs_isqp,   (IMP *)&orig_qs_isqp);

    hookInstance(@"IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)new_qs_isqp, NULL);
    hookInstance(@"_TtC24IGDirectNotesTrayUISwift37IGDirectNotesTrayRowSectionController",
                 @"isQPEnabled:", (IMP)new_qs_isqp, NULL);

    NSArray *instantsClasses = @[
        @"IGInstantGestureRecognizer",
        @"IGAPIQuickSnapData",
        @"XDTQuickSnapData",
        @"IGAPIQuicksnapRecapMediaInfo",
        @"XDTQuicksnapRecapMediaInfo",
    ];
    hookZeroArgAcross(instantsClasses, @"isEligibleForPeek",     (IMP)new_peek,         (IMP *)&orig_peek);
    hookZeroArgAcross(instantsClasses, @"isQuicksnapRecap",      (IMP)new_recap,        (IMP *)&orig_recap);
    hookZeroArgAcross(instantsClasses, @"_isQuicksnapRecap",     (IMP)new__recap,       (IMP *)&orig__recap);
    hookZeroArgAcross(instantsClasses, @"hasQuicksnapRecapMedia",(IMP)new_recap_media,  (IMP *)&orig_recap_media);
    hookZeroArgAcross(instantsClasses, @"isInstantsRecapVideo",  (IMP)new_recap_video,  (IMP *)&orig_recap_video);

    NSString *svc = @"_TtC18IGQuickSnapService18IGQuickSnapService";
    hookInstance(svc, @"isHiddenByServer",  (IMP)new_hidden,  (IMP *)&orig_hidden);
    hookInstance(svc, @"_isHiddenByServer", (IMP)new__hidden, (IMP *)&orig__hidden);
}
