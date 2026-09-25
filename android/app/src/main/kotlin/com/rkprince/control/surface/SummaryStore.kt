package com.rkprince.control.surface

import android.content.Context
import org.json.JSONObject

/**
 * A flattened snapshot of what the app would show, cached for the surfaces that
 * live outside it.
 *
 * The home-screen widget, the Quick Settings tile and the weekly notification
 * all need numbers, and none of them can run the rule engine: they wake without
 * a Flutter isolate. So Dart writes this whenever it recomputes, and they read
 * it. Text is rendered here as plain strings rather than raw values, because
 * the formatting rules live in Dart and duplicating them in Kotlin is how two
 * screens end up disagreeing about the same number.
 */
data class Summary(
    val screenTime: String,
    val focusToday: String,
    val blockedCount: Int,
    val activeBlocks: Int,
    /** One sentence for the weekly notification. */
    val weeklyReport: String,
    val updatedAt: Long,
) {
    companion object {
        val EMPTY = Summary("0m", "0m", 0, 0, "", 0L)
    }
}

class SummaryStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun read(): Summary {
        val raw = prefs.getString(KEY, null) ?: return Summary.EMPTY
        return runCatching {
            val json = JSONObject(raw)
            Summary(
                screenTime = json.optString("screenTime", "0m"),
                focusToday = json.optString("focusToday", "0m"),
                blockedCount = json.optInt("blockedCount", 0),
                activeBlocks = json.optInt("activeBlocks", 0),
                weeklyReport = json.optString("weeklyReport", ""),
                updatedAt = json.optLong("updatedAt", 0L),
            )
        }.getOrDefault(Summary.EMPTY)
    }

    fun write(summary: Summary) {
        prefs.edit().putString(
            KEY,
            JSONObject()
                .put("screenTime", summary.screenTime)
                .put("focusToday", summary.focusToday)
                .put("blockedCount", summary.blockedCount)
                .put("activeBlocks", summary.activeBlocks)
                .put("weeklyReport", summary.weeklyReport)
                .put("updatedAt", summary.updatedAt)
                .toString(),
        ).apply()
    }

    var weeklyReportEnabled: Boolean
        get() = prefs.getBoolean(KEY_WEEKLY, false)
        set(value) = prefs.edit().putBoolean(KEY_WEEKLY, value).apply()

    private companion object {
        const val PREFS = "control_summary"
        const val KEY = "summary"
        const val KEY_WEEKLY = "weeklyReport"
    }
}
