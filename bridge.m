#import "bridge.h"

#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreMedia/CoreMedia.h>
#import <QuartzCore/QuartzCore.h>

@interface PreviewView : NSView
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation PreviewView

// layout подгоняет видеослой под размер области просмотра.
- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.previewLayer.frame = self.bounds;
    [CATransaction commit];
}

@end

@interface ScreenAppDelegate : NSObject <NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSPopUpButton *sourcePopup;
@property(nonatomic, strong) NSPopUpButton *formatPopup;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureDeviceInput *input;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property(nonatomic, strong) AVCaptureDevice *device;
@property(nonatomic, strong) NSArray<AVCaptureDevice *> *devices;
@property(nonatomic, strong) NSArray<AVCaptureDeviceFormat *> *formats;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic) BOOL showedPermissionAlert;
@end

@implementation ScreenAppDelegate

// applicationDidFinishLaunching создаёт интерфейс и запускает поиск capture-устройств.
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.captureQueue = dispatch_queue_create("local.screen.capture", DISPATCH_QUEUE_SERIAL);
    self.session = [[AVCaptureSession alloc] init];
    self.devices = @[];
    self.formats = @[];
    [self buildWindow];
    [self buildMenu];
    [self observeDevices];
    [self requestCameraAccess];
    [NSApp activateIgnoringOtherApps:YES];
}

// buildWindow создаёт минималистичное окно просмотра.
- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1100, 700);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Screen";
    self.window.minSize = NSMakeSize(760, 480);
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.backgroundColor = NSColor.blackColor;
    [self.window center];

    NSView *root = self.window.contentView;
    NSView *controls = [[NSView alloc] init];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:controls];

    PreviewView *preview = [[PreviewView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.wantsLayer = YES;
    preview.layer = [CALayer layer];
    preview.layer.backgroundColor = NSColor.blackColor.CGColor;
    preview.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    preview.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    preview.previewLayer.backgroundColor = NSColor.blackColor.CGColor;
    preview.previewLayer.frame = preview.bounds;
    [preview.layer addSublayer:preview.previewLayer];
    [root addSubview:preview];

    [NSLayoutConstraint activateConstraints:@[
        [controls.topAnchor constraintEqualToAnchor:root.topAnchor],
        [controls.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [controls.heightAnchor constraintEqualToConstant:62],
        [preview.topAnchor constraintEqualToAnchor:controls.bottomAnchor],
        [preview.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [preview.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];

    NSTextField *sourceLabel = [NSTextField labelWithString:@"Источник"];
    NSTextField *formatLabel = [NSTextField labelWithString:@"Качество"];
    sourceLabel.textColor = NSColor.secondaryLabelColor;
    formatLabel.textColor = NSColor.secondaryLabelColor;

    self.sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.sourcePopup.target = self;
    self.sourcePopup.action = @selector(sourceChanged:);
    self.formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.formatPopup.target = self;
    self.formatPopup.action = @selector(formatChanged:);

    self.statusLabel = [NSTextField labelWithString:@"Поиск устройств…"];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSButton *fullScreenButton = [NSButton buttonWithTitle:@"Во весь экран"
        target:self.window action:@selector(toggleFullScreen:)];
    fullScreenButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        sourceLabel, self.sourcePopup, formatLabel, self.formatPopup,
        self.statusLabel, fullScreenButton
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 9;
    stack.edgeInsets = NSEdgeInsetsMake(10, 16, 10, 16);
    [stack setCustomSpacing:18 afterView:self.sourcePopup];
    [stack setCustomSpacing:18 afterView:self.formatPopup];
    [controls addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:controls.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:controls.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:controls.centerYAnchor],
        [self.sourcePopup.widthAnchor constraintGreaterThanOrEqualToConstant:175],
        [self.formatPopup.widthAnchor constraintGreaterThanOrEqualToConstant:175],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:100]
    ]];
    [self.statusLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
        forOrientation:NSLayoutConstraintOrientationHorizontal];

    [self.window makeKeyAndOrderFront:nil];
}

// buildMenu добавляет стандартные команды приложения и полноэкранный режим.
- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Screen"];
    [appMenu addItemWithTitle:@"Выйти из Screen" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"Вид"];
    NSMenuItem *fullScreenItem = [viewMenu addItemWithTitle:@"Во весь экран"
        action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fullScreenItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    viewMenuItem.submenu = viewMenu;
    [mainMenu addItem:viewMenuItem];
    NSApp.mainMenu = mainMenu;
}

// observeDevices подписывается на подключение, отключение и ошибки захвата.
- (void)observeDevices {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(deviceListChanged:)
        name:AVCaptureDeviceWasConnectedNotification object:nil];
    [center addObserver:self selector:@selector(deviceListChanged:)
        name:AVCaptureDeviceWasDisconnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureFailed:)
        name:AVCaptureSessionRuntimeErrorNotification object:self.session];
}

