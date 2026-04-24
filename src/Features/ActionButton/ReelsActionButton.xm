// Reels action button — injects a RyukGram action button above the reel's
// vertical like/comment/share sidebar (IGSundialViewerVerticalUFI).

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger kReelActionBtnTag = 1337;

static UIView *sciFindSuperviewOfClass(UIView *view, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return nil;
    UIView *current = view.superview;
    for (int depth = 0; current && depth < 20; depth++) {
        if ([current isKindOfClass:cls]) return current;
        current = current.superview;
    }
    return nil;
}

static id sciFindMediaIvar(UIView *view) {
    if (!view) return nil;
    Class mediaClass = NSClassFromString(@"IGMedia");
    if (!mediaClass) return nil;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([view class], &count);
    id found = nil;
    for (unsigned int i = 0; i < count; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        @try {
            id val = object_getIvar(view, ivars[i]);
            if (val && [val isKindOfClass:mediaClass]) { found = val; break; }
        } @catch (__unused id e) {}
    }
    if (ivars) free(ivars);
    return found;
}

// Resolve the current carousel child from _currentIndex.
static id sciCurrentCarouselChildMedia(UIView *carouselCell, id parentMedia) {
    if (!carouselCell || !parentMedia) return parentMedia;

    // Try _currentIndex ivar
    Ivar idxIvar = class_getInstanceVariable([carouselCell class], "_currentIndex");
    NSInteger currentIdx = 0;
    if (idxIvar) {
        ptrdiff_t offset = ivar_getOffset(idxIvar);
        currentIdx = *(NSInteger *)((char *)(__bridge void *)carouselCell + offset);
    }

    // Fallback: _currentFractionalIndex
    if (!idxIvar || currentIdx == 0) {
        Ivar fracIvar = class_getInstanceVariable([carouselCell class], "_currentFractionalIndex");
        if (fracIvar) {
            ptrdiff_t fOffset = ivar_getOffset(fracIvar);
            double fracIdx = *(double *)((char *)(__bridge void *)carouselCell + fOffset);
            NSInteger roundedIdx = (NSInteger)round(fracIdx);
            if (roundedIdx > 0) currentIdx = roundedIdx;
        }
    }

    // Fallback: inner collection view content offset
    Ivar cvIvar = class_getInstanceVariable([carouselCell class], "_collectionView");
    if (cvIvar) {
        UICollectionView *cv = object_getIvar(carouselCell, cvIvar);
        if (cv) {
            CGFloat pageWidth = cv.bounds.size.width;
            if (pageWidth > 0) {
                NSInteger cvIdx = (NSInteger)round(cv.contentOffset.x / pageWidth);
                if (cvIdx > currentIdx) currentIdx = cvIdx;
            }
        }
    }

    NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
    if (currentIdx >= 0 && (NSUInteger)currentIdx < children.count) {
        return children[currentIdx];
    }
    return parentMedia;
}

// Media provider for reels. Returns current page's child for carousels.
static id sciReelsMediaProvider(UIView *sourceView) {
    // Video reel
    UIView *videoCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerVideoCell");
    if (videoCell) {
        id m = sciFindMediaIvar(videoCell);
        if (m) return m;
    }

    // Photo reel
    UIView *photoCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerPhotoCell");
    if (photoCell) {
        id m = sciFindMediaIvar(photoCell);
        if (m) return m;
    }

    // Carousel reel
    UIView *carouselCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerCarouselCell");
    if (carouselCell) {
        id parentMedia = sciFindMediaIvar(carouselCell);
        if (parentMedia) {
            return sciCurrentCarouselChildMedia(carouselCell, parentMedia);
        }
    }

    return nil;
}

%hook IGSundialViewerVerticalUFI

- (void)didMoveToSuperview {
    %orig;

    if (![SCIUtils getBoolPref:@"reels_action_button"]) return;
    if (!self.superview) return;

    SCIChromeButton *btn = (SCIChromeButton *)[self viewWithTag:kReelActionBtnTag];
    if (![btn isKindOfClass:[SCIChromeButton class]]) btn = nil;

    if (!btn) {
        UIImageSymbolConfiguration *symCfg =
            [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
        UIImage *base = [UIImage systemImageNamed:@"ellipsis.circle" withConfiguration:symCfg];
        // Bake the drop shadow into the image so no CALayer shadow is needed.
        CGFloat pad = 8;
        CGSize sz = CGSizeMake(base.size.width + pad * 2, base.size.height + pad * 2);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz];
        UIImage *icon = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextRef c = ctx.CGContext;
            CGContextSaveGState(c);
            CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 3,
                [UIColor colorWithWhite:0 alpha:0.55].CGColor);
            UIImage *tinted = [base imageWithTintColor:[UIColor whiteColor]
                                         renderingMode:UIImageRenderingModeAlwaysOriginal];
            [tinted drawInRect:CGRectMake(pad, pad, base.size.width, base.size.height)];
            CGContextRestoreGState(c);
        }];

        btn = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:0 diameter:40];
        btn.tag = kReelActionBtnTag;
        btn.bubbleColor = [UIColor clearColor];
        btn.iconView.image = icon;

        // Capsule configuration gives us the native dark platter animation
        // when the menu opens/closes — behaviour parity with IG's own chrome.
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.background.backgroundColor = [UIColor clearColor];
        cfg.contentInsets = NSDirectionalEdgeInsetsZero;
        btn.configuration = cfg;

        self.clipsToBounds = NO;
        [self addSubview:btn];

        [NSLayoutConstraint activateConstraints:@[
            [btn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [btn.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-10],
            [btn.widthAnchor constraintEqualToConstant:40],
            [btn.heightAnchor constraintEqualToConstant:40]
        ]];
    }

    [SCIActionButton configureButton:btn
                             context:SCIActionContextReels
                             prefKey:@"reels_action_default"
                       mediaProvider:^id (UIView *sourceView) {
        return sciReelsMediaProvider(sourceView);
    }];
}

%end
