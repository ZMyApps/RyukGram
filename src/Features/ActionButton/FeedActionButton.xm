// Feed action button — hooks IGUFIInteractionCountsView.
// Media lives on sibling cells (IGFeedItemPhotoCell, IGModernFeedVideoCell)
// in the same collection view section, NOT on the UFI cell itself.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger kFeedActionBtnTag = 13370;
static const void *kFeedPageIndexKey = &kFeedPageIndexKey;

// Read _currentMediaPK from IGFeedItemUFICell.
static NSString *sciFeedCurrentMediaPK(UIView *button) {
    UIResponder *r = button;
    Class ufiCls = NSClassFromString(@"IGFeedItemUFICell");
    while (r && !(ufiCls && [r isKindOfClass:ufiCls])) r = [r nextResponder];
    if (!r) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(r), "_currentMediaPK");
    if (!iv) return nil;
    id val = object_getIvar(r, iv);
    return [val isKindOfClass:[NSString class]] ? val : nil;
}

// Current carousel page index. Returns -1 if not found.
static NSInteger sciFeedCarouselPageIndex(UIView *button) {
    // Walk up to collection view
    UIView *v = button;
    UICollectionViewCell *ufiCell = nil;
    UICollectionView *cv = nil;
    while (v) {
        if (!ufiCell && [v isKindOfClass:[UICollectionViewCell class]]
            && [NSStringFromClass([v class]) containsString:@"UFI"]) {
            ufiCell = (UICollectionViewCell *)v;
        }
        if ([v isKindOfClass:[UICollectionView class]]) {
            cv = (UICollectionView *)v;
            break;
        }
        v = v.superview;
    }
    if (!ufiCell || !cv) return -1;

    NSIndexPath *ufiPath = [cv indexPathForCell:ufiCell];
    if (!ufiPath) return -1;
    NSInteger section = ufiPath.section;

    // Find IGFeedItemPageCell in same section
    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;
        NSString *cls = NSStringFromClass([cell class]);
        if (![cls containsString:@"Page"]) continue;

        // BFS for IGPageMediaView
        Class pmvCls = NSClassFromString(@"IGPageMediaView");
        if (pmvCls) {
            NSMutableArray *queue = [NSMutableArray arrayWithObject:cell];
            int scanned = 0;
            UIView *pmv = nil;
            while (queue.count && scanned < 50) {
                UIView *cur = queue.firstObject; [queue removeObjectAtIndex:0]; scanned++;
                if ([cur isKindOfClass:pmvCls]) { pmv = cur; break; }
                for (UIView *s in cur.subviews) [queue addObject:s];
            }
            if (pmv && [pmv respondsToSelector:@selector(currentMediaItem)] && [pmv respondsToSelector:@selector(items)]) {
                @try {
                    id current = ((id(*)(id,SEL))objc_msgSend)(pmv, @selector(currentMediaItem));
                    NSArray *items = ((id(*)(id,SEL))objc_msgSend)(pmv, @selector(items));
                    if (current && items.count) {
                        NSUInteger idx = [items indexOfObjectIdenticalTo:current];
                        if (idx != NSNotFound) return (NSInteger)idx;
                    }
                } @catch (__unused id e) {}
            }
        }

        // Fallback: _currentIndex ivar on the page cell
        Ivar idxIvar = class_getInstanceVariable([cell class], "_currentIndex");
        if (!idxIvar) idxIvar = class_getInstanceVariable([cell class], "_currentPage");
        if (!idxIvar) idxIvar = class_getInstanceVariable([cell class], "_currentMediaIndex");
        if (idxIvar) {
            ptrdiff_t offset = ivar_getOffset(idxIvar);
            NSInteger idx = *(NSInteger *)((char *)(__bridge void *)cell + offset);
            return idx;
        }

        // Fallback: compute page from scroll view content offset
        {
            NSMutableArray *sq = [NSMutableArray arrayWithObject:cell];
            int sc = 0;
            while (sq.count && sc < 100) {
                UIView *cur = sq.firstObject; [sq removeObjectAtIndex:0]; sc++;
                if ([cur isKindOfClass:[UIScrollView class]] && cur != cv) {
                    UIScrollView *sv = (UIScrollView *)cur;
                    CGFloat pageW = sv.bounds.size.width;
                    // Horizontal paging scroll view
                    if (pageW > 100 && sv.contentSize.width > pageW * 1.5) {
                        NSInteger idx = (NSInteger)round(sv.contentOffset.x / pageW);
                        return idx;
                    }
                }
                for (UIView *s in cur.subviews) [sq addObject:s];
            }
        }
    }
    return -1;
}

