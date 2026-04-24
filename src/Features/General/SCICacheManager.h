// Compute and clear Instagram's local caches (Library/Caches, Application
// Support, tmp, NSURLCache).

#import <Foundation/Foundation.h>

// Posted on main after a non-transient scan completes. Object is NSNumber.
extern NSString *const SCICacheSizeDidUpdateNotification;

@interface SCICacheManager : NSObject

// Scan + update cachedSize + persist. Completion on main.
+ (void)getCacheSizeWithCompletion:(void(^)(uint64_t bytes))completion;

// Scan without touching cachedSize / persistence / notification.
+ (void)getCacheSizeTransientWithCompletion:(void(^)(uint64_t bytes))completion;

// Last computed value; lazy-loads from NSUserDefaults on first call.
+ (uint64_t)cachedSize;

+ (void)refreshSizeInBackground;

// No-op when `cache_auto_check_size` is off.
+ (void)refreshSizeInBackgroundIfEnabled;

// Completion reports bytes reclaimed, on main.
+ (void)clearCacheWithCompletion:(void(^)(uint64_t bytesCleared))completion;

// Fires a silent clear if the configured interval has elapsed. Called from
// applicationDidEnterBackground.
+ (void)runAutoClearIfDue;

+ (NSString *)formattedSize:(uint64_t)bytes;

@end
