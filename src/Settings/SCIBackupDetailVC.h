#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Read-only searchable key/value list.
// Sections: [ { "title": ..., "rows": [ { "title": ..., "value": ... }, ... ] } ]
@interface SCIBackupDetailVC : UIViewController
- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections;
@end

NS_ASSUME_NONNULL_END
