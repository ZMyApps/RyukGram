// Pure-black DM thread background + incoming message bubbles.
// IGDirectThreadBackgroundImageView / IGDirectMessageBubbleView declared in InstagramHeaders.h.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%group OLEDChatThemeGroup

%hook IGDirectThreadBackgroundImageView
- (void)layoutSubviews {
    %orig;
    self.image = nil;
    self.backgroundColor = [UIColor blackColor];
}
- (void)setImage:(UIImage *)image {
    %orig(nil);
    self.backgroundColor = [UIColor blackColor];
}
- (void)setBackgroundColor:(UIColor *)color {
    %orig([UIColor blackColor]);
}
%end

%hook IGDirectMessageBubbleView
- (void)layoutSubviews {
    %orig;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([self.backgroundColor getRed:&r green:&g blue:&b alpha:&a]) {
        // Leave tinted outgoing bubbles (blue/purple) alone.
        if (a >= 0.9 && r < 0.2 && g < 0.2 && b < 0.2) {
            self.backgroundColor = [UIColor blackColor];
        }
    }
}
%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"theme_oled_chat"]) {
        %init(OLEDChatThemeGroup);
    }
}
