package com.rkprince.control.enforcement

import android.content.Context

/**
 * Remembers when the block screen could not be shown and Home was used
 * instead, so the app can point at the system setting that is in the way
 * rather than leave the user wondering why the screen never appears.
 */
object ShieldHealth {
    private const val PREFS = "control_shield"
    private const val KEY_FALLBACK_AT = "fallbackAt"
    private const val KEY_FALLBACKS = "fallbacks"

    fun recordFallback(context: Context) {
        val prefs = EnforcementStorage.preferences(context, PREFS)
        prefs.edit()
            .putLong(KEY_FALLBACK_AT, System.currentTimeMillis())
            .putInt(KEY_FALLBACKS, prefs.getInt(KEY_FALLBACKS, 0) + 1)
            .apply()
    }

    /** Wall-clock millis of the last fallback, or 0 if there has been none. */
    fun lastFallbackAt(context: Context): Long =
        EnforcementStorage.preferences(context, PREFS).getLong(KEY_FALLBACK_AT, 0L)

    fun clear(context: Context) {
        EnforcementStorage.preferences(context, PREFS).edit().clear().apply()
    }
}
