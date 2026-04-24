// SCIQualityPicker — quality selection bottom sheet for HD downloads.

#import <UIKit/UIKit.h>
#import "SCIDashParser.h"
#import "Downloader/Download.h"

@interface SCIQualityPicker : NSObject

/// Show quality picker or auto-pick based on prefs. Returns NO if enhanced
/// downloads are off or no DASH manifest is found (calls fallback).
/// `action` is passed through to the Audio / Photo rows inside the sheet.
+ (BOOL)pickQualityForMedia:(id)media
                   fromView:(UIView *)sourceView
                     action:(DownloadAction)action
                     picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                   fallback:(void(^)(void))fallback;

@end
