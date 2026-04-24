#import "SCIChrome.h"
#import "Utils.h"
#import "SCIPrefObserver.h"

// MARK: - Canvas discovery

static UIView *sciFindCanvasDeep(UIView *root, int depth) {
    if (depth > 4) return nil;
    for (UIView *sub in root.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"CanvasView"]) return sub;
        UIView *found = sciFindCanvasDeep(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

// MARK: - SCIChromeCanvas

@interface SCIChromeCanvas ()
@property (nonatomic, strong) UITextField *secureField;
@property (nonatomic, strong, nullable) UIView *canvas;
@end

@implementation SCIChromeCanvas

+ (NSHashTable<SCIChromeCanvas *> *)instances {
    static NSHashTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [NSHashTable weakObjectsHashTable]; });
    return t;
}

+ (void)ensureObserverInstalled {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [SCIPrefObserver observeKey:@"hide_ui_on_capture" handler:^{
            for (SCIChromeCanvas *v in [SCIChromeCanvas instances]) [v applyPref];
        }];
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [SCIChromeCanvas ensureObserverInstalled];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _secureField = [UITextField new];
        _secureField.userInteractionEnabled = NO;
        _secureField.autocorrectionType = UITextAutocorrectionTypeNo;
        _secureField.spellCheckingType = UITextSpellCheckingTypeNo;
        _secureField.smartDashesType = UITextSmartDashesTypeNo;
        _secureField.smartQuotesType = UITextSmartQuotesTypeNo;
        _secureField.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        _secureField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self applyPref];
        [[SCIChromeCanvas instances] addObject:self];
        [self attachCanvasIfPossible];
    }
    return self;
}

- (UIView *)contentContainer { return self.canvas ?: self; }

- (void)applyPref {
    BOOL on = [SCIUtils getBoolPref:@"hide_ui_on_capture"];
    if (self.secureField.secureTextEntry != on) self.secureField.secureTextEntry = on;
}

- (void)didMoveToWindow { [super didMoveToWindow]; [self attachCanvasIfPossible]; }
- (void)layoutSubviews  { [super layoutSubviews];  [self attachCanvasIfPossible]; }

