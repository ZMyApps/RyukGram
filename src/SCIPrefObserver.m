#import "SCIPrefObserver.h"

@interface SCIPrefObserver ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *handlers;
@end

@implementation SCIPrefObserver

+ (instancetype)shared {
    static SCIPrefObserver *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SCIPrefObserver new];
        s.handlers = [NSMutableDictionary dictionary];
    });
    return s;
}

+ (void)observeKey:(NSString *)key handler:(void (^)(void))handler {
    if (!key.length || !handler) return;
    SCIPrefObserver *s = [self shared];
    @synchronized (s) {
        NSMutableArray *arr = s.handlers[key];
        if (!arr) {
            arr = [NSMutableArray array];
            s.handlers[key] = arr;
            [[NSUserDefaults standardUserDefaults] addObserver:s
                                                    forKeyPath:key
                                                       options:0
                                                       context:NULL];
        }
        [arr addObject:[handler copy]];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    NSArray *snapshot;
    @synchronized (self) { snapshot = [self.handlers[keyPath] copy]; }
    if (!snapshot.count) return;
    dispatch_block_t run = ^{
        for (void (^h)(void) in snapshot) h();
    };
    if ([NSThread isMainThread]) run();
    else dispatch_async(dispatch_get_main_queue(), run);
}

@end
