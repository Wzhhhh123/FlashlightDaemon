#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>

// Private API for flashlight control
@interface AVFlashlight : NSObject
+ (BOOL)hasFlashlight;
+ (instancetype)flashlightWithDevice:(AVCaptureDevice *)device;
- (instancetype)initWithDevice:(AVCaptureDevice *)device;
- (BOOL)setFlashlightLevel:(float)level withError:(NSError **)error;
- (void)turnPowerOff;
- (float)flashlightLevel;
- (BOOL)isAvailable;
@end

@interface FlashlightController : NSObject
@property (nonatomic, strong) AVFlashlight *flashlight;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, assign) float currentLevel;
- (BOOL)turnOn:(float)brightness;
- (BOOL)turnOff;
- (BOOL)setLevel:(float)level;
- (NSDictionary *)getStatus;
@end

@implementation FlashlightController

- (instancetype)init {
    self = [super init];
    if (self) {
        _isOn = NO;
        _currentLevel = 1.0;

        // Use AVFlashlight private API - same as Control Center
        Class flashlightClass = NSClassFromString(@"AVFlashlight");
        NSLog(@"[FlashlightDaemon] AVFlashlight class: %@", flashlightClass);

        if (flashlightClass) {
            // Check if flashlight is available
            SEL hasFlashlightSel = NSSelectorFromString(@"hasFlashlight");
            NSLog(@"[FlashlightDaemon] respondsToSelector(hasFlashlight): %d", [flashlightClass respondsToSelector:hasFlashlightSel]);

            if ([flashlightClass respondsToSelector:hasFlashlightSel]) {
                NSMethodSignature *sig = [flashlightClass methodSignatureForSelector:hasFlashlightSel];
                NSLog(@"[FlashlightDaemon] hasFlashlight signature: %@", sig);

                if (sig) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
                    [invocation setTarget:flashlightClass];
                    [invocation setSelector:hasFlashlightSel];
                    [invocation invoke];

                    BOOL hasFlash = NO;
                    [invocation getReturnValue:&hasFlash];
                    NSLog(@"[FlashlightDaemon] hasFlashlight returned: %d", hasFlash);

                    if (hasFlash) {
                        // Get AVCaptureDevice
                        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                        NSLog(@"[FlashlightDaemon] AVCaptureDevice: %@", device);

                        if (device) {
                            // Try flashlightWithDevice: method
                            SEL flashlightWithDeviceSel = NSSelectorFromString(@"flashlightWithDevice:");
                            NSLog(@"[FlashlightDaemon] respondsToSelector(flashlightWithDevice:): %d", [flashlightClass respondsToSelector:flashlightWithDeviceSel]);

                            if ([flashlightClass respondsToSelector:flashlightWithDeviceSel]) {
                                NSMethodSignature *flashlightSig = [flashlightClass methodSignatureForSelector:flashlightWithDeviceSel];
                                NSLog(@"[FlashlightDaemon] flashlightWithDevice: signature: %@", flashlightSig);

                                if (flashlightSig) {
                                    NSInvocation *flashlightInvocation = [NSInvocation invocationWithMethodSignature:flashlightSig];
                                    [flashlightInvocation setTarget:flashlightClass];
                                    [flashlightInvocation setSelector:flashlightWithDeviceSel];
                                    [flashlightInvocation setArgument:&device atIndex:2];
                                    [flashlightInvocation invoke];

                                    __unsafe_unretained id result = nil;
                                    [flashlightInvocation getReturnValue:&result];
                                    _flashlight = result;

                                    NSLog(@"[FlashlightDaemon] flashlightWithDevice: returned: %@", _flashlight);

                                    if (_flashlight) {
                                        NSLog(@"[FlashlightDaemon] ✓ Using AVFlashlight private API (Control Center method)");
                                    } else {
                                        NSLog(@"[FlashlightDaemon] ✗ flashlightWithDevice: returned nil");
                                    }
                                }
                            } else {
                                NSLog(@"[FlashlightDaemon] ✗ flashlightWithDevice: method not found");
                            }
                        } else {
                            NSLog(@"[FlashlightDaemon] ✗ Could not get AVCaptureDevice");
                        }
                    } else {
                        NSLog(@"[FlashlightDaemon] ✗ hasFlashlight returned NO");
                    }
                }
            }
        } else {
            NSLog(@"[FlashlightDaemon] ✗ AVFlashlight class not found");
        }

        if (!_flashlight) {
            NSLog(@"[FlashlightDaemon] ✗ ERROR: Could not initialize flashlight control");
        }
    }
    return self;
}

