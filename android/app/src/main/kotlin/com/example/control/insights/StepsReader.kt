package com.example.control.insights

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.Calendar

/**
 * Today's step count, taken from the hardware step counter the platform already
 * runs for every fitness app on the device.
 *
 * `TYPE_STEP_COUNTER` reports steps since the last reboot, not since midnight,
 * so a daily baseline is kept here and subtracted. The counter is maintained by
 * the sensor hub in firmware, which is why this costs no meaningful battery and
 * keeps counting while the app is dead.
 *
 * The alternative, Health Connect, aggregates across every fitness app and
 * backfills history, but it requires the Health Connect app, a permissions
 * flow, and a published privacy policy. That is the better long-term source and
 * this class is deliberately shaped so it can be swapped in behind the same
 * call.
 */
class StepsReader(private val context: Context) {

    private val prefs =
        context.getSharedPreferences("control_steps", Context.MODE_PRIVATE)

    fun hasPermission(): Boolean {
        // Only Android 10 and up gate the step counter behind a permission.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun isAvailable(): Boolean {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        return manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
    }

    /**
     * Reads the counter once and reports steps taken today.
     *
     * The sensor delivers its current value on registration, so this is a
     * single callback rather than a subscription. Reports 0 if the sensor stays
     * silent, which happens on emulators and on devices with no step hardware.
     */
    fun readToday(onResult: (Int) -> Unit) {
        if (!hasPermission() || !isAvailable()) {
            onResult(stepsFromRaw(null))
            return
        }

        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        val handler = Handler(Looper.getMainLooper())
        var settled = false

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (settled) return
                settled = true
                manager.unregisterListener(this)
                onResult(stepsFromRaw(event.values.firstOrNull()?.toLong()))
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
        handler.postDelayed({
            if (settled) return@postDelayed
            settled = true
            manager.unregisterListener(listener)
            onResult(stepsFromRaw(null))
        }, READ_TIMEOUT_MS)
    }

    /**
     * Converts a since-boot counter reading into steps taken today.
     *
     * Two resets have to be handled. At midnight the baseline moves to the
     * current reading. At reboot the counter itself restarts, which shows up as
     * a reading below the last one; the steps counted before the reboot are
     * banked so the day's total does not jump backwards.
     */
    @Synchronized
    private fun stepsFromRaw(raw: Long?): Int {
        val today = todayKey()
        var banked = prefs.getLong(KEY_BANKED, 0L)
        var baseline = prefs.getLong(KEY_BASELINE, -1L)
        val lastSeen = prefs.getLong(KEY_LAST_SEEN, -1L)

        if (prefs.getInt(KEY_DAY, -1) != today) {
            banked = 0L
            baseline = raw ?: -1L
            prefs.edit()
                .putInt(KEY_DAY, today)
                .putLong(KEY_BANKED, 0L)
                .putLong(KEY_BASELINE, baseline)
                .apply()
        }

        if (raw == null) return banked.toInt()

        if (baseline < 0) {
            baseline = raw
            prefs.edit().putLong(KEY_BASELINE, baseline).apply()
        }

        if (lastSeen >= 0 && raw < lastSeen) {
            // Counter restarted: bank what was counted before the reboot.
            banked += (lastSeen - baseline).coerceAtLeast(0L)
            baseline = 0L
            prefs.edit()
                .putLong(KEY_BANKED, banked)
                .putLong(KEY_BASELINE, baseline)
                .apply()
        }

        prefs.edit().putLong(KEY_LAST_SEEN, raw).apply()
        return (banked + (raw - baseline).coerceAtLeast(0L)).toInt()
    }

    private fun todayKey(): Int = Calendar.getInstance().run {
        get(Calendar.YEAR) * 10000 + (get(Calendar.MONTH) + 1) * 100 + get(Calendar.DAY_OF_MONTH)
    }

    private companion object {
        const val KEY_DAY = "day"
        const val KEY_BASELINE = "baseline"
        const val KEY_LAST_SEEN = "lastSeen"
        const val KEY_BANKED = "banked"
        const val READ_TIMEOUT_MS = 1500L
    }
}
