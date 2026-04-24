#import <Foundation/Foundation.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

// Posted on every save/update/reset. userInfo carries @"user_pk".
extern NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification;

// Per-account on-disk store: current + previous snapshots (for since-last-scan
// diffs), an optional baseline for cumulative tracking, and a lightweight
// header cache keyed by PK.
@interface SCIProfileAnalyzerStorage : NSObject

+ (nullable SCIProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK;
+ (nullable SCIProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK;
+ (nullable SCIProfileAnalyzerSnapshot *)baselineSnapshotForUserPK:(NSString *)userPK;
+ (BOOL)saveBaselineSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;
+ (void)clearBaselineForUserPK:(NSString *)userPK;

// Rotates current → previous, then writes the new current.
+ (BOOL)saveSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;

// Overwrites current without touching previous — keeps the diff baseline
// intact across in-app follow/unfollow mutations.
+ (BOOL)updateCurrentSnapshot:(SCIProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;

+ (void)resetForUserPK:(NSString *)userPK;
+ (void)resetAll;

// Self-profile summary (username, name, counts, pic) cached so the header
// paints on cold launch without a /users/{pk}/info/ call.
+ (nullable NSDictionary *)headerInfoForUserPK:(NSString *)userPK;
+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK;

// Backup/Restore hooks — opaque pk-keyed JSON blob.
+ (NSDictionary *)exportedDict;
+ (BOOL)importFromDict:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
