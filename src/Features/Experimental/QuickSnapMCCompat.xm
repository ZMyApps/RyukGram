// MobileConfig override for any ig_boolForKey: naming QuickSnap. Gate: igt_quicksnap.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static inline BOOL keyMatchesQuickSnap(id key) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    NSString *s = ((NSString *)key).lowercaseString;
    return [s containsString:@"quicksnap"]  ||
           [s containsString:@"quick_snap"] ||
           [s containsString:@"instants"]   ||
           [s containsString:@"xma_quicksnap"];
}

static BOOL (*orig_bool_key)(id, SEL, id) = NULL;
static BOOL new_bool_key(id self, SEL _cmd, id key) {
    if (keyMatchesQuickSnap(key)) return YES;
    return orig_bool_key ? orig_bool_key(self, _cmd, key) : NO;
}

static BOOL (*orig_bool_key_def)(id, SEL, id, BOOL) = NULL;
static BOOL new_bool_key_def(id self, SEL _cmd, id key, BOOL def) {
    if (keyMatchesQuickSnap(key)) return YES;
    return orig_bool_key_def ? orig_bool_key_def(self, _cmd, key, def) : def;
}

static void hookInstance(NSString *cn, NSString *sn, IMP impl, IMP *orig) {
    Class cls = NSClassFromString(cn);
    if (!cls) return;
    SEL sel = NSSelectorFromString(sn);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, impl, orig);
}

%ctor {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return;

    hookInstance(@"IGMobileConfigContextManager",            @"ig_boolForKey:",              (IMP)new_bool_key,     (IMP *)&orig_bool_key);
    hookInstance(@"IGMobileConfigContextManager",            @"ig_boolForKey:defaultValue:", (IMP)new_bool_key_def, (IMP *)&orig_bool_key_def);
    hookInstance(@"IGMobileConfigUserSessionContextManager", @"ig_boolForKey:",              (IMP)new_bool_key,     (IMP *)&orig_bool_key);
    hookInstance(@"IGMobileConfigUserSessionContextManager", @"ig_boolForKey:defaultValue:", (IMP)new_bool_key_def, (IMP *)&orig_bool_key_def);
}