// requestCameraAccess запрашивает разрешение, необходимое для работы с UVC-устройствами.
- (void)requestCameraAccess {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self reloadDevices];
        return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
        [self setStatus:@"Ожидание доступа к камере…" detail:nil];
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self reloadDevices];
                } else {
                    [self showPermissionDenied];
                }
            });
        }];
        return;
    }
    [self showPermissionDenied];
}

// showPermissionDenied объясняет, как разрешить доступ к capture-устройству.
- (void)showPermissionDenied {
    [self setStatus:@"Нет доступа к камере" detail:@"Разрешите доступ в настройках конфиденциальности macOS."];
    self.sourcePopup.enabled = NO;
    self.formatPopup.enabled = NO;
    if (self.showedPermissionAlert) {
        return;
    }
    self.showedPermissionAlert = YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Нужен доступ к камере";
    alert.informativeText = @"macOS считает USB HDMI-capture камерой. Разрешите Screen доступ, чтобы показать видео.";
    [alert addButtonWithTitle:@"Открыть настройки"];
    [alert addButtonWithTitle:@"Позже"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
            [NSWorkspace.sharedWorkspace openURL:url];
        }
    }];
}

// reloadDevices обновляет список внешних видеоустройств и сохраняет текущий выбор.
- (void)reloadDevices {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != AVAuthorizationStatusAuthorized) {
        return;
    }
    NSArray<NSString *> *types;
    if (@available(macOS 14.0, *)) {
        types = @[AVCaptureDeviceTypeExternal];
    } else {
        types = @[@"AVCaptureDeviceTypeExternalUnknown"];
    }
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:types mediaType:AVMediaTypeVideo
        position:AVCaptureDevicePositionUnspecified];
    self.devices = [discovery.devices sortedArrayUsingComparator:^NSComparisonResult(AVCaptureDevice *a, AVCaptureDevice *b) {
        return [a.localizedName localizedCaseInsensitiveCompare:b.localizedName];
    }];

    NSString *selectedID = self.device.uniqueID;
    [self.sourcePopup removeAllItems];
    for (AVCaptureDevice *device in self.devices) {
        [self.sourcePopup addItemWithTitle:device.localizedName];
    }
    self.sourcePopup.enabled = self.devices.count > 0;
    if (self.devices.count == 0) {
        self.device = nil;
        self.formats = @[];
        [self.formatPopup removeAllItems];
        self.formatPopup.enabled = NO;
        [self stopCapture];
        [self setStatus:@"Подключите USB HDMI-capture" detail:nil];
        return;
    }

    NSInteger selectedIndex = 0;
    if (selectedID != nil) {
        NSUInteger preservedIndex = [self.devices indexOfObjectPassingTest:^BOOL(AVCaptureDevice *device, NSUInteger index, BOOL *stop) {
            return [device.uniqueID isEqualToString:selectedID];
        }];
        if (preservedIndex != NSNotFound) {
            selectedIndex = (NSInteger)preservedIndex;
        }
    }
    [self.sourcePopup selectItemAtIndex:selectedIndex];
    [self selectDeviceAtIndex:selectedIndex preferredFormat:nil];
}

