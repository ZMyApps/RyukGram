// Hide the trending-searches pill bar under the explore search bar.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%group HideTrendingSearchesGroup
%hook IGDSSegmentedPillBarView
- (void)didMoveToSuperview {
    %orig;
    if (![[self delegate] isKindOfClass:%c(IGSearchTypeaheadNavigationHeaderView)]) return;
    self.hidden = YES;
}
- (void)layoutSubviews {
    %orig;
    if (![[self delegate] isKindOfClass:%c(IGSearchTypeaheadNavigationHeaderView)]) return;
    self.hidden = YES;
}
%end
%end

%ctor {
    if ([SCIUtils getBoolPref:@"hide_trending_searches"]) {
        %init(HideTrendingSearchesGroup);
    }
}
