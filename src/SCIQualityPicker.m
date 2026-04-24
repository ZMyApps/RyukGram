#import "SCIQualityPicker.h"
#import "SCIFFmpeg.h"
#import "Utils.h"
#import "InstagramHeaders.h"
#import "ActionButton/SCIMediaActions.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <objc/message.h>

// MARK: - Row cell

@interface _SCIQualityCell : UITableViewCell
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation _SCIQualityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    _playButton.tintColor = [UIColor labelColor];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_playButton];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [self.contentView addSubview:_spinner];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.font = [UIFont systemFontOfSize:11];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    _subtitleLabel.numberOfLines = 1;
    _subtitleLabel.adjustsFontSizeToFitWidth = YES;
    _subtitleLabel.minimumScaleFactor = 0.85;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_subtitleLabel];

    UIImageSymbolConfiguration *menuCfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIFontWeightMedium];
    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_menuButton setImage:[UIImage systemImageNamed:@"ellipsis.circle" withConfiguration:menuCfg] forState:UIControlStateNormal];
    _menuButton.tintColor = [UIColor secondaryLabelColor];
    _menuButton.translatesAutoresizingMaskIntoConstraints = NO;
    _menuButton.showsMenuAsPrimaryAction = YES;
    [self.contentView addSubview:_menuButton];

    [NSLayoutConstraint activateConstraints:@[
        [_playButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_playButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:32],
        [_playButton.heightAnchor constraintEqualToConstant:32],

        [_spinner.centerXAnchor constraintEqualToAnchor:_playButton.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:12],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_menuButton.leadingAnchor constant:-8],

        [_menuButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [_menuButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_menuButton.widthAnchor constraintEqualToConstant:32],
        [_menuButton.heightAnchor constraintEqualToConstant:32],
    ]];

    return self;
}

- (void)setLoading:(BOOL)loading {
    if (loading) {
        self.playButton.hidden = YES;
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
        self.playButton.hidden = NO;
    }
}

@end

// MARK: - Sheet VC

@interface _SCIQualitySheetVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSArray<SCIDashRepresentation *> *videoReps;
@property (nonatomic, strong) SCIDashRepresentation *audioRep;
@property (nonatomic, strong) NSURL *standardURL;
@property (nonatomic, strong) id mediaRef;
@property (nonatomic, assign) DownloadAction saveAction;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, copy) void (^onPickStandard)(void);
@property (nonatomic, copy) void (^onPickHD)(SCIDashRepresentation *video, SCIDashRepresentation *audio);
@end

@implementation _SCIQualitySheetVC