- (BOOL)turnOn:(float)brightness {
    brightness = MAX(0.01, MIN(1.0, brightness));

    if (!_flashlight) {
        NSLog(@"[FlashlightDaemon] ✗ No flashlight available");
        return NO;
    }

    NSError *error = nil;
    SEL setLevelSel = NSSelectorFromString(@"setFlashlightLevel:withError:");

    if ([_flashlight respondsToSelector:setLevelSel]) {
        NSMethodSignature *sig = [_flashlight methodSignatureForSelector:setLevelSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setTarget:_flashlight];
        [invocation setSelector:setLevelSel];
        [invocation setArgument:&brightness atIndex:2];
        [invocation setArgument:&error atIndex:3];
        [invocation invoke];

        BOOL success = NO;
        [invocation getReturnValue:&success];

        if (success) {
            _isOn = YES;
            _currentLevel = brightness;
            NSLog(@"[FlashlightDaemon] ✓ Flashlight ON at %.2f", brightness);
            return YES;
        } else {
            NSLog(@"[FlashlightDaemon] ✗ setFlashlightLevel error: %@", error);
        }
    }

    return NO;
}

- (BOOL)turnOff {
    if (!_flashlight) {
        return NO;
    }

    SEL turnOffSel = NSSelectorFromString(@"turnPowerOff");
    if ([_flashlight respondsToSelector:turnOffSel]) {
        NSMethodSignature *sig = [_flashlight methodSignatureForSelector:turnOffSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setTarget:_flashlight];
        [invocation setSelector:turnOffSel];
        [invocation invoke];

        _isOn = NO;
        NSLog(@"[FlashlightDaemon] ✓ Flashlight OFF");
        return YES;
    }

    return NO;
}

- (BOOL)setLevel:(float)level {
    if (!_isOn) {
        return [self turnOn:level];
    }
    return [self turnOn:level];
}

- (NSDictionary *)getStatus {
    return @{
        @"isOn": @(_isOn),
        @"level": @(_currentLevel),
        @"available": @(_flashlight != nil)
    };
}

@end

// HTTP Server
@interface HTTPServer : NSObject
@property (nonatomic, strong) FlashlightController *controller;
@property (nonatomic, assign) int serverSocket;
- (void)start;
- (void)handleClient:(int)clientSocket;
@end

@implementation HTTPServer

- (instancetype)init {
    self = [super init];
    if (self) {
        _controller = [[FlashlightController alloc] init];
    }
    return self;
}

- (NSString *)getLocalIPAddress {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSString *address = @"0.0.0.0";

    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *ifname = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if([ifname isEqualToString:@"en0"] || [ifname isEqualToString:@"en1"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

- (void)start {
    _serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_serverSocket < 0) {
        NSLog(@"[FlashlightDaemon] ✗ Failed to create socket");
        return;
    }

    int opt = 1;
    setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in serverAddr;
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(8080);

    if (bind(_serverSocket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[FlashlightDaemon] ✗ Failed to bind socket");
        close(_serverSocket);
        return;
    }

    if (listen(_serverSocket, 5) < 0) {
        NSLog(@"[FlashlightDaemon] ✗ Failed to listen");
        close(_serverSocket);
        return;
    }

    NSString *ipAddress = [self getLocalIPAddress];
    NSLog(@"========================================");
    NSLog(@"[FlashlightDaemon] Server started on port 8080");
    NSLog(@"[FlashlightDaemon] Open in browser: http://%@:8080", ipAddress);
    NSLog(@"========================================");

    while (YES) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSocket = accept(_serverSocket, (struct sockaddr *)&clientAddr, &clientLen);

        if (clientSocket < 0) {
            continue;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSocket];
        });
    }
}

