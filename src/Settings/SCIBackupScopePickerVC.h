#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Bitmask must match the one in SCISettingsBackup.m — kept as plain
// NSInteger here so consumers don't have to drag the enum around.
typedef NS_OPTIONS(NSInteger, SCIBackupScopePickerMask) {
    SCIBackupScopePickerSettings = 1 << 0,
    SCIBackupScopePickerLists    = 1 << 1,
    SCIBackupScopePickerAnalyzer = 1 << 2,
};

// Scope picker + live preview. Rows combine a leading checkbox toggle with a
// tappable body that pushes a read-only drill-down; a "Raw JSON" row pushes
// the full payload viewer; a CTA commits.
@interface SCIBackupScopePickerVC : UIViewController

@property (nonatomic, copy) NSString *continueTitle;
@property (nonatomic, copy, nullable) NSString *headerMessage;
// Scopes present in the payload. Rows outside the mask are disabled.
@property (nonatomic, assign) SCIBackupScopePickerMask availableScopes;
@property (nonatomic, assign) SCIBackupScopePickerMask initialSelection;
// v2 envelope: {"settings": {...}, "lists": {...}, "analyzer": {...}}.
@property (nonatomic, copy, nullable) NSDictionary *payload;
@property (nonatomic, copy) void (^onContinue)(SCIBackupScopePickerMask chosen);

@end

NS_ASSUME_NONNULL_END
