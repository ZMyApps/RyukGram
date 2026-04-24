// Keyboard appearance override for IG's text inputs.
// Modes: "off" / "dark" / "oled".

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL sciKeyboardOLED(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"theme_keyboard"] isEqualToString:@"oled"];
}

%group KeyboardThemeDarkGroup

%hook UITextField
- (BOOL)becomeFirstResponder {
    self.keyboardAppearance = UIKeyboardAppearanceDark;
    return %orig;
}
%end

%hook UITextView
- (BOOL)becomeFirstResponder {
    self.keyboardAppearance = UIKeyboardAppearanceDark;
    return %orig;
}
%end

%end

%group KeyboardThemeOLEDGroup

%hook UIKBBackdropView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = [UIColor blackColor];
    for (UIView *sub in self.subviews) sub.backgroundColor = [UIColor blackColor];
}
%end

%hook UIKBKeyplaneChargedView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = [UIColor blackColor];
}
%end

%end

%ctor {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"theme_keyboard"];
    if ([mode isEqualToString:@"dark"] || [mode isEqualToString:@"oled"]) {
        %init(KeyboardThemeDarkGroup);
        if (sciKeyboardOLED()) {
            %init(KeyboardThemeOLEDGroup);
        }
    }
}
