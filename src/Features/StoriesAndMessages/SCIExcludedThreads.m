#import "SCIExcludedThreads.h"
#import "../../Utils.h"

#define SCI_EXCL_KEY @"excluded_threads"

@implementation SCIExcludedThreads

static NSString *sciActiveTid = nil;

+ (BOOL)isFeatureEnabled {
    return [SCIUtils getBoolPref:@"enable_chat_exclusions"];
}

+ (NSArray<NSDictionary *> *)allEntries {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:SCI_EXCL_KEY];
    return raw ?: @[];
}

+ (NSUInteger)count {
    return [self allEntries].count;
}

+ (void)saveAll:(NSArray *)entries {
    [[NSUserDefaults standardUserDefaults] setObject:entries forKey:SCI_EXCL_KEY];
}

+ (NSDictionary *)entryForThreadId:(NSString *)threadId {
    if (threadId.length == 0) return nil;
    for (NSDictionary *e in [self allEntries]) {
        if ([e[@"threadId"] isEqualToString:threadId]) return e;
    }
    return nil;
}

+ (BOOL)isThreadIdExcluded:(NSString *)threadId {
    if (![self isFeatureEnabled]) return NO;
    return [self entryForThreadId:threadId] != nil;
}

+ (BOOL)shouldKeepDeletedBeBlockedForThreadId:(NSString *)threadId {
    if (![self isFeatureEnabled]) return NO;
    NSDictionary *e = [self entryForThreadId:threadId];
    if (!e) return NO;
    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    if (mode == SCIKeepDeletedOverrideExcluded) return YES;
    if (mode == SCIKeepDeletedOverrideIncluded) return NO;
    return [SCIUtils getBoolPref:@"exclusions_default_keep_deleted"];
}

+ (void)addOrUpdateEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (tid.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    NSInteger existingIdx = -1;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"threadId"] isEqualToString:tid]) { existingIdx = i; break; }
    }
    NSMutableDictionary *merged = [entry mutableCopy];
    if (existingIdx >= 0) {
        // Preserve existing addedAt + override
        NSDictionary *old = all[existingIdx];
        if (old[@"addedAt"]) merged[@"addedAt"] = old[@"addedAt"];
        if (old[@"keepDeletedOverride"]) merged[@"keepDeletedOverride"] = old[@"keepDeletedOverride"];
        all[existingIdx] = merged;
    } else {
        if (!merged[@"addedAt"]) merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
        if (!merged[@"keepDeletedOverride"]) merged[@"keepDeletedOverride"] = @(SCIKeepDeletedOverrideDefault);
        [all addObject:merged];
    }
    [self saveAll:all];
}

+ (void)removeThreadId:(NSString *)threadId {
    if (threadId.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
        return ![e[@"threadId"] isEqualToString:threadId];
    }]];
    [self saveAll:all];
}

+ (void)setKeepDeletedOverride:(SCIKeepDeletedOverride)mode forThreadId:(NSString *)threadId {
    if (threadId.length == 0) return;
    NSMutableArray *all = [[self allEntries] mutableCopy];
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if ([all[i][@"threadId"] isEqualToString:threadId]) {
            NSMutableDictionary *m = [all[i] mutableCopy];
            m[@"keepDeletedOverride"] = @(mode);
            all[i] = m;
            break;
        }
    }
    [self saveAll:all];
}

+ (void)setActiveThreadId:(NSString *)threadId { sciActiveTid = [threadId copy]; }
+ (NSString *)activeThreadId { return sciActiveTid; }
+ (BOOL)isActiveThreadExcluded { return [self isThreadIdExcluded:sciActiveTid]; }

@end
