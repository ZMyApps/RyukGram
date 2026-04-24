// Crash-loop guard + pref registry for igt_* experimental flags.

#import <Foundation/Foundation.h>

@interface SCIExperimentalGuard : NSObject

+ (NSArray<NSString *> *)allPrefKeys;
+ (BOOL)anyEnabled;
+ (void)resetAll;
+ (BOOL)didResetThisLaunch;

@end
