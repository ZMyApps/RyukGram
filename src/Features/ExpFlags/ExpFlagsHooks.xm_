// Hooks installed iff sci_exp_flags_enabled.
// Override: MetaLocalExperiment group{,Peek}Name — substring-match _experimentName, return "test"/nil.
// View-only: IGMobileConfigContextManager get{Bool,Int64,Double,String}[:withDefault:] — record, no override.

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// MetaLocalExperiment

static NSString *experimentNameOf(id obj) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static id overrideGroupFor(NSString *expName, id origGroup) {
    if (!expName.length) return origGroup;
    NSString *lower = expName.lowercaseString;
    for (NSString *key in [SCIExpFlags allOverriddenNames]) {
        if (![lower containsString:key.lowercaseString]) continue;
        SCIExpFlagOverride o = [SCIExpFlags overrideForName:key];
        if (o == SCIExpFlagOverrideTrue)  return @"test";
        if (o == SCIExpFlagOverrideFalse) return nil;
    }
    return origGroup;
}

static id (*orig_groupName)(id, SEL);
static id new_groupName(id self, SEL _cmd) {
    id orig = orig_groupName ? orig_groupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

static id (*orig_peekGroupName)(id, SEL);
static id new_peekGroupName(id self, SEL _cmd) {
    id orig = orig_peekGroupName ? orig_peekGroupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

// IGMobileConfigContextManager — view-only.
// param arg is {uint64} struct, ABI-identical to unsigned long long on arm64.

static BOOL (*orig_mcBool)(id, SEL, unsigned long long);
static BOOL new_mcBool(id self, SEL _cmd, unsigned long long pid) {
    BOOL v = orig_mcBool(self, _cmd, pid);
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeBool defaultValue:v ? @"YES" : @"NO"];
    return v;
}
static BOOL (*orig_mcBool_def)(id, SEL, unsigned long long, BOOL);
static BOOL new_mcBool_def(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeBool defaultValue:def ? @"YES" : @"NO"];
    return orig_mcBool_def(self, _cmd, pid, def);
}
static long long (*orig_mcInt)(id, SEL, unsigned long long);
static long long new_mcInt(id self, SEL _cmd, unsigned long long pid) {
    long long v = orig_mcInt(self, _cmd, pid);
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeInt defaultValue:[NSString stringWithFormat:@"%lld", v]];
    return v;
}
static long long (*orig_mcInt_def)(id, SEL, unsigned long long, long long);
static long long new_mcInt_def(id self, SEL _cmd, unsigned long long pid, long long def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeInt defaultValue:[NSString stringWithFormat:@"%lld", def]];
    return orig_mcInt_def(self, _cmd, pid, def);
}
static double (*orig_mcDouble)(id, SEL, unsigned long long);
static double new_mcDouble(id self, SEL _cmd, unsigned long long pid) {
    double v = orig_mcDouble(self, _cmd, pid);
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeDouble defaultValue:[NSString stringWithFormat:@"%f", v]];
    return v;
}
static double (*orig_mcDouble_def)(id, SEL, unsigned long long, double);
static double new_mcDouble_def(id self, SEL _cmd, unsigned long long pid, double def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeDouble defaultValue:[NSString stringWithFormat:@"%f", def]];
    return orig_mcDouble_def(self, _cmd, pid, def);
}
static id (*orig_mcString)(id, SEL, unsigned long long);
static id new_mcString(id self, SEL _cmd, unsigned long long pid) {
    id v = orig_mcString(self, _cmd, pid);
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeString defaultValue:[v description] ?: @""];
    return v;
}
static id (*orig_mcString_def)(id, SEL, unsigned long long, id);
static id new_mcString_def(id self, SEL _cmd, unsigned long long pid, id def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeString defaultValue:[def description] ?: @""];
    return orig_mcString_def(self, _cmd, pid, def);
}

// install

static void install(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

%ctor {
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"]) return;

    if ([SCIExpFlags checkAndHandleCrashLoop]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [SCIUtils showToastForDuration:4.0 title:@"Exp flags reset after repeated crashes"];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [SCIExpFlags markLaunchStable]; });

    // Family inherits Meta — one install covers both
    Class meta = NSClassFromString(@"MetaLocalExperiment");
    install(meta, @"groupName",     (IMP)new_groupName,     (IMP *)&orig_groupName);
    install(meta, @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);

    Class mc = NSClassFromString(@"IGMobileConfigContextManager");
    install(mc, @"getBool:",               (IMP)new_mcBool,       (IMP *)&orig_mcBool);
    install(mc, @"getBool:withDefault:",   (IMP)new_mcBool_def,   (IMP *)&orig_mcBool_def);
    install(mc, @"getInt64:",              (IMP)new_mcInt,        (IMP *)&orig_mcInt);
    install(mc, @"getInt64:withDefault:",  (IMP)new_mcInt_def,    (IMP *)&orig_mcInt_def);
    install(mc, @"getDouble:",             (IMP)new_mcDouble,     (IMP *)&orig_mcDouble);
    install(mc, @"getDouble:withDefault:", (IMP)new_mcDouble_def, (IMP *)&orig_mcDouble_def);
    install(mc, @"getString:",             (IMP)new_mcString,     (IMP *)&orig_mcString);
    install(mc, @"getString:withDefault:", (IMP)new_mcString_def, (IMP *)&orig_mcString_def);
}
