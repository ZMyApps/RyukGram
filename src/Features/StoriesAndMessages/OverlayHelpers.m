#import "OverlayHelpers.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../Downloader/Download.h"

// MARK: - Context detection

BOOL sciOverlayIsInDMContext(UIView *overlay) {
    Class dmCls = NSClassFromString(@"IGDirectVisualMessageViewerController");
    if (!dmCls) return NO;

    UIResponder *r = overlay.nextResponder;
    while (r) {
        if ([r isKindOfClass:dmCls]) return YES;
        r = r.nextResponder;
    }

    // Fallback: _gestureDelegate ivar is the DM VC in DM contexts.
    static Ivar gdIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGStoryFullscreenOverlayView");
        if (c) gdIvar = class_getInstanceVariable(c, "_gestureDelegate");
    });
    if (gdIvar) {
        id d = object_getIvar(overlay, gdIvar);
        if (d && [d isKindOfClass:dmCls]) return YES;
    }
    return NO;
}

UIView *sciFindOverlayInView(UIView *root) {
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls || !root) return nil;
    if ([root isKindOfClass:overlayCls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = sciFindOverlayInView(sub);
        if (found) return found;
    }
    return nil;
}

// MARK: - DM media URL

NSURL *sciDMMediaURL(UIViewController *dmVC, BOOL *outIsVideo) {
    if (!dmVC) return nil;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return nil;

    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    Ivar mIvar = vmi ? class_getInstanceVariable([vmi class], "_media") : nil;
    id visMedia = mIvar ? object_getIvar(vmi, mIvar) : nil;
    if (!visMedia) return nil;

    @try {
        id rawVideo = [msg valueForKey:@"rawVideo"];
        if (rawVideo) {
            NSURL *url = [SCIUtils getVideoUrl:rawVideo];
            if (url) { if (outIsVideo) *outIsVideo = YES; return url; }
        }
    } @catch (__unused NSException *e) {}

    Ivar pi = class_getInstanceVariable([visMedia class], "_photo_photo");
    id photo = pi ? object_getIvar(visMedia, pi) : nil;
    if (photo) {
        if (outIsVideo) *outIsVideo = NO;
        return [SCIUtils getPhotoUrl:photo];
    }
    return nil;
}

// MARK: - DM actions

// Strong refs — SCIDownloadDelegate needs to outlive the download.
static SCIDownloadDelegate *sciDMShareDelegate = nil;
static SCIDownloadDelegate *sciDMDownloadDelegate = nil;

void sciDMExpandMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    if (isVideo) [SCIMediaViewer showWithVideoURL:url photoURL:nil caption:nil];
    else         [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:nil];
}

void sciDMShareMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    sciDMShareDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    [sciDMShareDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

void sciDMDownloadMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    sciDMDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:YES];
    [sciDMDownloadDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

// Flips dmVisualMsgsViewedButtonEnabled for ~1s so VisualMsgModifier lets the
// begin/end playback callbacks through, then restores.
void sciDMMarkCurrentAsViewed(UIViewController *dmVC) {
    if (!dmVC) return;

    BOOL wasEnabled = dmVisualMsgsViewedButtonEnabled;
    dmVisualMsgsViewedButtonEnabled = YES;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    Ivar erIvar = class_getInstanceVariable([dmVC class], "_eventResponders");
    NSArray *responders = erIvar ? object_getIvar(dmVC, erIvar) : nil;

    if (responders && msg) {
        for (id resp in responders) {
            SEL beginSel = @selector(visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:);
            if ([resp respondsToSelector:beginSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger);
                ((Fn)objc_msgSend)(resp, beginSel, dmVC, msg, 0);
            }
            SEL endSel = @selector(visualMessageViewerController:didEndPlaybackForVisualMessage:atIndex:mediaCurrentTime:forNavType:);
            if ([resp respondsToSelector:endSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger, CGFloat, NSInteger);
                ((Fn)objc_msgSend)(resp, endSel, dmVC, msg, 0, 0.0, 0);
            }
        }
    }

    SEL dismissSel = NSSelectorFromString(@"_didTapHeaderViewDismissButton:");
    if ([dmVC respondsToSelector:dismissSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(dmVC, dismissSel, nil);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dmVisualMsgsViewedButtonEnabled = wasEnabled;
    });

    [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Marked as viewed")];
}

// MARK: - Settings shortcut

void sciOpenMessagesSettings(UIView *source) {
    UIWindow *win = source.window;
    if (!win) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) return;
    [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Messages")];
}
