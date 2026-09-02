#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <unistd.h>

#pragma mark - AVFlashlight private API helpers

static NSString *DumpClassMethods(Class cls) {
    NSMutableString *out = [NSMutableString string];
    if (!cls) {
        [out appendString:@"(class not found)\n"];
        return out;
    }

    unsigned int count = 0;
    Method *classMethods = class_copyMethodList(object_getClass(cls), &count);
    [out appendFormat:@"=== %@ class methods (%u) ===\n", NSStringFromClass(cls), count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  + %@\n", NSStringFromSelector(method_getName(classMethods[i]))];
    }
    free(classMethods);

    count = 0;
    Method *instanceMethods = class_copyMethodList(cls, &count);
    [out appendFormat:@"=== %@ instance methods (%u) ===\n", NSStringFromClass(cls), count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  - %@\n", NSStringFromSelector(method_getName(instanceMethods[i]))];
    }
    free(instanceMethods);

    return out;
}

// AVFlashlight's constructor differs between iOS versions, so probe every known
// spelling instead of assuming one exists.
static id CreateFlashlight(AVCaptureDevice *device, NSMutableString *log) {
    Class cls = NSClassFromString(@"AVFlashlight");
    if (!cls) {
        [log appendString:@"AVFlashlight class not found\n"];
        return nil;
    }

    NSArray *deviceInits = @[@"initWithCaptureDevice:", @"initWithDevice:", @"initWithCaptureDeviceID:"];
    for (NSString *name in deviceInits) {
        SEL sel = NSSelectorFromString(name);
        if (![cls instancesRespondToSelector:sel]) continue;
        @try {
            id instance = [cls alloc];
            NSMethodSignature *sig = [instance methodSignatureForSelector:sel];
            if (!sig) continue;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:instance];
            [inv setSelector:sel];
            [inv setArgument:&device atIndex:2];
            [inv invoke];
            __unsafe_unretained id result = nil;
            [inv getReturnValue:&result];
            if (result) {
                [log appendFormat:@"AVFlashlight created via %@\n", name];
                return result;
            }
        } @catch (NSException *e) {
            [log appendFormat:@"%@ threw %@\n", name, e.reason];
        }
    }

    NSArray *plainFactories = @[@"defaultFlashlight", @"sharedFlashlight"];
    for (NSString *name in plainFactories) {
        SEL sel = NSSelectorFromString(name);
        if (![cls respondsToSelector:sel]) continue;
        @try {
            NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
            if (!sig) continue;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:cls];
            [inv setSelector:sel];
            [inv invoke];
            __unsafe_unretained id result = nil;
            [inv getReturnValue:&result];
            if (result) {
                [log appendFormat:@"AVFlashlight created via +%@\n", name];
                return result;
            }
        } @catch (NSException *e) {
            [log appendFormat:@"+%@ threw %@\n", name, e.reason];
        }
    }

    @try {
        id instance = [[cls alloc] init];
        if (instance) {
            [log appendString:@"AVFlashlight created via plain init\n"];
            return instance;
        }
    } @catch (NSException *e) {
        [log appendFormat:@"plain init threw %@\n", e.reason];
    }

    [log appendString:@"AVFlashlight could not be constructed\n"];
    return nil;
}

static BOOL FlashlightSetLevel(id flashlight, float level, NSError **outError) {
    SEL sel = NSSelectorFromString(@"setFlashlightLevel:withError:");
    if (!flashlight || ![flashlight respondsToSelector:sel]) return NO;

    NSMethodSignature *sig = [flashlight methodSignatureForSelector:sel];
    if (!sig) return NO;

    NSError *error = nil;
    NSError **errorPtr = &error;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:flashlight];
    [inv setSelector:sel];
    [inv setArgument:&level atIndex:2];
    [inv setArgument:&errorPtr atIndex:3];
    [inv invoke];

    BOOL success = NO;
    [inv getReturnValue:&success];
    if (outError) *outError = error;
    return success;
}