- (void)viewDidLoad {
    [super viewDidLoad];

    // Match the expanded-sheet grey so the initial state doesn't look glass-transparent.
    UIColor *sheetGrey = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0]
            : [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }];
    self.view.backgroundColor = sheetGrey;
    self.view.opaque = YES;

    UIView *solidCard = [UIView new];
    solidCard.backgroundColor = sheetGrey;
    solidCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:solidCard];
    [self.view sendSubviewToBack:solidCard];
    [NSLayoutConstraint activateConstraints:@[
        [solidCard.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [solidCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [solidCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [solidCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = SCILocalized(@"Download Quality");
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.rowHeight = 56;
    self.tableView.sectionHeaderTopPadding = 8;
    [self.tableView registerClass:[_SCIQualityCell class] forCellReuseIdentifier:@"q"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],

        [self.tableView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)dismiss { [self dismissViewControllerAnimated:YES completion:nil]; }

// MARK: - Table
// Sections: Standard, HD, optional Audio, optional Extras (photo). Audio
// appears before Extras when both are present.

- (BOOL)_hasExtrasSection { return self.photoURL != nil; }
- (BOOL)_hasAudioSection  { return self.audioRep.url != nil; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    NSInteger n = 2;
    if ([self _hasExtrasSection]) n++;
    if ([self _hasAudioSection])  n++;
    return n;
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return (NSInteger)self.videoReps.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Standard";
    if (section == 1) return @"HD";
    if (section == 2 && [self _hasAudioSection]) return SCILocalized(@"Audio");
    return SCILocalized(@"Extras");
}

- (UIImage *)_playIconSilent:(BOOL)silent {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    NSString *name = silent ? @"play.slash.fill" : @"play.fill";
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    _SCIQualityCell *cell = [tv dequeueReusableCellWithIdentifier:@"q" forIndexPath:ip];
    [cell setLoading:NO];

    BOOL silent = !self.hasAudio;

    if (ip.section == 0) {
        cell.titleLabel.text = SCILocalized(@"Standard");
        cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.subtitleLabel.text = silent
            ? SCILocalized(@"720p • progressive • silent")
            : SCILocalized(@"720p • progressive • fastest");
        cell.playButton.hidden = (self.standardURL == nil);
        cell.menuButton.hidden = (self.standardURL == nil);
        [cell.playButton setImage:[self _playIconSilent:silent] forState:UIControlStateNormal];
        cell.accessoryType = UITableViewCellAccessoryNone;

        cell.playButton.tag = -1;
        [cell.playButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.playButton addTarget:self action:@selector(playStandardPreview:) forControlEvents:UIControlEventTouchUpInside];

        cell.menuButton.menu = [self menuForStandard];
    } else if (ip.section == 1) {
        SCIDashRepresentation *rep = self.videoReps[ip.row];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.playButton.hidden = NO;
        cell.menuButton.hidden = NO;
        [cell.playButton setImage:[self _playIconSilent:silent] forState:UIControlStateNormal];

        NSString *label = rep.qualityLabel ?: @"";
        if (rep.height > 0) {
            NSInteger shortSide = MIN(rep.width, rep.height);
            if (shortSide > 0) label = [NSString stringWithFormat:@"%ldp", (long)shortSide];
        }

        NSString *bw = rep.bandwidth > 1000000
            ? [NSString stringWithFormat:@"%.1f Mbps", rep.bandwidth / 1000000.0]
            : [NSString stringWithFormat:@"%ld Kbps", (long)(rep.bandwidth / 1000)];
        cell.titleLabel.text = [NSString stringWithFormat:@"%@ • %@", label, bw];
        cell.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];

        NSMutableArray *parts = [NSMutableArray array];
        if (rep.width > 0 && rep.height > 0)
            [parts addObject:[NSString stringWithFormat:@"%ld×%ld", (long)rep.width, (long)rep.height]];
        if (rep.frameRate > 0)
            [parts addObject:[NSString stringWithFormat:@"%.0ffps", rep.frameRate]];
        if (rep.codecs.length) {
            NSString *codec = [[rep.codecs componentsSeparatedByString:@"."] firstObject] ?: rep.codecs;
            [parts addObject:codec];
        }
        if (silent) [parts addObject:SCILocalized(@"silent")];
        cell.subtitleLabel.text = [parts componentsJoinedByString:@" • "];

        cell.playButton.tag = ip.row;
        [cell.playButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.playButton addTarget:self action:@selector(playPreview:) forControlEvents:UIControlEventTouchUpInside];

        cell.menuButton.menu = [self menuForRow:ip.row videoRep:rep];
    } else {
        BOOL isAudio = (ip.section == 2 && [self _hasAudioSection]);
        BOOL isPhoto = !isAudio;

        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.playButton.hidden = NO;
        cell.menuButton.hidden = YES;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];

        if (isPhoto) {
            cell.titleLabel.text = SCILocalized(@"Photo");
            cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            cell.subtitleLabel.text = SCILocalized(@"Raw image (no audio, no video)");
            [cell.playButton setImage:[UIImage systemImageNamed:@"photo" withConfiguration:cfg] forState:UIControlStateNormal];
        } else if (isAudio) {
            cell.titleLabel.text = SCILocalized(@"Audio only");
            cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            NSString *codec = self.audioRep.codecs.length
                ? [[self.audioRep.codecs componentsSeparatedByString:@"."] firstObject]
                : @"m4a";
            NSString *bw = self.audioRep.bandwidth > 0
                ? [NSString stringWithFormat:@"%ld Kbps", (long)(self.audioRep.bandwidth / 1000)]
                : @"";
            cell.subtitleLabel.text = [@[codec, bw] componentsJoinedByString:@" • "];
            [cell.playButton setImage:[UIImage systemImageNamed:@"music.note" withConfiguration:cfg] forState:UIControlStateNormal];
        }

        cell.playButton.tag = -2;
        [cell.playButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
    }
    return cell;
}

- (UIMenu *)menuForStandard {
    NSURL *url = self.standardURL;
    if (!url) return nil;
    UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy video URL")
                                         image:[UIImage systemImageNamed:@"video.fill"]
                                    identifier:nil
                                       handler:^(__unused UIAction *a) {
        [UIPasteboard generalPasteboard].string = url.absoluteString;
    }];
    return [UIMenu menuWithTitle:@"" children:@[copy]];
}

- (void)playStandardPreview:(UIButton *)sender {
    NSURL *url = self.standardURL;
    if (!url) return;
    AVPlayerViewController *playerVC = [AVPlayerViewController new];
    playerVC.player = [AVPlayer playerWithURL:url];
    playerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:playerVC animated:YES completion:^{ [playerVC.player play]; }];
}

- (UIMenu *)menuForRow:(NSInteger)row videoRep:(SCIDashRepresentation *)videoRep {
    NSURL *vURL = videoRep.url;
    NSURL *aURL = self.audioRep.url;

    UIAction *copyV = [UIAction actionWithTitle:SCILocalized(@"Copy video URL")
                                          image:[UIImage systemImageNamed:@"video.fill"]
                                     identifier:nil
                                        handler:^(__unused UIAction *a) {
        if (vURL) [UIPasteboard generalPasteboard].string = vURL.absoluteString;
    }];

    NSMutableArray *items = [NSMutableArray arrayWithObject:copyV];
    if (aURL) {
        UIAction *copyA = [UIAction actionWithTitle:SCILocalized(@"Copy audio URL")
                                              image:[UIImage systemImageNamed:@"waveform"]
                                         identifier:nil
                                            handler:^(__unused UIAction *a) {
            [UIPasteboard generalPasteboard].string = aURL.absoluteString;
        }];
        [items addObject:copyA];
    }

    UIAction *copyMPD = [UIAction actionWithTitle:SCILocalized(@"Copy quality info")
                                            image:[UIImage systemImageNamed:@"info.circle"]
                                       identifier:nil
                                          handler:^(__unused UIAction *a) {
        NSString *info = [NSString stringWithFormat:@"%ldp — %ld×%ld — %.1f Mbps",
                          (long)MIN(videoRep.width, videoRep.height),
                          (long)videoRep.width, (long)videoRep.height,
                          videoRep.bandwidth / 1000000.0];
        [UIPasteboard generalPasteboard].string = info;
    }];
    [items addObject:copyMPD];

    return [UIMenu menuWithTitle:@"" children:items];
}

// MARK: - Selection

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if (ip.section == 0) {
            if (self.onPickStandard) self.onPickStandard();
        } else if (ip.section == 1) {
            SCIDashRepresentation *rep = self.videoReps[ip.row];
            if (self.onPickHD) self.onPickHD(rep, self.audioRep);
        } else {
            BOOL isAudio = (ip.section == 2 && [self _hasAudioSection]);
            if (isAudio) {
                [SCIMediaActions downloadAudioOnlyForMedia:self.mediaRef action:self.saveAction];
            } else if (self.photoURL) {
                [SCIMediaActions downloadPhotoOnlyForMedia:self.mediaRef action:self.saveAction];
            }
        }
    }];
}

