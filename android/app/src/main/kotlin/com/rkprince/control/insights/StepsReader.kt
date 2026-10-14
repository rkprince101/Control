package com.rkprince.control.insights

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import com.rkprince.control.enforcement.EnforcementClock
import com.rkprince.control.enforcement.EnforcementStorage
import java.util.Calendar

/**
 * Today's step count, taken from the hardware step counter the platform already
 * runs for every fitness app on the device.
 *
 * `TYPE_STEP_COUNTER` reports steps since the last reboot, not since midnight,
 * so which of them are today's has to be worked out here; see [StepDay]. The
 * counter is kept by the sensor hub in firmware, so it costs no meaningful
 * battery and keeps counting while the app is dead.
 *
 * Readings come from two places. The accessibility service listens all day
 * (see [record]), which is what makes the split at midnight exact and lets a
 * steps rule unlock without opening Control. The Flutter bridge reads once on
 * demand ([readToday]) for when the service is off.
 *
 * The alternative, Health Connect, aggregates across every fitness app and
 * backfills history, but it requires the Health Connect app, a permissions
 * flow, and a published privacy policy. That is the better long-term source and
 * this class is deliberately shaped so it can be swapped in behind the same
 * call.
 */
class StepsReader(context: Context) {

    private val context = context.applicationContext

    /**
     * Device-protected, like the plan: the accessibility service starts before
     * the first unlock after a reboot and records steps from then on.
     */
    private val prefs: SharedPreferences
        get() = EnforcementStorage.preferences(context, PREFS)

    fun hasPermission(): Boolean {
        // Only Android 10 and up gate the step counter behind a permission.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun isAvailable(): Boolean = sensor() != null

    private fun sensor(): Sensor? =
        (context.getSystemService(Context.SENSOR_SERVICE) as SensorManager)
            .getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    /** Steps today from what has already been recorded, without waking the sensor. */
    fun todaySoFar(now: Long = EnforcementClock.now(context)): Int = synchronized(LOCK) {
        load().stepsOn(dayKey(now)).toInt()
    }

    /**
     * Reads the counter once, records it, and reports steps taken today.
     *
     * Registering delivers the current value on most devices; a flush asks the
     * rest for it. If the sensor stays silent anyway (emulators, phones with no
     * step hardware, some sensor hubs that only speak when a step is taken),
     * the last recorded total is reported rather than zero.
     */
    fun readToday(onResult: (Int) -> Unit) {
        val sensor = sensor()
        if (!hasPermission() || sensor == null) {
            onResult(todaySoFar())
            return
        }

        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val handler = Handler(Looper.getMainLooper())
        var settled = false

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (settled) return
                settled = true
                manager.unregisterListener(this)
                onResult(record(event))
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        if (!manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)) {
            onResult(todaySoFar())
            return
        }
        runCatching { manager.flush(listener) }
        handler.postDelayed({
            if (settled) return@postDelayed
            settled = true
            manager.unregisterListener(listener)
            onResult(todaySoFar())
        }, READ_TIMEOUT_MS)
    }