static void FlashlightPowerOff(id flashlight) {
    SEL sel = NSSelectorFromString(@"turnPowerOff");
    if (flashlight && [flashlight respondsToSelector:sel]) {
        NSMethodSignature *sig = [flashlight methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:flashlight];
        [inv setSelector:sel];
        [inv invoke];
    }
}

#pragma mark - Flashlight controller

typedef NS_ENUM(NSInteger, FlashlightStrategy) {
    FlashlightStrategyAuto = 0,
    FlashlightStrategyAVFlashlight,  // private API
    FlashlightStrategySession,       // AVCaptureSession + torch
    FlashlightStrategyPlain,         // torch only
};

@interface FlashlightController : NSObject
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) id flashlight;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, assign) BOOL deviceLocked;
@property (nonatomic, assign) float currentLevel;
@property (nonatomic, copy) NSString *activeMethod;
@property (nonatomic, copy) NSString *debugInfo;
- (BOOL)turnOn:(float)brightness strategy:(FlashlightStrategy)strategy;
- (BOOL)turnOff;
- (NSDictionary *)status;
@end

@implementation FlashlightController

- (instancetype)init {
    self = [super init];
    if (self) {
        _isOn = NO;
        _currentLevel = 1.0;
        _activeMethod = @"none";

        NSMutableString *log = [NSMutableString string];

        _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        [log appendFormat:@"device: %@\n", _device];
        [log appendFormat:@"hasTorch: %d, torchAvailable: %d\n",
            _device ? [_device hasTorch] : 0,
            _device ? [_device isTorchAvailable] : 0];

        _flashlight = CreateFlashlight(_device, log);
        [log appendString:DumpClassMethods(NSClassFromString(@"AVFlashlight"))];
        _debugInfo = log;

        NSLog(@"[FlashlightDaemon] %@", log);
    }
    return self;
}

// mediaserverd tends to ignore torch requests from a process with no running
// capture session, which is the most likely reason the plain path reports
// success without the LED lighting up.
- (BOOL)startSession {
    if (_session && _session.isRunning) return YES;
    if (!_device) return NO;

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_device error:&error];
    if (!input) {
        NSLog(@"[FlashlightDaemon] ✗ deviceInput failed: %@", error);
        return NO;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetLow;
    if (![session canAddInput:input]) {
        NSLog(@"[FlashlightDaemon] ✗ canAddInput returned NO");
        return NO;
    }
    [session addInput:input];
    [session startRunning];

    if (!session.isRunning) {
        NSLog(@"[FlashlightDaemon] ✗ session failed to start");
        return NO;
    }

    _session = session;
    NSLog(@"[FlashlightDaemon] ✓ capture session running");
    return YES;
}

- (void)stopSession {
    if (_session.isRunning) [_session stopRunning];
    _session = nil;
}

- (BOOL)applyTorchLevel:(float)brightness {
    if (!_device || ![_device hasTorch]) {
        NSLog(@"[FlashlightDaemon] ✗ no torch on device");
        return NO;
    }

    NSError *error = nil;
    if (!_deviceLocked) {
        if (![_device lockForConfiguration:&error]) {
            NSLog(@"[FlashlightDaemon] ✗ lockForConfiguration failed: %@", error);
            return NO;
        }
        _deviceLocked = YES;
    }

    if (![_device setTorchModeOnWithLevel:brightness error:&error]) {
        NSLog(@"[FlashlightDaemon] ✗ setTorchModeOnWithLevel failed: %@", error);
        return NO;
    }

    // torchActive is the hardware's own answer, unlike the return value above.
    NSLog(@"[FlashlightDaemon] torchActive=%d torchLevel=%.2f", [_device isTorchActive], [_device torchLevel]);
    return YES;
}