- (void)handleClient:(int)clientSocket {
    char buffer[4096];
    ssize_t received = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);

    if (received <= 0) {
        close(clientSocket);
        return;
    }

    buffer[received] = '\0';
    NSString *request = [NSString stringWithUTF8String:buffer];

    NSLog(@"[FlashlightDaemon] %@", [request componentsSeparatedByString:@"\r\n"][0]);

    NSString *response = nil;
    NSString *contentType = @"text/plain";

    if ([request hasPrefix:@"GET / HTTP"]) {
        contentType = @"text/html; charset=utf-8";
        response = @"<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>手电筒控制</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}. container{background:rgba(255,255,255,0.95);border-radius:24px;padding:40px;max-width:400px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.3)}h1{font-size:28px;margin-bottom:30px;text-align:center;color:#333}.status{text-align:center;margin-bottom:30px;font-size:18px;color:#666}.toggle-btn{width:100%;padding:20px;font-size:20px;font-weight:600;border:none;border-radius:16px;cursor:pointer;transition:all 0.3s;margin-bottom:20px}.btn-on{background:#4CAF50;color:white}.btn-on:active{background:#45a049}.btn-off{background:#f44336;color:white}.btn-off:active{background:#da190b}.slider-container{margin-top:20px}input[type=range]{width:100%;height:8px;border-radius:4px;background:#ddd;outline:none;-webkit-appearance:none}input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:24px;height:24px;border-radius:50%;background:#667eea;cursor:pointer}.level-display{text-align:center;margin-top:10px;font-size:16px;color:#666}</style></head><body><div class='container'><h1>🔦 手电筒控制</h1><div class='status' id='status'>加载中...</div><button id='toggle' class='toggle-btn' onclick='toggle()'>切换</button><div class='slider-container'><input type='range' id='slider' min='1' max='100' value='100' oninput='setLevel(this.value)'><div class='level-display'>亮度: <span id='level'>100</span>%</div></div></div><script>function updateStatus(){fetch('/status').then(r=>r.json()).then(d=>{document.getElementById('status').textContent=d.isOn?'状态: 已开启':'状态: 已关闭';document.getElementById('toggle').textContent=d.isOn?'关闭':'开启';document.getElementById('toggle').className='toggle-btn '+(d.isOn?'btn-off':'btn-on');document.getElementById('level').textContent=Math.round(d.level*100)}).catch(e=>console.error(e))}function toggle(){fetch('/toggle',{method:'POST'}).then(()=>updateStatus())}function setLevel(v){fetch('/level',{method:'POST',body:v/100}).then(()=>updateStatus())}updateStatus();setInterval(updateStatus,2000)</script></body></html>";
    } else if ([request hasPrefix:@"GET /status"]) {
        contentType = @"application/json";
        NSDictionary *status = [_controller getStatus];
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
        response = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    } else if ([request hasPrefix:@"POST /on"]) {
        [_controller turnOn:_controller.currentLevel];
        response = @"OK";
    } else if ([request hasPrefix:@"POST /off"]) {
        [_controller turnOff];
        response = @"OK";
    } else if ([request hasPrefix:@"POST /toggle"]) {
        if (_controller.isOn) {
            [_controller turnOff];
        } else {
            [_controller turnOn:_controller.currentLevel];
        }
        response = @"OK";
    } else if ([request hasPrefix:@"POST /level"]) {
        NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
        NSString *body = [lines lastObject];
        float level = [body floatValue];
        [_controller setLevel:level];
        response = @"OK";
    } else {
        response = @"404 Not Found";
    }

    NSString *httpResponse = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: %@\r\n"
        @"Content-Length: %lu\r\n"
        @"Connection: close\r\n"
        @"\r\n%@",
        contentType, (unsigned long)[response length], response];

    send(clientSocket, [httpResponse UTF8String], [httpResponse length], 0);
    close(clientSocket);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[FlashlightDaemon] Starting...");

        HTTPServer *server = [[HTTPServer alloc] init];
        [server start];
    }
    return 0;
}
