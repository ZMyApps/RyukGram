#import <UIKit/UIKit.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIPAListKind) {
    SCIPAListKindPlain,           // no action button
    SCIPAListKindUnfollow,        // show "Unfollow" button (you follow them)
    SCIPAListKindFollow,          // show "Follow" button (you don't follow them)
    SCIPAListKindProfileUpdate,   // displays previous → current change rows
};

@interface SCIProfileAnalyzerListViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SCIProfileAnalyzerUser *> *)users
                         kind:(SCIPAListKind)kind;
- (instancetype)initWithTitle:(NSString *)title
              profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates;
@end

NS_ASSUME_NONNULL_END