- (BOOL)turnOn:(float)brightness strategy:(FlashlightStrategy)strategy {
    brightness = MAX(0.01f, MIN(1.0f, brightness));

    if (strategy == FlashlightStrategyAVFlashlight || strategy == FlashlightStrategyAuto) {
        NSError *error = nil;
        if (_flashlight && FlashlightSetLevel(_flashlight, brightness, &error)) {
            _isOn = YES;
            _currentLevel = brightness;
            _activeMethod = @"AVFlashlight";
            NSLog(@"[FlashlightDaemon] ✓ ON %.2f via AVFlashlight", brightness);
            return YES;
        }
        if (_flashlight) NSLog(@"[FlashlightDaemon] ✗ AVFlashlight failed: %@", error);
        if (strategy == FlashlightStrategyAVFlashlight) return NO;
    }

    if (strategy == FlashlightStrategySession || strategy == FlashlightStrategyAuto) {
        if ([self startSession] && [self applyTorchLevel:brightness]) {
            _isOn = YES;
            _currentLevel = brightness;
            _activeMethod = @"session+torch";
            NSLog(@"[FlashlightDaemon] ✓ ON %.2f via session+torch", brightness);
            return YES;
        }
        if (strategy == FlashlightStrategySession) return NO;
    }

    if (strategy == FlashlightStrategyPlain || strategy == FlashlightStrategyAuto) {
        if ([self applyTorchLevel:brightness]) {
            _isOn = YES;
            _currentLevel = brightness;
            _activeMethod = @"torch";
            NSLog(@"[FlashlightDaemon] ✓ ON %.2f via torch", brightness);
            return YES;
        }
    }

    return NO;
}

- (BOOL)turnOff {
    BOOL ok = NO;

    if (_flashlight) {
        FlashlightPowerOff(_flashlight);
        ok = YES;
    }

    if (_device && [_device hasTorch]) {
        NSError *error = nil;
        if (!_deviceLocked && [_device lockForConfiguration:&error]) {
            _deviceLocked = YES;
        }
        if (_deviceLocked) {
            _device.torchMode = AVCaptureTorchModeOff;
            [_device unlockForConfiguration];
            _deviceLocked = NO;
            ok = YES;
        } else {
            NSLog(@"[FlashlightDaemon] ✗ turnOff lock failed: %@", error);
        }
    }

    [self stopSession];
    _isOn = NO;
    NSLog(@"[FlashlightDaemon] ✓ OFF (torchActive=%d)", _device ? [_device isTorchActive] : 0);
    return ok;
}

- (NSDictionary *)status {
    BOOL torchActive = (_device && [_device hasTorch]) ? [_device isTorchActive] : NO;
    return @{
        @"isOn": @(_isOn),
        @"level": @(_currentLevel),
        @"available": @(_device != nil && [_device hasTorch]),
        @"torchActive": @(torchActive),   // ground truth from the hardware
        @"method": _activeMethod ?: @"none",
        @"hasAVFlashlight": @(_flashlight != nil),
        @"sessionRunning": @(_session.isRunning)
    };
}

@end

#pragma mark - HTTP server

