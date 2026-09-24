package com.example.control.surface

import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * The running focus timer, kept alive and announced natively.
 *
 * While a session or a break counts, a foreground service holds the ongoing
 * notification, which keeps the process alive so the Dart side keeps ticking
 * with the app in the background. The end of a pomodoro or a break is
 * announced twice over: by the service on the minute while the process runs,
 * and by an alarm if it does not. Whichever comes first wins; the other finds
 * the end already announced and stays quiet.
 */
object FocusTimer {

    private const val TAG = "ControlFocus"
    private const val PREFS = "focus_timer"
    private const val KEY_ENDS = "endsAt"
    private const val KEY_DONE_TITLE = "doneTitle"
    private const val KEY_DONE_TEXT = "doneText"
    private const val KEY_ANNOUNCED = "announcedFor"
    private const val ACTION_END = "com.example.control.action.FOCUS_END"
    private const val REQUEST_CODE = 4913

    /** An alarm a minute late is fine for the backup; the service is on time. */
    private const val BACKUP_WINDOW = 60_000L

    internal const val EXTRA_TITLE = "title"
    internal const val EXTRA_TEXT = "text"
    internal const val EXTRA_CLOCK = "clockAt"
    internal const val EXTRA_COUNT_DOWN = "countDown"
    internal const val EXTRA_ENDS = "endsAt"

    /**
     * Shows the timer. [clockAt] zero means nothing is counting (a pause): no
     * service, just the notification. [endsAt] zero means no natural end (a
     * stopwatch); otherwise it is announced with [doneTitle] and [doneText].
     */
    fun show(
        context: Context,
        title: String,
        text: String,
        clockAt: Long,
        countDown: Boolean,
        endsAt: Long,
        doneTitle: String,
        doneText: String,
    ) {
        prefs(context).edit()
            .putLong(KEY_ENDS, endsAt)
            .putString(KEY_DONE_TITLE, doneTitle)
            .putString(KEY_DONE_TEXT, doneText)
            .apply()
        if (endsAt > 0) {
            NotificationAccess.alarmAt(context, endsAt, BACKUP_WINDOW, endIntent(context, endsAt))
        } else {
            cancelAlarm(context)
        }

        if (clockAt <= 0) {
            stopService(context)
            FocusNotification.showRunning(
                context,
                FocusNotification.running(context, title, text, 0, false),
            )
            return
        }
        FocusNotification.cancelDone(context)
        val intent = Intent(context, FocusTimerService::class.java)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_TEXT, text)
            .putExtra(EXTRA_CLOCK, clockAt)
            .putExtra(EXTRA_COUNT_DOWN, countDown)
            .putExtra(EXTRA_ENDS, endsAt)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (refused: Exception) {
            // Android refuses a foreground start from the background. The
            // plain notification still shows the clock, and the alarm still
            // announces the end.
            Log.w(TAG, "Focus service not started; showing the notification only", refused)
            FocusNotification.showRunning(
                context,
                FocusNotification.running(context, title, text, clockAt, countDown),
            )
        }
    }

    /** Stopped by the user: nothing to announce. */
    fun cancel(context: Context) {
        prefs(context).edit().putLong(KEY_ENDS, 0L).apply()
        cancelAlarm(context)
        stopService(context)
        FocusNotification.cancelRunning(context)
    }

    /** The Dart side saw the end first. Announce it now unless already done. */
    fun finish(context: Context) {
        val ends = prefs(context).getLong(KEY_ENDS, 0L)
        if (ends > 0) announce(context, ends) else cancel(context)
    }

    /** The end of [endsAt]'s session or break, announced once. */
    fun announce(context: Context, endsAt: Long) {
        val prefs = prefs(context)
        if (endsAt <= 0 || prefs.getLong(KEY_ENDS, 0L) != endsAt) return
        if (prefs.getLong(KEY_ANNOUNCED, 0L) != endsAt) {
            FocusNotification.done(
                context,
                prefs.getString(KEY_DONE_TITLE, null) ?: "Time is up",
                prefs.getString(KEY_DONE_TEXT, null) ?: "",
            )
            prefs.edit().putLong(KEY_ANNOUNCED, endsAt).apply()
        }
        cancel(context)
    }

    private fun stopService(context: Context) {
        context.stopService(Intent(context, FocusTimerService::class.java))
    }

    private fun cancelAlarm(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        // Extras are not part of intent equality, so any end time matches.
        alarms.cancel(endIntent(context, 0L))
    }

    private fun endIntent(context: Context, endsAt: Long) = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, FocusTimerReceiver::class.java)
            .setAction(ACTION_END)
            .putExtra(EXTRA_ENDS, endsAt),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/**
 * Holds the running notification in the foreground, and announces the end on
 * the minute while the process lives.
 *
 * A special-use foreground service because no standard type fits a timer the
 * user started on purpose. It never runs on its own: only while a session or a
 * break is counting, and it stops the moment that ends.
 */
class FocusTimerService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = FocusNotification.running(
            this,
            intent.getStringExtra(FocusTimer.EXTRA_TITLE) ?: "",
            intent.getStringExtra(FocusTimer.EXTRA_TEXT) ?: "",
            intent.getLongExtra(FocusTimer.EXTRA_CLOCK, 0L),
            intent.getBooleanExtra(FocusTimer.EXTRA_COUNT_DOWN, false),
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    FocusNotification.RUNNING_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(FocusNotification.RUNNING_ID, notification)
            }
        } catch (refused: Exception) {
            Log.w("ControlFocus", "Could not enter the foreground", refused)
            FocusNotification.showRunning(this, notification)
            stopSelf()
            return START_NOT_STICKY
        }

        handler.removeCallbacksAndMessages(null)
        val ends = intent.getLongExtra(FocusTimer.EXTRA_ENDS, 0L)
        if (ends > 0) {
            val delay = (ends - System.currentTimeMillis()).coerceAtLeast(0L)
            handler.postDelayed({ FocusTimer.announce(this, ends) }, delay)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}

class FocusTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        FocusTimer.announce(context, intent.getLongExtra(FocusTimer.EXTRA_ENDS, 0L))
    }
}

/**
 * Alarms are wall-clock times. When the clock, the time zone, or the right to
 * exact alarms changes, every one of them is set again from scratch.
 */
class AlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!handles(intent.action)) return
        runCatching {
            HabitReminders.rescheduleAll(context)
            WeeklyReport.restore(context)
        }.onFailure { Log.e("ControlAlarms", "Could not restore alarms", it) }
    }

    companion object {
        internal fun handles(action: String?): Boolean =
            action == Intent.ACTION_TIME_CHANGED ||
                action == Intent.ACTION_TIMEZONE_CHANGED ||
                action == "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
    }
}
