// Force IG into dark appearance regardless of iOS setting.

#import "../../Utils.h"

%group ForceDarkModeGroup

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}
- (void)becomeKeyWindow {
    %orig;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}
%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"theme_force_dark"]) {
        %init(ForceDarkModeGroup);
    }
}
