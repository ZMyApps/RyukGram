// Hide suggested stories from the feed tray. The adapter hook is shared
// with profile highlights, so we key off diffIdentifier: only suggested
// items use a 32-char hex UUID (real users use numeric PKs, highlights use
// "highlight:<pk>"). Default-keep on anything ambiguous.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL sciIsHexUUIDString(NSString *s) {
    if (s.length != 32) return NO;
    static NSCharacterSet *nonHex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    });
    return [s rangeOfCharacterFromSet:nonHex].location == NSNotFound;
}

static BOOL sciIsSuggestedTrayItem(id obj) {
    @try {
        if (![NSStringFromClass([obj class]) isEqualToString:@"IGStoryTrayViewModel"]) return NO;
        if ([[obj valueForKey:@"isCurrentUserReel"] boolValue]) return NO;

        NSString *diffId = nil;
        @try { diffId = [[obj performSelector:@selector(diffIdentifier)] description]; } @catch (...) {}
        if (!sciIsHexUUIDString(diffId)) return NO;

        id owner = [obj valueForKey:@"reelOwner"];
        if (!owner) return NO;
        Ivar userIvar = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!userIvar) return NO;
        id igUser = object_getIvar(owner, userIvar);
        if (!igUser) return NO;

        Ivar fcIvar = NULL;
        for (Class c = [igUser class]; c && !fcIvar; c = class_getSuperclass(c))
            fcIvar = class_getInstanceVariable(c, "_fieldCache");
        if (!fcIvar) return NO;
        id fc = object_getIvar(igUser, fcIvar);
        if (![fc isKindOfClass:[NSDictionary class]]) return NO;

        id fs = [(NSDictionary *)fc objectForKey:@"friendship_status"];
        if (!fs) return NO;
        return ![[fs valueForKey:@"following"] boolValue];
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static NSArray *(*orig_objectsForListAdapter)(id, SEL, id);
static NSArray *hook_objectsForListAdapter(id self, SEL _cmd, id adapter) {
    NSArray *objects = orig_objectsForListAdapter(self, _cmd, adapter);
    if (![SCIUtils getBoolPref:@"hide_suggested_stories"]) return objects;

    BOOL anySuggested = NO;
    for (id obj in objects) {
        if (sciIsSuggestedTrayItem(obj)) { anySuggested = YES; break; }
    }
    if (!anySuggested) return objects;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:objects.count];
    for (id obj in objects) {
        if (!sciIsSuggestedTrayItem(obj)) [filtered addObject:obj];
    }
    return [filtered copy];
}

%ctor {
    Class cls = NSClassFromString(@"IGStoryTrayListAdapterDataSource");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"objectsForListAdapter:");
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, (IMP)hook_objectsForListAdapter, (IMP *)&orig_objectsForListAdapter);
}