// deviceListChanged обновляет устройства после их подключения или отключения.
- (void)deviceListChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadDevices];
    });
}

// sourceChanged включает выбранный пользователем источник видео.
- (void)sourceChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    if (index >= 0 && index < (NSInteger)self.devices.count) {
        [self selectDeviceAtIndex:index preferredFormat:nil];
    }
}

// formatChanged применяет выбранные разрешение и формат кадра.
- (void)formatChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    if (self.device != nil && index >= 0 && index < (NSInteger)self.formats.count) {
        [self startCaptureWithDevice:self.device format:self.formats[index]];
    }
}

// selectDeviceAtIndex настраивает форматы и автоматически выбирает качество около 1080p.
- (void)selectDeviceAtIndex:(NSInteger)index preferredFormat:(AVCaptureDeviceFormat *)preferredFormat {
    self.device = self.devices[index];
    NSMutableArray<AVCaptureDeviceFormat *> *videoFormats = [NSMutableArray array];
    for (AVCaptureDeviceFormat *format in self.device.formats) {
        CMFormatDescriptionRef description = format.formatDescription;
        if (CMFormatDescriptionGetMediaType(description) == kCMMediaType_Video) {
            [videoFormats addObject:format];
        }
    }
    self.formats = [videoFormats sortedArrayUsingComparator:^NSComparisonResult(AVCaptureDeviceFormat *a, AVCaptureDeviceFormat *b) {
        CMVideoDimensions aSize = CMVideoFormatDescriptionGetDimensions(a.formatDescription);
        CMVideoDimensions bSize = CMVideoFormatDescriptionGetDimensions(b.formatDescription);
        double aPixels = (double)aSize.width * aSize.height;
        double bPixels = (double)bSize.width * bSize.height;
        if (aPixels != bPixels) {
            return aPixels > bPixels ? NSOrderedAscending : NSOrderedDescending;
        }
        double aRate = [self maximumFrameRateForFormat:a];
        double bRate = [self maximumFrameRateForFormat:b];
        if (aRate != bRate) {
            return aRate > bRate ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    [self.formatPopup removeAllItems];
    for (AVCaptureDeviceFormat *format in self.formats) {
        [self.formatPopup addItemWithTitle:[self titleForFormat:format]];
    }
    self.formatPopup.enabled = self.formats.count > 0;

    NSInteger selectedFormat = 0;
    double bestDistance = DBL_MAX;
    for (NSInteger i = 0; i < (NSInteger)self.formats.count; i++) {
        AVCaptureDeviceFormat *format = self.formats[i];
        if (preferredFormat != nil && format == preferredFormat) {
            selectedFormat = i;
            break;
        }
        CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        double pixels = (double)size.width * size.height;
        double distance = fabs(pixels - 1920.0 * 1080.0);
        if (distance < bestDistance) {
            bestDistance = distance;
            selectedFormat = i;
        }
    }
    if (self.formats.count > 0) {
        [self.formatPopup selectItemAtIndex:selectedFormat];
        [self startCaptureWithDevice:self.device format:self.formats[selectedFormat]];
    } else {
        [self startCaptureWithDevice:self.device format:nil];
    }
}

// startCaptureWithDevice перестраивает AVFoundation-сессию и начинает воспроизведение.
- (void)startCaptureWithDevice:(AVCaptureDevice *)device format:(AVCaptureDeviceFormat *)format {
    [self setStatus:@"Подключение…" detail:nil];
    dispatch_async(self.captureQueue, ^{
        NSError *error = nil;
        [self.session beginConfiguration];
        if (self.input != nil) {
            [self.session removeInput:self.input];
            self.input = nil;
        }
        if ([self.session canSetSessionPreset:AVCaptureSessionPresetHigh]) {
            self.session.sessionPreset = AVCaptureSessionPresetHigh;
        }

        if (format != nil) {
            if ([device lockForConfiguration:&error]) {
                device.activeFormat = format;
                [device unlockForConfiguration];
            }
        }
        if (error == nil) {
            self.input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        }
        if (self.input != nil && [self.session canAddInput:self.input]) {
            [self.session addInput:self.input];
        } else if (error == nil) {
            self.input = nil;
            error = [NSError errorWithDomain:@"Screen" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"macOS не смогла добавить выбранное видеоустройство."
            }];
        }

        if (self.videoOutput == nil) {
            self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
            self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
            [self.videoOutput setSampleBufferDelegate:self queue:self.captureQueue];
        }
        if (self.session.outputs.count == 0 && [self.session canAddOutput:self.videoOutput]) {
            [self.session addOutput:self.videoOutput];
        }
        [self.session commitConfiguration];

        if (error != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setStatus:@"Не удалось открыть устройство" detail:error.localizedDescription];
            });
            return;
        }

        [self.session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.device.uniqueID isEqualToString:device.uniqueID] && self.session.isRunning) {
                [self setStatus:@"Воспроизведение" detail:device.localizedName];
            }
        });
    });
}