// Resolve current carousel child using page index.
static id sciFeedResolveCarouselChild(id parentMedia, UIView *button) {
    if (!parentMedia) return nil;
    if (![SCIMediaActions isCarouselMedia:parentMedia]) return parentMedia;

    NSInteger idx = sciFeedCarouselPageIndex(button);
    NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
    if (idx >= 0 && (NSUInteger)idx < children.count) {
        return children[idx];
    }
    return parentMedia;
}

// Extract IGMedia from sibling cells in the same collection view section.
static IGMedia *sciFeedMediaFromButton(UIView *button) {
    if (!button) return nil;
    Class mediaClass = NSClassFromString(@"IGMedia");
    if (!mediaClass) return nil;

    // Walk up to find UFI cell and collection view
    UIView *v = button;
    UICollectionViewCell *ufiCell = nil;
    UICollectionView *cv = nil;

    while (v) {
        if (!ufiCell && [v isKindOfClass:[UICollectionViewCell class]]
            && [NSStringFromClass([v class]) containsString:@"UFI"]) {
            ufiCell = (UICollectionViewCell *)v;
        }
        if ([v isKindOfClass:[UICollectionView class]]) {
            cv = (UICollectionView *)v;
            break;
        }
        v = v.superview;
    }

    if (!ufiCell || !cv) return nil;

    // Get section
    NSIndexPath *ufiPath = [cv indexPathForCell:ufiCell];
    if (!ufiPath) return nil;
    NSInteger section = ufiPath.section;

    // Search sibling cells for IGMedia
    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;
        if (cell == ufiCell) continue;

        // Filter to media cell classes
        NSString *cls = NSStringFromClass([cell class]);
        if (![cls containsString:@"Photo"] && ![cls containsString:@"Video"]
            && ![cls containsString:@"Media"] && ![cls containsString:@"Page"]) continue;

        // Scan ivars for IGMedia
        unsigned int count = 0;
        Class c = object_getClass(cell);
        while (c && c != [UICollectionViewCell class]) {
            Ivar *ivars = class_copyIvarList(c, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                if (!type || type[0] != '@') continue;
                @try {
                    id val = object_getIvar(cell, ivars[i]);
                    if (val && [val isKindOfClass:mediaClass]) {
                        free(ivars);
                        return (IGMedia *)val;
                    }
                    // Try .media selector on wrapper objects
                    if (val && [val respondsToSelector:@selector(media)]) {
                        id m = ((id(*)(id,SEL))objc_msgSend)(val, @selector(media));
                        if (m && [m isKindOfClass:mediaClass]) {
                            free(ivars);
                            return (IGMedia *)m;
                        }
                    }
                } @catch (__unused id e) {}
            }
            if (ivars) free(ivars);
            c = class_getSuperclass(c);
        }

        // Try mediaCellFeedItem (video cells)
        if ([cell respondsToSelector:@selector(mediaCellFeedItem)]) {
            @try {
                id m = ((id(*)(id,SEL))objc_msgSend)(cell, @selector(mediaCellFeedItem));
                if (m && [m isKindOfClass:mediaClass]) {
                    return (IGMedia *)m;
                }
            } @catch (__unused id e) {}
        }
    }

    return nil;
}

%hook IGUFIInteractionCountsView

- (void)updateUFIWithButtonsConfig:(id)config interactionCountProvider:(id)provider {
    %orig;

    if (![SCIUtils getBoolPref:@"feed_action_button"]) return;

    SCIChromeButton *btn = (SCIChromeButton *)[self viewWithTag:kFeedActionBtnTag];
    if (![btn isKindOfClass:[SCIChromeButton class]]) btn = nil;
    if (!btn) {
        btn = [[SCIChromeButton alloc] initWithSymbol:@"ellipsis.circle" pointSize:21 diameter:36];
        btn.tag = kFeedActionBtnTag;
        btn.iconTint = [UIColor labelColor];
        btn.bubbleColor = [UIColor clearColor];
        [self addSubview:btn];

        // Position: right side, left of bookmark. Shifted up 4pt to
        // align with the native like/comment/share icons.
        [NSLayoutConstraint activateConstraints:@[
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-44],
            [btn.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-6],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36],
        ]];
    }

    // Reconfigure with fresh media provider.
    [SCIActionButton configureButton:btn
                             context:SCIActionContextFeed
                             prefKey:@"feed_action_default"
                       mediaProvider:^id (UIView *sourceView) {
        id parentMedia = sciFeedMediaFromButton(sourceView);
        if (!parentMedia) return nil;

        if ([SCIMediaActions isCarouselMedia:parentMedia]) {
            NSInteger idx = sciFeedCarouselPageIndex(sourceView);
            NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
            if (idx >= 0 && (NSUInteger)idx < children.count) {
                // Stash page index for the menu builder to find the parent.
                objc_setAssociatedObject(sourceView, kFeedPageIndexKey,
                    @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return children[idx];
            }
        }
        return parentMedia;
    }];
}

%end