// MARK: - Preview

- (void)playPreview:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.videoReps.count) return;

    _SCIQualityCell *cell = (_SCIQualityCell *)[self.tableView cellForRowAtIndexPath:
        [NSIndexPath indexPathForRow:idx inSection:1]];
    [cell setLoading:YES];

    SCIDashRepresentation *videoRep = self.videoReps[idx];
    NSURL *videoURL = videoRep.url;
    NSURL *audioURL = self.audioRep.url;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *tmp = NSTemporaryDirectory();
        NSString *vPath = [tmp stringByAppendingPathComponent:
            [NSString stringWithFormat:@"sci_preview_v_%@.mp4", [[NSUUID UUID] UUIDString]]];
        NSString *aPath = [tmp stringByAppendingPathComponent:
            [NSString stringWithFormat:@"sci_preview_a_%@.m4a", [[NSUUID UUID] UUIDString]]];
        NSString *oPath = [tmp stringByAppendingPathComponent:
            [NSString stringWithFormat:@"sci_preview_%@.mp4", [[NSUUID UUID] UUIDString]]];

        NSData *vData = [NSURLConnection sendSynchronousRequest:
            [NSURLRequest requestWithURL:videoURL] returningResponse:nil error:nil];
        if (!vData.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self restorePlayButton:idx]; });
            return;
        }
        [vData writeToFile:vPath atomically:YES];

        NSString *cmd;
        if (audioURL) {
            NSData *aData = [NSURLConnection sendSynchronousRequest:
                [NSURLRequest requestWithURL:audioURL] returningResponse:nil error:nil];
            if (aData.length) {
                [aData writeToFile:aPath atomically:YES];
                cmd = [NSString stringWithFormat:
                    @"-y -hide_banner "
                    @"-analyzeduration 1M -probesize 1M -fflags +genpts "
                    @"-i '%@' -i '%@' -map 0:v:0 -map 1:a:0 "
                    @"-c:a copy -c:v h264_videotoolbox -b:v 8M -realtime 1 -allow_sw 1 "
                    @"-movflags +faststart -shortest '%@'",
                    vPath, aPath, oPath];
            } else {
                cmd = [NSString stringWithFormat:
                    @"-y -hide_banner "
                    @"-analyzeduration 1M -probesize 1M -fflags +genpts "
                    @"-i '%@' -c:v h264_videotoolbox -b:v 8M -realtime 1 -allow_sw 1 "
                    @"-movflags +faststart '%@'",
                    vPath, oPath];
            }
        } else {
            cmd = [NSString stringWithFormat:
                @"-y -hide_banner "
                @"-analyzeduration 1M -probesize 1M -fflags +genpts "
                @"-i '%@' -c:v h264_videotoolbox -b:v 8M -realtime 1 -allow_sw 1 "
                @"-movflags +faststart '%@'",
                vPath, oPath];
        }

        [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
            [[NSFileManager defaultManager] removeItemAtPath:vPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:aPath error:nil];

            if (success && [[NSFileManager defaultManager] fileExistsAtPath:oPath]) {
                AVPlayerViewController *playerVC = [AVPlayerViewController new];
                playerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:oPath]];
                playerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
                [self presentViewController:playerVC animated:YES completion:^{
                    [playerVC.player play];
                }];
            }
            [self restorePlayButton:idx];
        }];
    });
}