    /**
     * Folds one counter event in and returns today's total.
     *
     * Events can arrive long after the step: a non-wakeup sensor holds them in
     * its FIFO while the phone sleeps. The event's own timestamp decides which
     * day it belongs to, so steps taken at 23:50 still land on that day even
     * when they are delivered at 07:00.
     */
    fun record(event: SensorEvent): Int {
        val raw = event.values.firstOrNull()?.toLong() ?: return todaySoFar()
        val now = EnforcementClock.now(context)
        val ageMillis = (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000L
        // Some older devices stamp events on another time base; distrust an
        // age that is negative or longer than a day rather than misfile it.
        val at = if (ageMillis in 0..DAY_MILLIS) now - ageMillis else now
        return record(raw, at, now)
    }

    private fun record(raw: Long, at: Long, now: Long): Int = synchronized(LOCK) {
        val state = load()
        val next = state.record(
            raw = raw,
            day = dayKey(at),
            previousDay = dayKey(at, daysBack = 1),
            boot = bootCount(),
            bootedOnDay = now - SystemClock.elapsedRealtime() >= startOfDay(at),
        )
        if (next != state) save(next)
        next.stepsOn(dayKey(now)).toInt()
    }

    private fun bootCount(): Int = runCatching {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    }.getOrDefault(-1)

    private fun load(): StepDay = prefs.run {
        StepDay(
            day = getInt(KEY_DAY, -1),
            boot = getInt(KEY_BOOT, -1),
            baseline = getLong(KEY_BASELINE, -1L),
            banked = getLong(KEY_BANKED, 0L),
            lastSeen = getLong(KEY_LAST_SEEN, -1L),
        )
    }

    private fun save(state: StepDay) {
        prefs.edit()
            .putInt(KEY_DAY, state.day)
            .putInt(KEY_BOOT, state.boot)
            .putLong(KEY_BASELINE, state.baseline)
            .putLong(KEY_BANKED, state.banked)
            .putLong(KEY_LAST_SEEN, state.lastSeen)
            .apply()
    }

    companion object {
        private const val PREFS = "control_steps_v2"
        private const val KEY_DAY = "day"
        private const val KEY_BOOT = "boot"
        private const val KEY_BASELINE = "baseline"
        private const val KEY_LAST_SEEN = "lastSeen"
        private const val KEY_BANKED = "banked"
        private const val READ_TIMEOUT_MS = 2500L
        private const val DAY_MILLIS = 24L * 60 * 60 * 1000

        /** The service and the bridge share one process and one record. */
        private val LOCK = Any()

        /** `yyyymmdd` of the local day [millis] falls on, [daysBack] days earlier. */
        fun dayKey(millis: Long, daysBack: Int = 0): Int = Calendar.getInstance().run {
            timeInMillis = millis
            if (daysBack != 0) add(Calendar.DAY_OF_MONTH, -daysBack)
            get(Calendar.YEAR) * 10000 + (get(Calendar.MONTH) + 1) * 100 + get(Calendar.DAY_OF_MONTH)
        }

        fun startOfDay(millis: Long): Long = Calendar.getInstance().run {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            timeInMillis
        }

        /** The next local midnight after [millis]. */
        fun endOfDay(millis: Long): Long = Calendar.getInstance().run {
            timeInMillis = startOfDay(millis)
            add(Calendar.DAY_OF_MONTH, 1)
            timeInMillis
        }
    }
}

/**
 * Which of the since-boot counter's steps belong to one day. Pure, so the
 * day and reboot arithmetic is tested on the JVM.
 *
 * The bug this replaced: the day's baseline used to be the first reading taken
 * after midnight, and readings were only taken when Control was opened. Every
 * step walked before opening the app each day was thrown away, so a steps rule
 * could sit at zero all morning. Now the baseline is the last reading of the
 * day before, which the always-listening service keeps current to the step.
 */
data class StepDay(
    /** `yyyymmdd` the totals belong to, or -1 before the first reading. */
    val day: Int = -1,
    /** Boot count of the readings in [baseline] and [lastSeen]. */
    val boot: Int = -1,
    /** Counter value at the start of [day] in this boot. */
    val baseline: Long = -1L,
    /** Steps counted on [day] in earlier boots, before the counter restarted. */
    val banked: Long = 0L,
    /** The latest counter value seen in this boot. */
    val lastSeen: Long = -1L,
) {
    fun stepsOn(day: Int): Long {
        if (day != this.day) return 0L
        val sinceBaseline = if (lastSeen >= 0 && baseline >= 0) lastSeen - baseline else 0L
        return banked + sinceBaseline.coerceAtLeast(0L)
    }

    /**
     * Folds in a counter reading of [raw] taken on [day].
     *
     * [bootedOnDay] says the current boot started on [day], in which case every
     * step since boot is that day's. When the split cannot be known (a first
     * reading on a phone that has been on since before today, or no reading
     * yesterday to divide at), counting starts from the reading: missing a few
     * steps keeps a rule shut a little longer, while inventing them would open
     * it early.
     */
    fun record(raw: Long, day: Int, previousDay: Int, boot: Int, bootedOnDay: Boolean): StepDay {
        if (raw < 0) return this
        val sameBoot = boot == this.boot && lastSeen >= 0 && raw >= lastSeen

        // A late event from an earlier day, delivered after this one started:
        // every step up to it was taken before today, so today began at least
        // there.
        if (day < this.day) {
            return if (boot == this.boot && baseline >= 0 && raw > baseline && raw <= lastSeen) {
                copy(baseline = raw)
            } else this
        }

        return when {
            !sameBoot -> {
                // The counter restarted: a reboot, or a sensor hub reset.
                val keep = if (this.day == day) stepsOn(day) else 0L
                copy(
                    day = day,
                    boot = boot,
                    baseline = if (bootedOnDay || this.day == day) 0L else raw,
                    banked = keep,
                    lastSeen = raw,
                )
            }
            this.day != day -> copy(
                day = day,
                banked = 0L,
                // Yesterday's last reading is where today began.
                baseline = if (this.day == previousDay) lastSeen else raw,
                lastSeen = raw,
            )
            else -> copy(lastSeen = raw)
        }
    }
}
