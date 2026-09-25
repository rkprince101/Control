package com.rkprince.control.surface

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import com.rkprince.control.MainActivity
import com.rkprince.control.R
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/** One reminder for one habit, at one time of day. */
data class HabitReminder(
    val id: String,
    val habitId: String,
    val title: String,
    val body: String,
    /** Minutes after local midnight. */
    val minute: Int,
    /** ISO weekdays, Monday = 1, matching Dart's `DateTime.weekday`. */
    val weekdays: Set<Int>,
    /** yyyymmdd of the last day the habit was finished, or 0. */
    val doneDay: Int,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("habitId", habitId)
        .put("title", title)
        .put("body", body)
        .put("minute", minute)
        .put("weekdays", JSONArray(weekdays.sorted()))
        .put("doneDay", doneDay)

    companion object {
        fun fromJson(json: JSONObject): HabitReminder? = runCatching {
            val days = json.getJSONArray("weekdays")
            HabitReminder(
                id = json.getString("id"),
                habitId = json.getString("habitId"),
                title = json.getString("title"),
                body = json.optString("body", ""),
                minute = json.getInt("minute"),
                weekdays = (0 until days.length()).map { days.getInt(it) }.toSet(),
                doneDay = json.optInt("doneDay", 0),
            )
        }.getOrNull()

        /** From the method channel, where numbers arrive as whatever boxed type. */
        fun fromMap(map: Map<*, *>): HabitReminder? {
            val id = map["id"] as? String ?: return null
            val habitId = map["habitId"] as? String ?: return null
            val minute = (map["minute"] as? Number)?.toInt() ?: return null
            return HabitReminder(
                id = id,
                habitId = habitId,
                title = map["title"] as? String ?: return null,
                body = map["body"] as? String ?: "",
                minute = minute,
                weekdays = (map["weekdays"] as? List<*>)
                    ?.mapNotNull { (it as? Number)?.toInt() }
                    ?.toSet()
                    ?: emptySet(),
                doneDay = (map["doneDay"] as? Number)?.toInt() ?: 0,
            )
        }
    }
}

/**
 * Habit reminders, owned natively because they fire with Flutter asleep.
 *
 * On the minute when the user has allowed exact alarms, within a ten-minute
 * window when not: the permission is optional and offered in Settings, never
 * required. Each alarm schedules only the next occurrence and re-arms itself
 * when it fires, so a changed schedule never leaves a stale repeating alarm
 * behind.
 */
object HabitReminders {

    private const val TAG = "ControlHabits"
    private const val PREFS = "habit_reminders"
    private const val KEY = "reminders"
    private const val CHANNEL_ID = "habit_reminders"
    private const val ACTION = "com.rkprince.control.action.HABIT_REMINDER"
    private const val WINDOW_MILLIS = 10 * 60 * 1000L
    const val EXTRA_ID = "reminderId"

    fun replace(context: Context, reminders: List<HabitReminder>) {
        val wanted = reminders.map { it.id }.toSet()
        read(context).filter { it.id !in wanted }.forEach { cancel(context, it) }
        write(context, reminders)
        reminders.forEach { schedule(context, it) }
    }

    /** Alarms do not survive a reboot or an app update; this puts them back. */
    fun rescheduleAll(context: Context) = read(context).forEach { schedule(context, it) }

    fun fire(context: Context, id: String) {
        val reminder = read(context).firstOrNull { it.id == id } ?: return
        val now = Calendar.getInstance()
        if (reminder.doneDay != dayKey(now) && isoWeekday(now) in reminder.weekdays) {
            post(context, reminder)
        }
        schedule(context, reminder)
    }

    private fun schedule(context: Context, reminder: HabitReminder) {
        val next = nextTrigger(
            reminder.minute,
            reminder.weekdays,
            System.currentTimeMillis(),
            TimeZone.getDefault(),
        ) ?: return
        // On the minute when exact alarms are allowed, within ten otherwise.
        NotificationAccess.alarmAt(context, next, WINDOW_MILLIS, pendingIntent(context, reminder.id))
    }

    private fun cancel(context: Context, reminder: HabitReminder) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(pendingIntent(context, reminder.id))
    }

    /** The id rides in the data URI too, so two reminders never collapse into one intent. */
    private fun pendingIntent(context: Context, id: String) = PendingIntent.getBroadcast(
        context,
        id.hashCode(),
        Intent(context, HabitReminderReceiver::class.java)
            .setAction(ACTION)
            .setData(Uri.parse("control://habit-reminder/${Uri.encode(id)}"))
            .putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun post(context: Context, reminder: HabitReminder) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.habit_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = context.getString(R.string.habit_channel_body)
                },
            )
        }

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        runCatching {
            manager.notify(
                reminder.habitId.hashCode(),
                builder
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle(reminder.title)
                    .setContentText(reminder.body)
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }.onFailure { Log.w(TAG, "Could not post habit reminder", it) }
    }

    private fun read(context: Context): List<HabitReminder> {
        val raw = prefs(context).getString(KEY, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { HabitReminder.fromJson(array.getJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    private fun write(context: Context, reminders: List<HabitReminder>) {
        val array = JSONArray()
        reminders.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(KEY, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * The next moment after [nowMillis] that falls at [minute] on one of
     * [weekdays], or null when there are no days. The clock time is set again
     * on every step so a daylight-saving change cannot drift it by an hour.
     */
    internal fun nextTrigger(
        minute: Int,
        weekdays: Set<Int>,
        nowMillis: Long,
        zone: TimeZone,
    ): Long? {
        if (weekdays.isEmpty() || minute !in 0 until 24 * 60) return null
        val calendar = Calendar.getInstance(zone).apply { timeInMillis = nowMillis }
        repeat(8) {
            calendar.set(Calendar.HOUR_OF_DAY, minute / 60)
            calendar.set(Calendar.MINUTE, minute % 60)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            if (calendar.timeInMillis > nowMillis && isoWeekday(calendar) in weekdays) {
                return calendar.timeInMillis
            }
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        return null
    }

    /** Calendar counts Sunday as 1; Dart and ISO count Monday as 1. */
    internal fun isoWeekday(calendar: Calendar): Int =
        (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1

    internal fun dayKey(calendar: Calendar): Int =
        calendar.get(Calendar.YEAR) * 10000 +
            (calendar.get(Calendar.MONTH) + 1) * 100 +
            calendar.get(Calendar.DAY_OF_MONTH)
}

class HabitReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(HabitReminders.EXTRA_ID) ?: return
        HabitReminders.fire(context, id)
    }
}
