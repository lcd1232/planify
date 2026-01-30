#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>

// GLib/GApplication callback to activate app actions from notification responses
extern void g_action_group_activate_action(void *action_group, const char *action_name, void *parameter);
extern void *g_application_get_default(void);
extern void *g_variant_new_string(const char *string);

// Category identifier for Planify reminder notifications
static NSString *const kPlanifyReminderCategory = @"PLANIFY_REMINDER";

// Action identifiers matching Linux GLib.Notification actions
static NSString *const kActionComplete   = @"COMPLETE";
static NSString *const kActionSnooze10   = @"SNOOZE_10";
static NSString *const kActionSnooze30   = @"SNOOZE_30";
static NSString *const kActionSnooze60   = @"SNOOZE_60";

// ─── Notification delegate to handle user responses ───

@interface PlanifyNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation PlanifyNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {

    NSString *itemId = response.notification.request.content.userInfo[@"item_id"];
    if (!itemId) {
        completionHandler();
        return;
    }

    const char *item_id_str = [itemId UTF8String];
    void *app = g_application_get_default();
    if (!app) {
        NSLog(@"Planify: no GApplication default instance, cannot route notification action");
        completionHandler();
        return;
    }

    NSString *actionId = response.actionIdentifier;

    if ([actionId isEqualToString:kActionComplete]) {
        void *param = g_variant_new_string(item_id_str);
        g_action_group_activate_action(app, "complete", param);
    } else if ([actionId isEqualToString:kActionSnooze10]) {
        void *param = g_variant_new_string(item_id_str);
        g_action_group_activate_action(app, "snooze-10", param);
    } else if ([actionId isEqualToString:kActionSnooze30]) {
        void *param = g_variant_new_string(item_id_str);
        g_action_group_activate_action(app, "snooze-30", param);
    } else if ([actionId isEqualToString:kActionSnooze60]) {
        void *param = g_variant_new_string(item_id_str);
        g_action_group_activate_action(app, "snooze-60", param);
    } else if ([actionId isEqualToString:UNNotificationDefaultActionIdentifier]) {
        // User clicked the notification body → show-item
        void *param = g_variant_new_string(item_id_str);
        g_action_group_activate_action(app, "show-item", param);
    }

    completionHandler();
}

// Show notifications even when app is in foreground
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionSound |
                      UNNotificationPresentationOptionList);
}

@end

// ─── One-time setup ───

static PlanifyNotificationDelegate *_delegate = nil;
static BOOL _authorized = NO;

static void planify_ensure_notification_setup(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

        // Set delegate first so we receive callbacks
        _delegate = [[PlanifyNotificationDelegate alloc] init];
        center.delegate = _delegate;

        // Request authorization
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                                 UNAuthorizationOptionSound |
                                                 UNAuthorizationOptionBadge)
                             completionHandler:^(BOOL granted, NSError *error) {
            _authorized = granted;
            if (error) {
                NSLog(@"Planify: notification authorization error: %@", error);
            } else if (!granted) {
                NSLog(@"Planify: notification authorization denied by user");
            } else {
                NSLog(@"Planify: notification authorization granted");
            }
        }];

        // Register action category matching Linux buttons
        UNNotificationAction *completeAction =
            [UNNotificationAction actionWithIdentifier:kActionComplete
                                                 title:NSLocalizedString(@"Complete", nil)
                                               options:UNNotificationActionOptionNone];

        UNNotificationAction *snooze10Action =
            [UNNotificationAction actionWithIdentifier:kActionSnooze10
                                                 title:NSLocalizedString(@"Snooze for 10 minutes", nil)
                                               options:UNNotificationActionOptionNone];

        UNNotificationAction *snooze30Action =
            [UNNotificationAction actionWithIdentifier:kActionSnooze30
                                                 title:NSLocalizedString(@"Snooze for 30 minutes", nil)
                                               options:UNNotificationActionOptionNone];

        UNNotificationAction *snooze60Action =
            [UNNotificationAction actionWithIdentifier:kActionSnooze60
                                                 title:NSLocalizedString(@"Snooze for 1 hour", nil)
                                               options:UNNotificationActionOptionNone];

        UNNotificationCategory *reminderCategory =
            [UNNotificationCategory categoryWithIdentifier:kPlanifyReminderCategory
                                                   actions:@[completeAction, snooze10Action, snooze30Action, snooze60Action]
                                         intentIdentifiers:@[]
                                                   options:UNNotificationCategoryOptionNone];

        [center setNotificationCategories:[NSSet setWithObject:reminderCategory]];
    });
}

// ─── Public API called from Vala ───

// Call early at app startup to request notification permission before any reminders fire
void planify_init_macos_notifications(void) {
    planify_ensure_notification_setup();
    NSLog(@"Planify: macOS notification system initialized");
}

void planify_send_macos_notification(const char *title, const char *body, const char *item_id) {
    @autoreleasepool {
        planify_ensure_notification_setup();

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];

        if (title) {
            content.title = [NSString stringWithUTF8String:title];
        }
        if (body) {
            content.body = [NSString stringWithUTF8String:body];
        }

        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = kPlanifyReminderCategory;

        if (item_id) {
            content.userInfo = @{@"item_id": [NSString stringWithUTF8String:item_id]};
        }

        // Use item_id as request identifier so we can update/remove it later
        NSString *requestId = item_id
            ? [NSString stringWithUTF8String:item_id]
            : [[NSUUID UUID] UUIDString];

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:requestId
                                                 content:content
                                                 trigger:nil]; // deliver immediately

        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:^(NSError *error) {
                if (error) {
                    NSLog(@"Planify: failed to deliver notification: %@", error);
                } else {
                    NSLog(@"Planify: notification delivered successfully (id=%@)", requestId);
                }
            }];
    }
}
