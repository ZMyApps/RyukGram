#import <Foundation/Foundation.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIProfileAnalyzerError) {
    SCIProfileAnalyzerErrorNoSession = 1,
    SCIProfileAnalyzerErrorTooManyFollowers,
    SCIProfileAnalyzerErrorNetwork,
    SCIProfileAnalyzerErrorCancelled,
};

// Hard cap — beyond this follower count we refuse to run. Each followers
// page returns ~25-50 users so large accounts hit IG rate limits fast.
extern const NSInteger SCIProfileAnalyzerMaxFollowerCount;

typedef void(^SCIPAProgress)(NSString *status, double fraction);
typedef void(^SCIPACompletion)(SCIProfileAnalyzerSnapshot * _Nullable snapshot, NSError * _Nullable error);
// Fires once, right after the self-user-info call returns. Lets the UI
// paint the header immediately instead of waiting for the full run to finish.
typedef void(^SCIPAHeaderInfo)(NSDictionary *userInfo);

@interface SCIProfileAnalyzerService : NSObject

@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedService;

- (void)runForSelfWithHeaderInfo:(nullable SCIPAHeaderInfo)headerInfo
                        progress:(SCIPAProgress)progress
                      completion:(SCIPACompletion)completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
