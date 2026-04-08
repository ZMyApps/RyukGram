#import "../../Utils.h"
#import "SCIExcludedThreads.h"

%hook IGDirectVisualMessage
- (NSInteger)viewMode {
    NSInteger mode = %orig;
    // 0 = view once, 1 = replayable. Force view-once behavior to leak through
    // when the active thread is excluded so the message expires normally.
    if ([SCIUtils getBoolPref:@"disable_view_once_limitations"]
        && mode == 0
        && ![SCIExcludedThreads isActiveThreadExcluded]) {
        return 1;
    }
    return mode;
}
%end