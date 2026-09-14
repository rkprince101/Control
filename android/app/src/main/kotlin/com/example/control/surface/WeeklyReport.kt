package com.example.control.surface

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.control.MainActivity
import com.example.control.R
import java.util.Calendar

/**
 * A weekly summary notification.
 *
 * The one thing that keeps a tool like this installed is being reminded what it
 * did for you. All the data is already on the device; this just says it out
 * loud once a week.
 *
 * Sunday evening on purpose: a week that is over reads as a result, and a week
 * that has just started reads as a demand.
 */
object WeeklyReport {

    private const val CHANNEL_ID = "weekly_report"
    private const val NOTIFICATION_ID = 4901
    private const val REQUEST_CODE = 4902

    fun setEnabled(context: Context, enabled: Boolean) {
        SummaryStore(context).weeklyReportEnabled = enabled
        if (enabled) schedule(context) else cancel(context)
    }

    fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Inexact on purpose: this is a summary, not an alarm clock, and an
        // exact alarm would need a permission users are right to question.
        alarms.setInexactRepeating(
            AlarmManager.RTC,
            nextSundayEvening(),
            AlarmManager.INTERVAL_DAY * 7,
            pendingIntent(context),
        )
    }

    fun cancel(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(pendingIntent(context))
    }

    private fun pendingIntent(context: Context) = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, WeeklyReportReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun nextSundayEvening(): Long = Calendar.getInstance().run {
        set(Calendar.HOUR_OF_DAY, 18)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)

        while (get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY ||
            timeInMillis <= System.currentTimeMillis()
        ) {
            add(Calendar.DAY_OF_YEAR, 1)
        }
        timeInMillis
    }

    fun post(context: Context) {
        val summary = SummaryStore(context).read()
        if (summary.weeklyReport.isEmpty()) return

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.weekly_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = context.getString(R.string.weekly_channel_body)
                },
            )
        }

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        // The platform builder rather than NotificationCompat: this is the only
        // notification in the app, and it is not worth pulling an AndroidX
        // dependency and a version to maintain into a Gradle file that
        // otherwise has none.
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.weekly_title))
                .setContentText(summary.weeklyReport)
                .setStyle(Notification.BigTextStyle().bigText(summary.weeklyReport))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
    }
}

class WeeklyReportReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!SummaryStore(context).weeklyReportEnabled) return
        WeeklyReport.post(context)
    }
}
