package com.example.control.surface

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.example.control.MainActivity
import com.example.control.R

/**
 * The focus timer's two notifications.
 *
 * The running one is silent and ongoing, with a chronometer Android runs by
 * itself, so the clock stays live with Flutter asleep. It is also what the
 * foreground service shows. The finished one has its own slot and makes a
 * sound, so ending the service never takes the announcement down with it.
 */
object FocusNotification {

    private const val TAG = "ControlFocus"
    private const val RUNNING_CHANNEL = "focus_timer"
    private const val DONE_CHANNEL = "focus_done"
    const val RUNNING_ID = 4911
    private const val DONE_ID = 4912

    /**
     * [clockAt] is epoch millis: the moment a countdown reaches zero, or the
     * moment a count-up started. Zero shows no clock, as for a paused session.
     */
    fun running(
        context: Context,
        title: String,
        text: String,
        clockAt: Long,
        countDown: Boolean,
    ): Notification {
        ensureChannels(context)
        val builder = builder(context, RUNNING_CHANNEL)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
        if (clockAt > 0) {
            builder
                .setWhen(clockAt)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(countDown)
        } else {
            builder.setShowWhen(false)
        }
        return builder.build()
    }

    /** Posts the running notification without a service, as for a pause. */
    fun showRunning(context: Context, notification: Notification) {
        if (!allowed(context)) return
        post(context, RUNNING_ID, notification)
    }

    fun done(context: Context, title: String, text: String) {
        if (!allowed(context)) return
        ensureChannels(context)
        post(
            context,
            DONE_ID,
            builder(context, DONE_CHANNEL)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_REMINDER)
                .build(),
        )
    }

    fun cancelRunning(context: Context) = manager(context).cancel(RUNNING_ID)

    /** A new session clears the last one's announcement. */
    fun cancelDone(context: Context) = manager(context).cancel(DONE_ID)

    private fun allowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = manager(context)
        manager.createNotificationChannel(
            NotificationChannel(
                RUNNING_CHANNEL,
                context.getString(R.string.focus_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = context.getString(R.string.focus_channel_body) },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                DONE_CHANNEL,
                context.getString(R.string.focus_done_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = context.getString(R.string.focus_done_channel_body) },
        )
    }

    private fun builder(context: Context, channel: String): Notification.Builder {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(open)
    }

    private fun post(context: Context, id: Int, notification: Notification) {
        runCatching { manager(context).notify(id, notification) }
            .onFailure { Log.w(TAG, "Could not post the focus notification", it) }
    }
}