// stopCapture останавливает сессию и освобождает текущее устройство.
- (void)stopCapture {
    dispatch_async(self.captureQueue, ^{
        [self.session beginConfiguration];
        if (self.input != nil) {
            [self.session removeInput:self.input];
            self.input = nil;
        }
        [self.session commitConfiguration];
        if (self.session.isRunning) {
            [self.session stopRunning];
        }
    });
}

// captureFailed сообщает об ошибке воспроизведения без остановки интерфейса.
- (void)captureFailed:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setStatus:@"Ошибка видеозахвата" detail:error.localizedDescription];
    });
}

// setStatus обновляет короткое состояние и подробную подсказку.
- (void)setStatus:(NSString *)status detail:(NSString *)detail {
    self.statusLabel.stringValue = status;
    self.statusLabel.toolTip = detail;
}

// maximumFrameRateForFormat возвращает максимальную частоту кадров формата.
- (double)maximumFrameRateForFormat:(AVCaptureDeviceFormat *)format {
    double maximum = 0;
    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
        maximum = MAX(maximum, range.maxFrameRate);
    }
    return maximum;
}

// titleForFormat создаёт понятное название разрешения и кодека.
- (NSString *)titleForFormat:(AVCaptureDeviceFormat *)format {
    CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    return [NSString stringWithFormat:@"%d × %d · %@", size.width, size.height,
        [self codecNameForFormat:format]];
}

// codecNameForFormat переводит FourCC видеоформата в короткое имя.
- (NSString *)codecNameForFormat:(AVCaptureDeviceFormat *)format {
    FourCharCode codec = CMFormatDescriptionGetMediaSubType(format.formatDescription);
    switch (codec) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return @"NV12";
        case kCVPixelFormatType_422YpCbCr8:
            return @"YUY2";
        case 'mjpg':
        case 'jpeg':
        case 'dmb1':
            return @"MJPEG";
        case 'avc1':
        case 'h264':
            return @"H.264";
        default: {
            char name[5] = {
                (char)((codec >> 24) & 0xff), (char)((codec >> 16) & 0xff),
                (char)((codec >> 8) & 0xff), (char)(codec & 0xff), 0
            };
            return [NSString stringWithUTF8String:name] ?: @"Видео";
        }
    }
}

// captureOutput обслуживает поток кадров и отбрасывает их после показа preview-слоем.
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection {
}

// applicationShouldTerminateAfterLastWindowClosed завершает приложение после закрытия окна.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

// ScreenRun запускает цикл событий нативного macOS-приложения.
void ScreenRun(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        ScreenAppDelegate *delegate = [[ScreenAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
}
