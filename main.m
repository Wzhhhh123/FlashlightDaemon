#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>

// Private API for better flashlight control
@interface AVFlashlight : NSObject
+ (BOOL)hasFlashlight;
+ (instancetype)defaultFlashlight;
- (BOOL)setFlashlightLevel:(float)level withError:(NSError **)error;
- (void)turnPowerOff;
@end

@interface FlashlightController : NSObject
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVFlashlight *flashlight;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, assign) BOOL isDeviceLocked;
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
        _isDeviceLocked = NO;
        _currentLevel = 1.0;

        // Try to use private AVFlashlight API first (better control)
        Class flashlightClass = NSClassFromString(@"AVFlashlight");
        if (flashlightClass) {
            SEL hasFlashlightSel = NSSelectorFromString(@"hasFlashlight");
            SEL defaultFlashlightSel = NSSelectorFromString(@"defaultFlashlight");

            if ([flashlightClass respondsToSelector:hasFlashlightSel]) {
                // Use NSInvocation to safely call class method
                NSMethodSignature *sig = [flashlightClass methodSignatureForSelector:hasFlashlightSel];
                if (sig) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
                    [invocation setTarget:flashlightClass];
                    [invocation setSelector:hasFlashlightSel];
                    [invocation invoke];

                    BOOL hasFlash = NO;
                    [invocation getReturnValue:&hasFlash];

                    if (hasFlash && [flashlightClass respondsToSelector:defaultFlashlightSel]) {
                        NSMethodSignature *defaultSig = [flashlightClass methodSignatureForSelector:defaultFlashlightSel];
                        if (defaultSig) {
                            NSInvocation *defaultInvocation = [NSInvocation invocationWithMethodSignature:defaultSig];
                            [defaultInvocation setTarget:flashlightClass];
                            [defaultInvocation setSelector:defaultFlashlightSel];
                            [defaultInvocation invoke];

                            void *result = NULL;
                            [defaultInvocation getReturnValue:&result];
                            _flashlight = (__bridge AVFlashlight *)result;
                            NSLog(@"[FlashlightDaemon] Using AVFlashlight private API");
                        }
                    }
                }
            }
        }

        // Fallback to public AVCaptureDevice API
        if (!_flashlight) {
            _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            if (_device && [_device hasTorch]) {
                NSLog(@"[FlashlightDaemon] Using AVCaptureDevice public API");
            } else {
                NSLog(@"[FlashlightDaemon] ERROR: No flashlight available");
            }
        }
    }
    return self;
}

- (BOOL)turnOn:(float)brightness {
    brightness = MAX(0.01, MIN(1.0, brightness)); // Minimum 0.01 to ensure torch is actually on

    if (_flashlight) {
        NSError *error = nil;
        BOOL success = [_flashlight setFlashlightLevel:brightness withError:&error];
        if (success) {
            _isOn = YES;
            _currentLevel = brightness;
            NSLog(@"[FlashlightDaemon] Flashlight ON at %.2f (AVFlashlight)", brightness);
            return YES;
        } else {
            NSLog(@"[FlashlightDaemon] AVFlashlight error: %@", error);
        }
    }

    if (_device && [_device hasTorch]) {
        NSError *error = nil;

        // Unlock first if already locked
        if (_isDeviceLocked) {
            [_device unlockForConfiguration];
            _isDeviceLocked = NO;
        }

        if ([_device lockForConfiguration:&error]) {
            _isDeviceLocked = YES;
            if ([_device setTorchModeOnWithLevel:brightness error:&error]) {
                _isOn = YES;
                _currentLevel = brightness;
                // Keep device locked while torch is on
                NSLog(@"[FlashlightDaemon] Flashlight ON at %.2f (AVCaptureDevice)", brightness);
                return YES;
            } else {
                [_device unlockForConfiguration];
                _isDeviceLocked = NO;
                NSLog(@"[FlashlightDaemon] setTorchMode error: %@", error);
            }
        } else {
            NSLog(@"[FlashlightDaemon] lockForConfiguration error: %@", error);
        }
    }

    return NO;
}

