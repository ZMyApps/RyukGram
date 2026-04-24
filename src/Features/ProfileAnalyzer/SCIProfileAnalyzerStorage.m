#import "SCIProfileAnalyzerStorage.h"

NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification = @"SCIProfileAnalyzerDataDidChangeNotification";

@implementation SCIProfileAnalyzerStorage

static NSString *const kSCIPAStorageDir = @"RyukGram/ProfileAnalyzer";

static void sciPostDataChanged(NSString *userPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIProfileAnalyzerDataDidChangeNotification
                                                             object:nil
                                                           userInfo:userPK.length ? @{ @"user_pk": userPK } : @{}];
    });
}

static NSString *sciStorageDir(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = [roots.firstObject stringByAppendingPathComponent:kSCIPAStorageDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciPath(NSString *userPK, NSString *slot) {
    NSString *safePK = userPK.length ? userPK : @"anon";
    return [sciStorageDir() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.%@.json", safePK, slot]];
}

static NSDictionary *sciReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL sciWriteJSON(NSString *path, NSDictionary *dict) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&err];
    if (!data) return NO;
    return [data writeToFile:path atomically:YES];
}

+ (SCIProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"current"))];
}

+ (SCIProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"previous"))];
}

+ (SCIProfileAnalyzerSnapshot *)baselineSnapshotForUserPK:(NSString *)userPK {
    return [SCIProfileAnalyzerSnapshot snapshotFromJSONDict:sciReadJSON(sciPath(userPK, @"baseline"))];
}

+ (BOOL)saveBaselineSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    BOOL ok = sciWriteJSON(sciPath(userPK, @"baseline"), [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (void)clearBaselineForUserPK:(NSString *)userPK {
    [[NSFileManager defaultManager] removeItemAtPath:sciPath(userPK, @"baseline") error:nil];
    sciPostDataChanged(userPK);
}

+ (BOOL)saveSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    NSString *cur = sciPath(userPK, @"current");
    NSString *prev = sciPath(userPK, @"previous");
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:cur]) {
        [fm removeItemAtPath:prev error:nil];
        [fm moveItemAtPath:cur toPath:prev error:nil];
    }
    BOOL ok = sciWriteJSON(cur, [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (BOOL)updateCurrentSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot) return NO;
    BOOL ok = sciWriteJSON(sciPath(userPK, @"current"), [snapshot toJSONDict]);
    if (ok) sciPostDataChanged(userPK);
    return ok;
}

+ (void)resetForUserPK:(NSString *)userPK {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:sciPath(userPK, @"current") error:nil];
    [fm removeItemAtPath:sciPath(userPK, @"previous") error:nil];
    [fm removeItemAtPath:sciPath(userPK, @"baseline") error:nil];
    sciPostDataChanged(userPK);
}

+ (void)resetAll {
    [[NSFileManager defaultManager] removeItemAtPath:sciStorageDir() error:nil];
    sciPostDataChanged(nil);
}

+ (NSDictionary *)headerInfoForUserPK:(NSString *)userPK {
    return sciReadJSON(sciPath(userPK, @"header"));
}

+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK {
    if (!info.count) return;
    NSMutableDictionary *stored = [info mutableCopy];
    stored[@"cached_at"] = @([[NSDate date] timeIntervalSince1970]);
    sciWriteJSON(sciPath(userPK, @"header"), stored);
}

+ (NSDictionary *)exportedDict {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:sciStorageDir() error:nil]) {
        NSDictionary *d = sciReadJSON([sciStorageDir() stringByAppendingPathComponent:name]);
        if (d) out[name] = d;
    }
    return out;
}

+ (BOOL)importFromDict:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]] || !dict.count) return NO;
    [self resetAll];
    NSString *dir = sciStorageDir();
    for (NSString *name in dict) {
        if (![name hasSuffix:@".json"]) continue;
        NSDictionary *d = dict[name];
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        sciWriteJSON([dir stringByAppendingPathComponent:name], d);
    }
    return YES;
}

@end
