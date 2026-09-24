package com.example.control.surface

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Whether Control can actually reach the user, and the one place alarms are
 * set so every feature times itself the same way.
 *
 * Reminders, the weekly report and the focus timer all end in a notification.
 * Asking for the permission is not the same as having it, so the state is read
 * back here and shown in Settings rather than assumed.
 */
object NotificationAccess {

    private const val TAG = "ControlNotify"

    fun enabled(context: Context): Boolean =
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .areNotificationsEnabled()

    /** Exact alarms need a user grant from Android 12; before that they are free. */
    fun exactAlarmsRelevant(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    fun canUseExactAlarms(context: Context): Boolean {
        if (!exactAlarmsRelevant()) return true
        return (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .canScheduleExactAlarms()
    }

    fun settingsIntent(context: Context): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
        }

    /** Null below Android 12, where there is nothing to grant. */
    fun exactAlarmIntent(context: Context): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(Uri.parse("package:${context.packageName}"))
        } else {
            null
        }

    /**
     * On the minute when exact alarms are allowed, otherwise within [window].
     * Both wake the device and both fire in Doze, so a reminder never waits for
     * the screen to come on.
     */
    fun alarmAt(context: Context, triggerAt: Long, window: Long, intent: PendingIntent) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (canUseExactAlarms(context)) {
            try {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent)
                return
            } catch (denied: SecurityException) {
                // Revoked between the check and the call; fall through.
                Log.w(TAG, "Exact alarm refused, using a window", denied)
            }
        }
        alarms.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, window, intent)
    }
}
