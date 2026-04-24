// Keep RyukGram's table-view surfaces visible under Full OLED.
//
// Grouped-inset cells default to #1C1C1E which Full OLED blackens. Repaint
// SCI*-owned cells at ~#121212 (alpha 0.89 passes the hook's a >= 0.9 gate)
// on attach, so settings + Profile Analyzer stay readable on black.

#import "../../Utils.h"
#import <objc/runtime.h>

static inline BOOL sciOLEDSurfaceInRyukGram(UIView *view) {
    UIResponder *r = view;
    while (r) {
        const char *name = class_getName([r class]);
        if (name && name[0] == 'S' && name[1] == 'C' && name[2] == 'I') return YES;
        r = r.nextResponder;
    }
    return NO;
}

static UIColor *sciOLEDSurfaceTone(void) {
    static UIColor *tone;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tone = [UIColor colorWithWhite:0.08 alpha:0.89]; });
    return tone;
}

%group OLEDSurfaceGroup

%hook UITableViewCell
- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;
    if (!sciOLEDSurfaceInRyukGram((UIView *)self)) return;
    UIColor *tone = sciOLEDSurfaceTone();
    UIBackgroundConfiguration *bg = [UIBackgroundConfiguration listGroupedCellConfiguration];
    bg.backgroundColor = tone;
    self.backgroundConfiguration = bg;
    self.backgroundColor = tone;
    self.contentView.backgroundColor = tone;
}
%end

%hook UITableViewHeaderFooterView
- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;
    if (!sciOLEDSurfaceInRyukGram((UIView *)self)) return;
    self.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
}
%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"theme_full_oled"]) {
        %init(OLEDSurfaceGroup);
    }
}