static NSString *const kIndexHTML = @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
"<meta name='viewport' content='width=device-width,initial-scale=1'>"
"<title>手电筒控制</title><style>"
"*{margin:0;padding:0;box-sizing:border-box}"
"body{font-family:-apple-system,sans-serif;background:linear-gradient(135deg,#667eea,#764ba2);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}"
".card{background:rgba(255,255,255,.95);border-radius:24px;padding:32px;max-width:420px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,.3)}"
"h1{font-size:26px;margin-bottom:20px;text-align:center;color:#222}"
".status{text-align:center;margin-bottom:8px;font-size:18px;color:#444}"
".hw{text-align:center;margin-bottom:20px;font-size:13px;color:#888}"
"button{width:100%;padding:18px;font-size:19px;font-weight:600;border:none;border-radius:16px;cursor:pointer;margin-bottom:12px;color:#fff}"
".on{background:#4CAF50}.off{background:#f44336}"
".row{display:flex;gap:8px;margin-top:16px}"
".row button{font-size:14px;padding:12px;background:#667eea;margin:0}"
"input[type=range]{width:100%;height:8px;border-radius:4px;background:#ddd;outline:none;-webkit-appearance:none;margin-top:20px}"
"input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:26px;height:26px;border-radius:50%;background:#667eea}"
".lvl{text-align:center;margin-top:10px;font-size:15px;color:#666}"
"</style></head><body><div class='card'>"
"<h1>🔦 手电筒控制</h1>"
"<div class='status' id='status'>加载中...</div>"
"<div class='hw' id='hw'></div>"
"<button id='toggle' class='on'>切换</button>"
"<input type='range' id='slider' min='1' max='100' value='100'>"
"<div class='lvl'>亮度: <span id='level'>100</span>%</div>"
"<div class='row'>"
"<button data-m='avflashlight'>方法A</button>"
"<button data-m='session'>方法B</button>"
"<button data-m='plain'>方法C</button>"
"</div></div><script>\n"
"function refresh(){\n"
"  fetch('/status').then(function(r){return r.json()}).then(function(d){\n"
"    document.getElementById('status').textContent = d.isOn ? '状态: 已开启' : '状态: 已关闭';\n"
"    document.getElementById('hw').textContent = '硬件 torchActive=' + d.torchActive + ' / 方式: ' + d.method;\n"
"    var b = document.getElementById('toggle');\n"
"    b.textContent = d.isOn ? '关闭' : '开启';\n"
"    b.className = d.isOn ? 'off' : 'on';\n"
"    document.getElementById('level').textContent = Math.round(d.level * 100);\n"
"  }).catch(function(e){console.error(e)});\n"
"}\n"
"function post(path, body){\n"
"  return fetch(path, {method:'POST', body: body === undefined ? '' : String(body)}).then(refresh);\n"
"}\n"
"document.getElementById('toggle').addEventListener('click', function(){ post('/toggle') });\n"
"document.getElementById('slider').addEventListener('input', function(){\n"
"  document.getElementById('level').textContent = this.value;\n"
"  post('/level', this.value / 100);\n"
"});\n"
"var btns = document.querySelectorAll('[data-m]');\n"
"for (var i = 0; i < btns.length; i++) {\n"
"  btns[i].addEventListener('click', function(){\n"
"    post('/on/' + this.getAttribute('data-m'), document.getElementById('slider').value / 100);\n"
"  });\n"
"}\n"
"refresh(); setInterval(refresh, 2000);\n"
"</script></body></html>";

@interface HTTPServer : NSObject
@property (nonatomic, strong) FlashlightController *controller;
@end

@implementation HTTPServer

- (instancetype)init {
    self = [super init];
    if (self) _controller = [[FlashlightController alloc] init];
    return self;
}

- (NSString *)localIPAddress {
    struct ifaddrs *interfaces = NULL;
    NSString *address = @"0.0.0.0";

    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *addr = interfaces; addr != NULL; addr = addr->ifa_next) {
            if (!addr->ifa_addr || addr->ifa_addr->sa_family != AF_INET) continue;
            NSString *name = [NSString stringWithUTF8String:addr->ifa_name];
            if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
                char buf[INET_ADDRSTRLEN] = {0};
                inet_ntop(AF_INET, &((struct sockaddr_in *)addr->ifa_addr)->sin_addr, buf, sizeof(buf));
                address = [NSString stringWithUTF8String:buf];
                break;
            }
        }
        freeifaddrs(interfaces);
    }
    return address;
}

// Content-Length must count UTF-8 bytes, not UTF-16 characters, or any page
// containing non-ASCII text gets truncated mid-script by the client.
- (void)sendResponse:(NSString *)body contentType:(NSString *)contentType to:(int)clientSocket {
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: %@\r\n"
        @"Content-Length: %lu\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Cache-Control: no-store\r\n"
        @"Connection: close\r\n\r\n",
        contentType, (unsigned long)bodyData.length];

    NSMutableData *out = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [out appendData:bodyData];

    const uint8_t *bytes = out.bytes;
    NSUInteger remaining = out.length;
    while (remaining > 0) {
        ssize_t written = send(clientSocket, bytes, remaining, 0);
        if (written <= 0) break;
        bytes += written;
        remaining -= written;
    }
}

