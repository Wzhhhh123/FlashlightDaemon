#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

int main() {
    @autoreleasepool {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

        if (!device) {
            NSLog(@"No device found");
            return 1;
        }

        NSLog(@"Device: %@", device);
        NSLog(@"Has torch: %d", [device hasTorch]);
        NSLog(@"Torch available: %d", [device isTorchAvailable]);
        NSLog(@"Torch active: %d", [device isTorchActive]);

        NSError *error = nil;
        if ([device lockForConfiguration:&error]) {
            NSLog(@"Locked for configuration");

            // Try to turn on torch
            if ([device isTorchModeSupported:AVCaptureTorchModeOn]) {
                NSLog(@"Torch mode ON is supported");

                BOOL success = [device setTorchModeOnWithLevel:1.0 error:&error];
                if (success) {
                    NSLog(@"✓ Torch ON successful!");
                    NSLog(@"Torch active now: %d", [device isTorchActive]);

                    sleep(3);

                    device.torchMode = AVCaptureTorchModeOff;
                    NSLog(@"✓ Torch OFF");
                } else {
                    NSLog(@"✗ Failed to turn on: %@", error);
                }
            }

            [device unlockForConfiguration];
        } else {
            NSLog(@"✗ Failed to lock: %@", error);
        }
    }
    return 0;
}
