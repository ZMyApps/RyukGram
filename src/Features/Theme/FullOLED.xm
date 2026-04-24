// Replace IG's dark-gray surfaces with pure black.
//
// Swaps any near-black fill (RGB all < 0.13, alpha >= 0.9) for #000000.
// RyukGram's own surfaces opt out by painting above the threshold or with
// alpha < 0.9 — see SCIOLEDSurface.xm.

#import "../../Utils.h"

static inline BOOL sciOLEDShouldReplace(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if ([color getWhite:&w alpha:&a]) {
            return (a >= 0.9 && w < 0.13);
        }
        return NO;
    }
    return (a >= 0.9 && r < 0.13 && g < 0.13 && b < 0.13);
}

%group FullOLEDGroup

%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (sciOLEDShouldReplace(color)) {
        %orig([UIColor blackColor]);
        return;
    }
    %orig;
}
%end

%hook CAGradientLayer
- (void)setColors:(NSArray *)colors {
    if (colors.count >= 1) {
        BOOL allDark = YES;
        for (id raw in colors) {
            CGColorRef cg = (__bridge CGColorRef)raw;
            if (!cg) { allDark = NO; break; }
            UIColor *c = [UIColor colorWithCGColor:cg];
            if (!sciOLEDShouldReplace(c)) { allDark = NO; break; }
        }
        if (allDark) {
            id black = (id)[UIColor blackColor].CGColor;
            NSMutableArray *flat = [NSMutableArray arrayWithCapacity:colors.count];
            for (NSUInteger i = 0; i < colors.count; i++) [flat addObject:black];
            %orig(flat);
            return;
        }
    }
    %orig;
}
%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"theme_full_oled"]) {
        %init(FullOLEDGroup);
    }
}