- (void)restorePlayButton:(NSInteger)idx {
    dispatch_async(dispatch_get_main_queue(), ^{
        _SCIQualityCell *cell = (_SCIQualityCell *)[self.tableView cellForRowAtIndexPath:
            [NSIndexPath indexPathForRow:idx inSection:1]];
        [cell setLoading:NO];
    });
}

@end


// MARK: - Public API

@implementation SCIQualityPicker

+ (BOOL)pickQualityForMedia:(id)media
                   fromView:(UIView *)sourceView
                     action:(DownloadAction)action
                     picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                   fallback:(void(^)(void))fallback {
    if (!media) { if (fallback) fallback(); return NO; }

    BOOL prefOn = [SCIUtils getBoolPref:@"enhance_download_quality"];
    BOOL ffmpegOK = [SCIFFmpeg isAvailable];
    if (!prefOn || !ffmpegOK) { if (fallback) fallback(); return NO; }

    BOOL isVideo = ([SCIUtils getVideoUrlForMedia:(IGMedia *)media] != nil);
    if (!isVideo) { if (fallback) fallback(); return NO; }

    NSString *manifest = [SCIDashParser dashManifestForMedia:media];
    if (!manifest.length) { if (fallback) fallback(); return NO; }

    NSArray<SCIDashRepresentation *> *allReps = [SCIDashParser parseManifest:manifest];
    NSArray<SCIDashRepresentation *> *videoReps = [SCIDashParser videoRepresentations:allReps];
    SCIDashRepresentation *audioRep = [SCIDashParser bestAudioFromRepresentations:allReps];
    if (!videoReps.count) { if (fallback) fallback(); return NO; }

    NSString *qualityPref = [SCIUtils getStringPref:@"default_video_quality"];
    if (!qualityPref.length) qualityPref = @"always_ask";

    if ([qualityPref isEqualToString:@"always_ask"]) {
        NSURL *standardURL = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
        [self showSheetWithVideoReps:videoReps
                            audioRep:audioRep
                         standardURL:standardURL
                               media:media
                              action:action
                              picked:picked
                            fallback:fallback];
    } else {
        SCIVideoQuality q = SCIVideoQualityHighest;
        if ([qualityPref isEqualToString:@"medium"]) q = SCIVideoQualityMedium;
        else if ([qualityPref isEqualToString:@"low"]) q = SCIVideoQualityLowest;

        SCIDashRepresentation *videoRep = [SCIDashParser representationForQuality:q fromRepresentations:allReps];
        if (picked) picked(videoRep, audioRep);
    }
    return YES;
}

+ (void)showSheetWithVideoReps:(NSArray<SCIDashRepresentation *> *)videoReps
                      audioRep:(SCIDashRepresentation *)audioRep
                   standardURL:(NSURL *)standardURL
                         media:(id)media
                        action:(DownloadAction)action
                        picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                      fallback:(void(^)(void))fallback {
    dispatch_async(dispatch_get_main_queue(), ^{
        _SCIQualitySheetVC *vc = [_SCIQualitySheetVC new];
        vc.videoReps = videoReps;
        vc.audioRep = audioRep;
        vc.standardURL = standardURL;
        vc.mediaRef = media;
        vc.saveAction = action;
        // DASH truth: audio exists iff the manifest parsed an audio rep.
        vc.hasAudio = (audioRep.url != nil);
        vc.photoURL = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
        vc.onPickStandard = fallback;
        vc.onPickHD = picked;

        vc.modalPresentationStyle = UIModalPresentationPageSheet;

        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheetPC = vc.sheetPresentationController;
            sheetPC.detents = @[
                UISheetPresentationControllerDetent.mediumDetent,
                UISheetPresentationControllerDetent.largeDetent,
            ];
            SEL grabberSel = NSSelectorFromString(@"setPrefersGrabberIndicator:");
            if ([sheetPC respondsToSelector:grabberSel]) {
                ((void(*)(id,SEL,BOOL))objc_msgSend)(sheetPC, grabberSel, YES);
            }
            sheetPC.prefersScrollingExpandsWhenScrolledToEdge = YES;
        }

        [topMostController() presentViewController:vc animated:YES completion:nil];
    });
}

@end
