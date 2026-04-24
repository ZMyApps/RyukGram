// Experiment-name substring override. Gates: igt_quicksnap, igt_directnotes_friendmap, igt_prism.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static inline BOOL containsAny(NSString *s, NSArray<NSString *> *needles) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return NO;
    NSString *lower = s.lowercaseString;
    for (NSString *n in needles) if ([lower containsString:n]) return YES;
    return NO;
}

static BOOL matchQuickSnap(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return NO;
    return containsAny(name, @[@"quicksnap", @"quick_snap", @"instants", @"xma_quicksnap",
                               @"_ig_ios_quicksnap_", @"_ig_ios_quick_snap_", @"_ig_ios_instants_"]);
}

static BOOL matchFriendMap(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_directnotes_friendmap"]) return NO;
    return containsAny(name, @[@"friendmap", @"friends_map", @"direct_notes",
                               @"ig_direct_notes_ios", @"_ig_ios_friendmap_", @"_ig_ios_friends_map_"]);
}

static BOOL matchPrism(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_prism"]) return NO;
    return containsAny(name, @[@"prism"]);
}

static inline BOOL shouldForceOn(NSString *name) {
    return matchQuickSnap(name) || matchFriendMap(name) || matchPrism(name);
}

static NSString *expNameOf(id obj) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), "_experimentGroupName");
    if (!iv) iv = class_getInstanceVariable(object_getClass(obj), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static BOOL (*orig_meta_isIn)(id, SEL) = NULL;
static BOOL new_meta_isIn(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return YES;
    return orig_meta_isIn ? orig_meta_isIn(self, _cmd) : NO;
}

static BOOL (*orig_family_isIn)(id, SEL) = NULL;
static BOOL new_family_isIn(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return YES;
    return orig_family_isIn ? orig_family_isIn(self, _cmd) : NO;
}

static BOOL (*orig_lid_enabled)(id, SEL, NSString *) = NULL;
static BOOL new_lid_enabled(id self, SEL _cmd, NSString *name) {
    if (shouldForceOn(name)) return YES;
    return orig_lid_enabled ? orig_lid_enabled(self, _cmd, name) : NO;
}

static id (*orig_groupName)(id, SEL) = NULL;
static id new_groupName(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return @"test";
    return orig_groupName ? orig_groupName(self, _cmd) : nil;
}

static id (*orig_peekGroup)(id, SEL) = NULL;
static id new_peekGroup(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return @"test";
    return orig_peekGroup ? orig_peekGroup(self, _cmd) : nil;
}

static void hook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

%ctor {
    if (!([SCIUtils getBoolPref:@"igt_quicksnap"] ||
          [SCIUtils getBoolPref:@"igt_directnotes_friendmap"] ||
          [SCIUtils getBoolPref:@"igt_prism"])) return;

    Class meta = NSClassFromString(@"MetaLocalExperiment");
    hook(meta, @"isInExperiment", (IMP)new_meta_isIn,   (IMP *)&orig_meta_isIn);
    hook(meta, @"groupName",      (IMP)new_groupName,   (IMP *)&orig_groupName);
    hook(meta, @"peekGroupName",  (IMP)new_peekGroup,   (IMP *)&orig_peekGroup);
    hook(NSClassFromString(@"FamilyLocalExperiment"), @"isInExperiment",
         (IMP)new_family_isIn, (IMP *)&orig_family_isIn);
    hook(NSClassFromString(@"LIDExperimentGenerator"), @"isExperimentEnabled:",
         (IMP)new_lid_enabled, (IMP *)&orig_lid_enabled);
}
