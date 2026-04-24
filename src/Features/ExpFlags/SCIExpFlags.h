// Exp flag override store + observation logs.
// Override works only for MetaLocalExperiment (name-substring match on _experimentName).
// MC reads + scanned names are view-only — no reliable name→ID mapping.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SCIExpFlagOverride) {
    SCIExpFlagOverrideOff   = 0,
    SCIExpFlagOverrideTrue  = 1,
    SCIExpFlagOverrideFalse = 2,
};

typedef NS_ENUM(NSInteger, SCIExpMCType) {
    SCIExpMCTypeBool,
    SCIExpMCTypeInt,
    SCIExpMCTypeDouble,
    SCIExpMCTypeString,
};

@interface SCIExpObservation : NSObject
@property (nonatomic, copy) NSString *experimentName;
@property (nonatomic, copy) NSString *lastGroup;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface SCIExpMCObservation : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, assign) SCIExpMCType type;
@property (nonatomic, copy) NSString *lastDefault;
@property (nonatomic, assign) NSUInteger hitCount;
@end

@interface SCIExpFlags : NSObject

// overrides (persisted)
+ (SCIExpFlagOverride)overrideForName:(NSString *)name;
+ (void)setOverride:(SCIExpFlagOverride)o forName:(NSString *)name;
+ (NSArray<NSString *> *)allOverriddenNames;
+ (void)resetAllOverrides;

// meta observations (live)
+ (void)recordExperimentName:(NSString *)name group:(NSString *)group;
+ (NSArray<SCIExpObservation *> *)allObservations;

// MC id observations (live, view-only)
+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def;
+ (NSArray<SCIExpMCObservation *> *)allMCObservations;

// binary-scanned names (bg, cb on main)
+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *names))completion;

// crash-loop guard — 3 bad launches wipe overrides
+ (BOOL)checkAndHandleCrashLoop;
+ (void)markLaunchStable;

@end