- (BOOL)turnOff {
    if (_flashlight) {
        [_flashlight turnPowerOff];
        _isOn = NO;
        NSLog(@"[FlashlightDaemon] Flashlight OFF (AVFlashlight)");
        return YES;
    }

    if (_device && [_device hasTorch]) {
        NSError *error = nil;

        // If device is already locked from turnOn
        if (_isDeviceLocked) {
            _device.torchMode = AVCaptureTorchModeOff;
            [_device unlockForConfiguration];
            _isDeviceLocked = NO;
            _isOn = NO;
            NSLog(@"[FlashlightDaemon] Flashlight OFF (AVCaptureDevice - was locked)");
            return YES;
        }

        // If not locked, lock it first
        if ([_device lockForConfiguration:&error]) {
            _device.torchMode = AVCaptureTorchModeOff;
            [_device unlockForConfiguration];
            _isOn = NO;
            NSLog(@"[FlashlightDaemon] Flashlight OFF (AVCaptureDevice)");
            return YES;
        } else {
            NSLog(@"[FlashlightDaemon] turnOff lockForConfiguration error: %@", error);
        }
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
        @"api": _flashlight ? @"AVFlashlight" : @"AVCaptureDevice"
    };
}

@end

// ============ HTTP Server ============

static FlashlightController *g_controller = nil;

const char *HTML_PAGE =
"<!DOCTYPE html><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1'>"
"<title>手电筒远程控制</title><style>"
"*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}"
".container{background:rgba(255,255,255,0.95);border-radius:20px;padding:40px;max-width:400px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.3)}"
"h1{text-align:center;color:#333;margin-bottom:10px;font-size:28px}"
".status{text-align:center;margin:20px 0;padding:15px;border-radius:10px;font-size:16px;font-weight:600}"
".status.on{background:#d4edda;color:#155724}.status.off{background:#f8d7da;color:#721c24}"
".controls{display:flex;flex-direction:column;gap:15px;margin:30px 0}"
"button{padding:18px;font-size:18px;border:none;border-radius:12px;cursor:pointer;font-weight:600;transition:all 0.3s;box-shadow:0 4px 15px rgba(0,0,0,0.2)}"
"button:active{transform:scale(0.95)}"
".btn-on{background:#28a745;color:white}.btn-on:hover{background:#218838}"
".btn-off{background:#dc3545;color:white}.btn-off:hover{background:#c82333}"
".btn-toggle{background:#007bff;color:white;font-size:24px}.btn-toggle:hover{background:#0056b3}"
".slider-container{margin:20px 0}.slider-container label{display:block;margin-bottom:10px;color:#555;font-weight:600}"
"input[type=range]{width:100%;height:8px;border-radius:5px;background:#ddd;outline:none;-webkit-appearance:none}"
"input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:24px;height:24px;border-radius:50%;background:#007bff;cursor:pointer}"
".brightness-value{text-align:center;font-size:20px;font-weight:bold;color:#007bff;margin-top:10px}"
".info{text-align:center;color:#666;font-size:14px;margin-top:20px;padding-top:20px;border-top:1px solid #ddd}"
"</style></head><body><div class='container'>"
"<h1>💡 手电筒控制</h1>"
"<div id='status' class='status off'>状态: 关闭</div>"
"<div class='controls'>"
"<button class='btn-toggle' onclick='toggle()'>🔦 开关</button>"
"<button class='btn-on' onclick='turnOn()'>✅ 开启</button>"
"<button class='btn-off' onclick='turnOff()'>❌ 关闭</button>"
"</div>"
"<div class='slider-container'>"
"<label>亮度控制 <span id='brightness-display'>100%</span></label>"
"<input type='range' id='brightness' min='1' max='100' value='100' oninput='updateBrightness(this.value)'>"
"</div>"
"<div class='info'>API: <span id='api'>-</span><br>延迟: <span id='ping'>-</span>ms</div>"
"</div><script>"
"let currentState=false;async function req(p,d){const t=Date.now();try{const r=await fetch(p,{method:d?'POST':'GET',headers:{'Content-Type':'application/json'},body:d?JSON.stringify(d):null});const j=await r.json();updateUI(j,Date.now()-t);return j}catch(e){console.error(e);return null}}"
"async function turnOn(){await req('/on',{level:parseInt(document.getElementById('brightness').value)/100})}"
"async function turnOff(){await req('/off')}"
"async function toggle(){await req('/toggle',{level:parseInt(document.getElementById('brightness').value)/100})}"
"async function setLevel(l){if(currentState){await req('/level',{level:l})}}"
"function updateBrightness(v){document.getElementById('brightness-display').textContent=v+'%';setLevel(v/100)}"
"function updateUI(d,ms){if(!d)return;currentState=d.isOn;const s=document.getElementById('status');s.textContent='状态: '+(d.isOn?'开启 '+(d.level*100).toFixed(0)+'%':'关闭');s.className='status '+(d.isOn?'on':'off');document.getElementById('api').textContent=d.api||'-';document.getElementById('ping').textContent=ms||'-'}"
"setInterval(()=>req('/status').then(d=>updateUI(d,0)),2000);req('/status');"
"</script></body></html>";

