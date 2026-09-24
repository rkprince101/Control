package com.example.control.shortcuts

import android.content.Context
import com.example.control.enforcement.EnforcementClock
import org.json.JSONObject
import java.util.Calendar

/**
 * Counts how many times each shortcut channel fired today.
 *
 * A channel is just a name the user picks ("pushups") and then references from
 * whatever fires it: an NFC tag, a Tasker action, a home-screen shortcut. The
 * block knows the name, not the mechanism, so the same habit can be triggered
 * several different ways.
 *
 * Counts reset at local midnight, matching the daily reset of every other
 * signal the engine reads.
 */
class ShortcutStore(private val context: Context) {

    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    fun fire(channel: String): Int {
        val normalised = normalise(channel)
        if (normalised.isEmpty()) return 0

        val counts = countsForToday()
        val next = counts.optInt(normalised, 0) + 1
        counts.put(normalised, next)
        save(counts)
        return next
    }

    @Synchronized
    fun counts(): Map<String, Int> {
        val counts = countsForToday()
        return buildMap {
            counts.keys().forEach { key -> put(key, counts.getInt(key)) }
        }
    }

    @Synchronized
    fun reset(channel: String) {
        val counts = countsForToday()
        counts.remove(normalise(channel))
        save(counts)
    }

    /** Channel names are matched loosely so a tag written as "Pushups" still counts. */
    private fun normalise(channel: String) = channel.trim().lowercase()

    private fun countsForToday(): JSONObject {
        if (prefs.getInt(KEY_DAY, -1) != todayKey()) return JSONObject()
        val raw = prefs.getString(KEY_COUNTS, null) ?: return JSONObject()
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    private fun save(counts: JSONObject) {
        prefs.edit()
            .putInt(KEY_DAY, todayKey())
            .putString(KEY_COUNTS, counts.toString())
            .apply()
    }

    private fun todayKey(): Int = Calendar.getInstance().run {
        timeInMillis = EnforcementClock.now(context)
        get(Calendar.YEAR) * 10000 +
            (get(Calendar.MONTH) + 1) * 100 +
            get(Calendar.DAY_OF_MONTH)
    }

    private companion object {
        const val PREFS = "control_shortcuts"
        const val KEY_DAY = "day"
        const val KEY_COUNTS = "counts"
    }
}
