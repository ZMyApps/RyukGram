#import "../../Utils.h"

%hook IGDirectThreadCallButtonsCoordinator
// 426+ dropped the sender arg
- (void)_didTapAudioButton {
    if ([SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; }];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton {
    if ([SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; }];
    } else {
        return %orig;
    }
}

// Pre-426 signatures
- (void)_didTapAudioButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; }];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; }];
    } else {
        return %orig;
    }
}
%end