void send_response(int client_fd, int status_code, const char *status_text, const char *content_type, const char *body) {
    char header[1024];
    int body_len = body ? strlen(body) : 0;
    snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s; charset=utf-8\r\n"
        "Content-Length: %d\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Connection: close\r\n"
        "\r\n",
        status_code, status_text, content_type, body_len);

    write(client_fd, header, strlen(header));
    if (body) {
        write(client_fd, body, body_len);
    }
}

void send_json(int client_fd, NSDictionary *dict) {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        send_response(client_fd, 200, "OK", "application/json", [jsonString UTF8String]);
    } else {
        send_response(client_fd, 500, "Internal Server Error", "application/json", "{\"error\":\"JSON serialization failed\"}");
    }
}

void handle_request(int client_fd, const char *request) {
    char method[16], path[256];
    sscanf(request, "%s %s", method, path);

    NSLog(@"[FlashlightDaemon] %s %s", method, path);

    // Parse JSON body if POST
    NSDictionary *jsonBody = nil;
    if (strcmp(method, "POST") == 0) {
        const char *body_start = strstr(request, "\r\n\r\n");
        if (body_start) {
            body_start += 4;
            NSString *bodyStr = [NSString stringWithUTF8String:body_start];
            NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            jsonBody = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
        }
    }

    // Routes
    if (strcmp(path, "/") == 0) {
        send_response(client_fd, 200, "OK", "text/html", HTML_PAGE);
    }
    else if (strcmp(path, "/status") == 0) {
        send_json(client_fd, [g_controller getStatus]);
    }
    else if (strcmp(path, "/on") == 0) {
        float level = jsonBody && jsonBody[@"level"] ? [jsonBody[@"level"] floatValue] : 1.0;
        BOOL success = [g_controller turnOn:level];
        send_json(client_fd, @{@"success": @(success), @"isOn": @(g_controller.isOn), @"level": @(g_controller.currentLevel)});
    }
    else if (strcmp(path, "/off") == 0) {
        BOOL success = [g_controller turnOff];
        send_json(client_fd, @{@"success": @(success), @"isOn": @(g_controller.isOn)});
    }
    else if (strcmp(path, "/toggle") == 0) {
        float level = jsonBody && jsonBody[@"level"] ? [jsonBody[@"level"] floatValue] : 1.0;
        BOOL success = g_controller.isOn ? [g_controller turnOff] : [g_controller turnOn:level];
        send_json(client_fd, @{@"success": @(success), @"isOn": @(g_controller.isOn), @"level": @(g_controller.currentLevel)});
    }
    else if (strcmp(path, "/level") == 0) {
        float level = jsonBody && jsonBody[@"level"] ? [jsonBody[@"level"] floatValue] : 1.0;
        BOOL success = [g_controller setLevel:level];
        send_json(client_fd, @{@"success": @(success), @"level": @(g_controller.currentLevel)});
    }
    else {
        send_response(client_fd, 404, "Not Found", "text/plain", "404 Not Found");
    }
}

void start_server(int port) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        NSLog(@"[FlashlightDaemon] ERROR: socket() failed");
        return;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        NSLog(@"[FlashlightDaemon] ERROR: bind() failed on port %d", port);
        close(server_fd);
        return;
    }

    if (listen(server_fd, 5) < 0) {
        NSLog(@"[FlashlightDaemon] ERROR: listen() failed");
        close(server_fd);
        return;
    }

    // Get local IP address
    char ip_str[INET_ADDRSTRLEN] = "unknown";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;

    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Skip loopback
                if(strcmp(temp_addr->ifa_name, "lo0") != 0 && strcmp(temp_addr->ifa_name, "lo") != 0) {
                    inet_ntop(AF_INET, &((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr, ip_str, INET_ADDRSTRLEN);
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }

    NSLog(@"========================================");
    NSLog(@"[FlashlightDaemon] Server started on port %d", port);
    NSLog(@"[FlashlightDaemon] Open in browser: http://%s:%d", ip_str, port);
    NSLog(@"========================================");

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);

        if (client_fd < 0) continue;

        char buffer[4096] = {0};
        read(client_fd, buffer, sizeof(buffer) - 1);

        handle_request(client_fd, buffer);
        close(client_fd);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSLog(@"[FlashlightDaemon] Starting...");

        g_controller = [[FlashlightController alloc] init];

        int port = 8080;
        if (argc > 1) {
            port = atoi(argv[1]);
        }

        start_server(port);
    }
    return 0;
}
