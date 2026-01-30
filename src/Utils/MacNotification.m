#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

void planify_send_macos_notification(const char *title, const char *body) {
    @autoreleasepool {
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        
        if (title) {
            notification.title = [NSString stringWithUTF8String:title];
        }
        if (body) {
            notification.informativeText = [NSString stringWithUTF8String:body];
        }
        
        notification.soundName = NSUserNotificationDefaultSoundName;
        
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
    }
}