- (void)attachCanvasIfPossible {
    if (self.canvas && self.canvas.superview == self) return;

    [self.secureField layoutIfNeeded];
    UIView *c = sciFindCanvasDeep(self.secureField, 0);
    if (!c) return;

    // Migrate anything that landed on self (contentContainer fallback) into
    // the canvas so redaction covers it.
    NSMutableArray<UIView *> *stashed = [NSMutableArray array];
    for (UIView *sub in self.subviews) {
        if (sub != c) [stashed addObject:sub];
    }

    [c removeFromSuperview];
    [self insertSubview:c atIndex:0];
    c.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [c.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [c.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [c.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [c.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.canvas = c;

    for (UIView *v in stashed) {
        [v removeFromSuperview];
        [c addSubview:v];
    }
}

@end

// MARK: - SCIChromeButton

@interface SCIChromeButton ()
@property (nonatomic, strong) SCIChromeCanvas *chromeCanvas;
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong, readwrite) UIImageView *iconView;
@end

@implementation SCIChromeButton

- (instancetype)initWithSymbol:(NSString *)symbol
                     pointSize:(CGFloat)pointSize
                      diameter:(CGFloat)diameter {
    self = [super initWithFrame:CGRectMake(0, 0, diameter, diameter)];
    if (self) {
        _diameter = diameter;
        _symbolName = [symbol copy];
        _symbolPointSize = pointSize;
        _iconTint = [UIColor whiteColor];
        _bubbleColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        [self buildChrome];
    }
    return self;
}

- (void)buildChrome {
    self.adjustsImageWhenHighlighted = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _chromeCanvas = [SCIChromeCanvas new];
    _chromeCanvas.userInteractionEnabled = NO;
    [self addSubview:_chromeCanvas];
    [NSLayoutConstraint activateConstraints:@[
        [_chromeCanvas.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_chromeCanvas.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_chromeCanvas.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_chromeCanvas.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _bubbleView = [UIView new];
    _bubbleView.userInteractionEnabled = NO;
    _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
    _bubbleView.backgroundColor = _bubbleColor;
    _bubbleView.layer.cornerRadius = _diameter / 2;
    _bubbleView.clipsToBounds = YES;

    _iconView = [UIImageView new];
    _iconView.userInteractionEnabled = NO;
    _iconView.contentMode = UIViewContentModeCenter;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = _iconTint;
    [self reloadIcon];

    UIView *host = _chromeCanvas.contentContainer;
    [host addSubview:_bubbleView];
    [host addSubview:_iconView];
    [NSLayoutConstraint activateConstraints:@[
        [_bubbleView.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor],
        [_bubbleView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [_bubbleView.topAnchor      constraintEqualToAnchor:host.topAnchor],
        [_bubbleView.bottomAnchor   constraintEqualToAnchor:host.bottomAnchor],
        [_iconView.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
    ]];
}

- (CGSize)intrinsicContentSize { return CGSizeMake(_diameter, _diameter); }

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    [self reloadIcon];
}

- (void)setSymbolPointSize:(CGFloat)symbolPointSize {
    _symbolPointSize = symbolPointSize;
    [self reloadIcon];
}

- (void)setIconTint:(UIColor *)iconTint {
    _iconTint = [iconTint copy];
    _iconView.tintColor = iconTint;
}

- (void)setBubbleColor:(UIColor *)bubbleColor {
    _bubbleColor = [bubbleColor copy];
    _bubbleView.backgroundColor = bubbleColor;
}

- (void)reloadIcon {
    if (!_symbolName.length) { _iconView.image = nil; return; }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:_symbolPointSize
                                                                                       weight:UIImageSymbolWeightSemibold];
    _iconView.image = [UIImage systemImageNamed:_symbolName withConfiguration:cfg];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Keep the bubble circular when the caller resizes via constraints.
    CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    _bubbleView.layer.cornerRadius = r;
}

@end

// MARK: - SCIChromeLabel

@interface SCIChromeLabel ()
@property (nonatomic, strong) SCIChromeCanvas *chromeCanvas;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SCIChromeLabel

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _chromeCanvas = [SCIChromeCanvas new];
        _chromeCanvas.userInteractionEnabled = NO;
        [self addSubview:_chromeCanvas];
        [NSLayoutConstraint activateConstraints:@[
            [_chromeCanvas.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
            [_chromeCanvas.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_chromeCanvas.topAnchor      constraintEqualToAnchor:self.topAnchor],
            [_chromeCanvas.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
        ]];

        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.text = text;

        UIView *host = _chromeCanvas.contentContainer;
        [host addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [_label.topAnchor      constraintEqualToAnchor:host.topAnchor],
            [_label.bottomAnchor   constraintEqualToAnchor:host.bottomAnchor],
        ]];
    }
    return self;
}

- (NSString *)text            { return _label.text; }
- (void)setText:(NSString *)t { _label.text = t; }
- (UIFont *)font              { return _label.font; }
- (void)setFont:(UIFont *)f   { _label.font = f; }
- (UIColor *)textColor        { return _label.textColor; }
- (void)setTextColor:(UIColor *)c { _label.textColor = c; }
- (NSTextAlignment)textAlignment  { return _label.textAlignment; }
- (void)setTextAlignment:(NSTextAlignment)a { _label.textAlignment = a; }

@end

// MARK: - Bar button helpers

UIBarButtonItem *SCIChromeBarButtonItem(NSString *symbol,
                                         CGFloat pointSize,
                                         id target,
                                         SEL action,
                                         SCIChromeButton **outButton) {
    SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:symbol
                                                         pointSize:pointSize
                                                          diameter:28];
    btn.bubbleColor = [UIColor clearColor];
    if (target && action) [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    if (outButton) *outButton = btn;
    return [[UIBarButtonItem alloc] initWithCustomView:btn];
}

SCIChromeButton *SCIChromeButtonForBarItem(UIBarButtonItem *item) {
    UIView *v = item.customView;
    return [v isKindOfClass:[SCIChromeButton class]] ? (SCIChromeButton *)v : nil;
}
