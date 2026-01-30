/*
 * Copyright © 2023 Alain M. (https://github.com/alainm23/planify)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: Alain M. <alainmh23@gmail.com>
 */

public class Services.Notification : GLib.Object {
    private static Notification ? _instance;
    public static Notification get_default () {
        if (_instance == null) {
            _instance = new Notification ();
        }

        return _instance;
    }

#if MACOS
    [CCode (cname = "planify_init_macos_notifications")]
    extern static void macos_init_notifications ();

    [CCode (cname = "planify_send_macos_notification")]
    extern void macos_send_notification (string title, string body, string item_id);
#endif

    private Gee.HashMap<string, string> reminders;

    construct {
#if MACOS
        // Request notification permission early so it's granted before any reminder fires
        macos_init_notifications ();
#endif
        regresh ();
    }

    public void regresh () {
        if (reminders == null) {
            reminders = new Gee.HashMap<string, string> ();
        } else {
            reminders.clear ();
        }

        foreach (var reminder in Services.Store.instance ().reminders) {
            reminder_added (reminder);
        }

        Services.Store.instance ().reminder_added.connect ((reminder) => {
            reminder_added (reminder);
        });

        Services.Store.instance ().reminder_deleted.connect ((reminder) => {
            if (reminders.has_key (reminder.id)) {
                reminders.unset (reminder.id);
            }
        });
    }

    private void reminder_added (Objects.Reminder reminder) {
        if (reminder.datetime.compare (new GLib.DateTime.now_local ()) <= 0) {
            dispatch_notification (reminder.id, reminder);
            Services.Store.instance ().delete_reminder (reminder);
        } else if (Utils.Datetime.is_same_day (reminder.datetime, new GLib.DateTime.now_local ())) {
            uint interval = (uint) time_until_now (reminder.datetime);
            string uid = "%u-%u".printf (interval, GLib.Random.next_int ());
            reminders.set (reminder.id, uid);

            Timeout.add_seconds (interval, () => {
                queue_reminder_notification (reminder, uid);
                return GLib.Source.REMOVE;
            });
        }
    }

    private TimeSpan time_until_now (GLib.DateTime dt) {
        var now = new DateTime.now_local ();
        return dt.difference (now) / TimeSpan.SECOND;
    }

    private void queue_reminder_notification (Objects.Reminder reminder, string uid) {
        if (reminders.values.contains (uid) == false) {
            return;
        }

        dispatch_notification (uid, reminder);
        Services.Store.instance ().delete_reminder (reminder);
    }

    private void dispatch_notification (string id, Objects.Reminder reminder) {
        #if MACOS
            string title = reminder.item.project.name;
            string body = reminder.item.content;
            macos_send_notification (title, body, reminder.item_id);
        #else
            GLib.Notification notification = build_notification (reminder);
            Planify.instance.send_notification (id, notification);
        #endif
    }

    private GLib.Notification build_notification (Objects.Reminder reminder) {
        var notification = new GLib.Notification (reminder.item.project.name);
        notification.set_body (reminder.item.content);
        notification.set_icon (new ThemedIcon ("io.github.alainm23.planify"));
        notification.set_priority (GLib.NotificationPriority.URGENT);
        notification.set_default_action_and_target_value ("app.show-item", new Variant.string (reminder.item_id));
        notification.add_button_with_target_value (_("Complete"), "app.complete", new Variant.string (reminder.item_id));
        notification.add_button_with_target_value (_("Snooze for 10 minutes"), "app.snooze-10", new Variant.string (reminder.item_id));
        notification.add_button_with_target_value (_("Snooze for 30 minutes"), "app.snooze-30", new Variant.string (reminder.item_id));
        notification.add_button_with_target_value (_("Snooze for 1 hour"), "app.snooze-60", new Variant.string (reminder.item_id));

        return notification;
    }
}
