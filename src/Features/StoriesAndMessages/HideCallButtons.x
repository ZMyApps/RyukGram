// Hide voice/video call buttons in DM thread header.

#import "../../Utils.h"

// IGDirectThreadCallButtonsCoordinator / IGDirectCallButton / IGNavigationBar
// declared in InstagramHeaders.h

static BOOL sciShouldHide(UIView *b) {
    if (![b isKindOfClass:NSClassFromString(@"IGDirectCallButton")]) return NO;
    NSString *axId = b.accessibilityIdentifier;
    if ([axId isEqualToString:@"audio-call"]) return [SCIUtils getBoolPref:@"hide_voice_call_button"];
    if ([axId isEqualToString:@"video-chat"]) return [SCIUtils getBoolPref:@"hide_video_call_button"];
    return NO;
}

static BOOL sciPlatterContainsHiddenButton(UIView *platter) {
    NSMutableArray *q = [NSMutableArray arrayWithObject:platter];
    while (q.count) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        if (sciShouldHide(v)) return YES;
        [q addObjectsFromArray:v.subviews];
    }
    return NO;
}

%group HideCallButtonsGroup

// Block taps in case a hidden button still receives hit-test events during transitions.
%hook IGDirectThreadCallButtonsCoordinator
- (void)_didTapAudioButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_voice_call_button"]) return;
    %orig;
}
- (void)_didTapVideoButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_video_call_button"]) return;
    %orig;
}
%end

%hook IGDirectCallButton
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (sciShouldHide((UIView *)self)) self.hidden = YES;
}
%end

// Re-pack platters on each layout: shift every non-back platter right by the
// total width of the hidden call platters to eliminate the gap.
static void sciRepackPlatters(UIView *container) {
    NSMutableArray *platters = [NSMutableArray array];
    for (UIView *sv in container.subviews)
        if ([NSStringFromClass([sv class]) isEqualToString:@"_UINavigationBarPlatterView"])
            [platters addObject:sv];

    CGFloat hiddenWidth = 0;
    NSMutableArray *alive = [NSMutableArray array];
    for (UIView *p in platters) {
        if (sciPlatterContainsHiddenButton(p)) {
            hiddenWidth += p.frame.size.width;
            p.hidden = YES;
        } else {
            p.hidden = NO;
            [alive addObject:p];
        }
    }
    if (!alive.count || hiddenWidth == 0) {
        for (UIView *p in alive) p.transform = CGAffineTransformIdentity;
        return;
    }
    for (UIView *p in alive) {
        if (p.frame.origin.x < 60) { p.transform = CGAffineTransformIdentity; continue; }
        p.transform = CGAffineTransformMakeTranslation(hiddenWidth, 0);
    }
}

%hook IGNavigationBar
- (void)layoutSubviews {
    %orig;
    NSMutableArray *q = [NSMutableArray arrayWithObject:self];
    while (q.count) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        if ([NSStringFromClass([v class]) containsString:@"NavigationBarPlatterContainer"]) {
            sciRepackPlatters(v);
            break;
        }
        [q addObjectsFromArray:v.subviews];
    }
}
%end

%end // HideCallButtonsGroup

%ctor {
    if ([SCIUtils getBoolPref:@"hide_voice_call_button"] ||
        [SCIUtils getBoolPref:@"hide_video_call_button"]) {
        %init(HideCallButtonsGroup);
    }
}
