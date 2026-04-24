// SCIChangelog — fetches RyukGram release notes from GitHub and presents
// them in a scrollable popup. Shows automatically on launch when the tweak
// version changes; also available from the About page.

#import <UIKit/UIKit.h>

@interface SCIChangelog : NSObject

/// Present the latest release notes when this is a version the user hasn't
/// seen yet. No-op otherwise. Safe to call on every launch.
+ (void)presentIfNewFromWindow:(UIWindow *)window;

/// Present a browser of every release (tap a row → see its notes).
+ (void)presentAllFromViewController:(UIViewController *)host;

@end