- (void)sendJSON:(NSDictionary *)dict to:(int)clientSocket {
    NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    NSString *body = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    [self sendResponse:body contentType:@"application/json; charset=utf-8" to:clientSocket];
}

- (void)handleClient:(int)clientSocket {
    char buffer[8192];
    ssize_t received = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
    if (received <= 0) {
        close(clientSocket);
        return;
    }
    buffer[received] = '\0';

    NSString *request = [[NSString alloc] initWithBytes:buffer length:received encoding:NSUTF8StringEncoding];
    if (!request) {
        request = [[NSString alloc] initWithBytes:buffer length:received encoding:NSASCIIStringEncoding];
    }

    NSString *requestLine = [[request componentsSeparatedByString:@"\r\n"] firstObject] ?: @"";
    NSArray *parts = [requestLine componentsSeparatedByString:@" "];
    NSString *path = parts.count > 1 ? parts[1] : @"/";
    NSLog(@"[FlashlightDaemon] %@", requestLine);

    NSString *body = @"";
    NSRange split = [request rangeOfString:@"\r\n\r\n"];
    if (split.location != NSNotFound) {
        body = [request substringFromIndex:NSMaxRange(split)];
    }

    FlashlightController *c = _controller;

    if ([path isEqualToString:@"/"]) {
        [self sendResponse:kIndexHTML contentType:@"text/html; charset=utf-8" to:clientSocket];
    } else if ([path isEqualToString:@"/status"]) {
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/debug"]) {
        [self sendResponse:c.debugInfo contentType:@"text/plain; charset=utf-8" to:clientSocket];
    } else if ([path isEqualToString:@"/on"]) {
        float level = body.length ? [body floatValue] : c.currentLevel;
        [c turnOn:level strategy:FlashlightStrategyAuto];
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/on/avflashlight"]) {
        [c turnOn:(body.length ? [body floatValue] : c.currentLevel) strategy:FlashlightStrategyAVFlashlight];
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/on/session"]) {
        [c turnOn:(body.length ? [body floatValue] : c.currentLevel) strategy:FlashlightStrategySession];
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/on/plain"]) {
        [c turnOn:(body.length ? [body floatValue] : c.currentLevel) strategy:FlashlightStrategyPlain];
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/off"]) {
        [c turnOff];
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/toggle"]) {
        if (c.isOn) {
            [c turnOff];
        } else {
            [c turnOn:c.currentLevel strategy:FlashlightStrategyAuto];
        }
        [self sendJSON:[c status] to:clientSocket];
    } else if ([path isEqualToString:@"/level"]) {
        [c turnOn:[body floatValue] strategy:FlashlightStrategyAuto];
        [self sendJSON:[c status] to:clientSocket];
    } else {
        [self sendResponse:@"404 Not Found" contentType:@"text/plain" to:clientSocket];
    }

    close(clientSocket);
}

- (void)startOnPort:(int)port {
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        NSLog(@"[FlashlightDaemon] ✗ socket() failed");
        return;
    }

    int opt = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in serverAddr = {0};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(port);

    if (bind(serverSocket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[FlashlightDaemon] ✗ bind() failed on port %d", port);
        close(serverSocket);
        return;
    }

    if (listen(serverSocket, 8) < 0) {
        NSLog(@"[FlashlightDaemon] ✗ listen() failed");
        close(serverSocket);
        return;
    }

    NSLog(@"========================================");
    NSLog(@"[FlashlightDaemon] Server started on port %d", port);
    NSLog(@"[FlashlightDaemon] Open in browser: http://%@:%d", [self localIPAddress], port);
    NSLog(@"[FlashlightDaemon] Debug dump:      http://%@:%d/debug", [self localIPAddress], port);
    NSLog(@"========================================");

    while (YES) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSocket = accept(serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientSocket < 0) continue;

        @autoreleasepool {
            [self handleClient:clientSocket];
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[FlashlightDaemon] Starting...");
        int port = (argc > 1) ? atoi(argv[1]) : 8080;
        HTTPServer *server = [[HTTPServer alloc] init];
        [server startOnPort:port];
    }
    return 0;
}
