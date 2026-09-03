#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

int main() {
    @autoreleasepool {
        NSLog(@"=== AVFlashlight API Test ===");

        // Get AVFlashlight class
        Class flashlightClass = NSClassFromString(@"AVFlashlight");
        if (!flashlightClass) {
            NSLog(@"✗ AVFlashlight class not found");
            return 1;
        }
        NSLog(@"✓ AVFlashlight class found: %@", flashlightClass);

        // List all class methods
        NSLog(@"\n=== Class Methods ===");
        unsigned int methodCount;
        Method *methods = class_copyMethodList(object_getClass(flashlightClass), &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL selector = method_getName(methods[i]);
            NSLog(@"  + %@", NSStringFromSelector(selector));
        }
        free(methods);

        // List all instance methods
        NSLog(@"\n=== Instance Methods ===");
        Method *instanceMethods = class_copyMethodList(flashlightClass, &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL selector = method_getName(instanceMethods[i]);
            NSLog(@"  - %@", NSStringFromSelector(selector));
        }
        free(instanceMethods);

        // Try to get AVCaptureDevice
        NSLog(@"\n=== Testing AVCaptureDevice ===");
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        NSLog(@"Device: %@", device);
        NSLog(@"Has torch: %d", [device hasTorch]);

        // Try different initialization methods
        NSLog(@"\n=== Trying Different Init Methods ===");

        // Method 1: alloc + init
        SEL initSel = NSSelectorFromString(@"init");
        if ([flashlightClass instancesRespondToSelector:initSel]) {
            NSLog(@"✓ Trying [[AVFlashlight alloc] init]");
            id flashlight = [[flashlightClass alloc] init];
            NSLog(@"  Result: %@", flashlight);
        }

        // Method 2: alloc + initWithDevice:
        SEL initWithDeviceSel = NSSelectorFromString(@"initWithDevice:");
        if ([flashlightClass instancesRespondToSelector:initWithDeviceSel]) {
            NSLog(@"✓ Trying [[AVFlashlight alloc] initWithDevice:device]");
            id flashlight = [[flashlightClass alloc] performSelector:initWithDeviceSel withObject:device];
            NSLog(@"  Result: %@", flashlight);

            if (flashlight) {
                // Try to turn on
                NSLog(@"\n=== Trying to Turn On ===");
                SEL setLevelSel = NSSelectorFromString(@"setFlashlightLevel:withError:");
                if ([flashlight respondsToSelector:setLevelSel]) {
                    NSError *error = nil;
                    NSMethodSignature *sig = [flashlight methodSignatureForSelector:setLevelSel];
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
                    [invocation setTarget:flashlight];
                    [invocation setSelector:setLevelSel];
                    float level = 1.0;
                    [invocation setArgument:&level atIndex:2];
                    [invocation setArgument:&error atIndex:3];
                    [invocation invoke];

                    BOOL success = NO;
                    [invocation getReturnValue:&success];

                    if (success) {
                        NSLog(@"✓✓✓ SUCCESS! Flashlight is ON!");
                        sleep(2);

                        // Turn off
                        SEL turnOffSel = NSSelectorFromString(@"turnPowerOff");
                        if ([flashlight respondsToSelector:turnOffSel]) {
                            [flashlight performSelector:turnOffSel];
                            NSLog(@"✓ Flashlight turned OFF");
                        }
                    } else {
                        NSLog(@"✗ Failed to turn on: %@", error);
                    }
                }
            }
        }

        NSLog(@"\n=== Test Complete ===");
    }
    return 0;
}
