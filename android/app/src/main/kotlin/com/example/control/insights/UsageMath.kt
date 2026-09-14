package com.example.control.insights

/** One raw usage event, reduced to what the arithmetic needs. */
data class UsageEventRecord(
    val packageName: String,
    val type: Int,
    val timestamp: Long,
)

data class UsageTotals(
    val perPackage: Map<String, Long>,
    val keyguardUnlocks: Int,
    val screenWakes: Int,
) {
    /**
     * A device with no lock screen never reports a keyguard event, so falling
     * back to screen wakes is the difference between a pickup count and a zero.
     */
    val pickups: Int get() = if (keyguardUnlocks > 0) keyguardUnlocks else screenWakes
}

/**
 * Turns a stream of usage events into per-app foreground time.
 *
 * Pulled out of [UsageStatsReader] so it can be tested. The arithmetic here has
 * had three separate bugs, and none was visible without being able to feed it a
 * hand-written event sequence.
 *
 * The model is the important part: **exactly one app is in the foreground at a
 * time.** Tracking a start time per package independently looks equivalent and
 * is not. Pause events go missing — an app killed in the background, an
 * `ACTIVITY_STOPPED` where a pause was expected, a dropped event — and every
 * package left open then gets credited all the way to the end of the window. In
 * practice that showed up as several apps each reporting the same two hours the
 * user actually spent in one of them.
 *
 * So a resume closes whatever was open before it, and the screen going off
 * closes it too. At most one session is ever running.
 */
object UsageMath {

    const val ACTIVITY_RESUMED = 1
    const val ACTIVITY_PAUSED = 2

    /**
     * `ACTIVITY_STOPPED`, `SCREEN_INTERACTIVE`, `SCREEN_NON_INTERACTIVE`,
     * `KEYGUARD_SHOWN` and `KEYGUARD_HIDDEN`. Inlined because several are only
     * public from API 28 and the values are stable across releases.
     */
    const val ACTIVITY_STOPPED = 23
    const val SCREEN_INTERACTIVE = 15
    const val SCREEN_NON_INTERACTIVE = 16
    const val KEYGUARD_SHOWN = 17
    const val KEYGUARD_HIDDEN = 18

    /**
     * Events must be in timestamp order, and should start before [windowStart]
     * so a session already running when the window opened is seen.
     */
    fun accumulate(
        events: List<UsageEventRecord>,
        windowStart: Long,
        windowEnd: Long,
    ): UsageTotals {
        val totals = mutableMapOf<String, Long>()
        var keyguardUnlocks = 0
        var screenWakes = 0

        // The single foreground session, if any.
        var openPackage: String? = null
        var openedAt = 0L

        fun close(at: Long) {
            val packageName = openPackage ?: return
            val clipped = overlap(openedAt, at, windowStart, windowEnd)
            if (clipped > 0) totals.merge(packageName, clipped, Long::plus)
            openPackage = null
        }

        for (event in events) {
            when (event.type) {
                ACTIVITY_RESUMED -> {
                    // A resume by anything ends whatever was in front of it,
                    // including a second resume by the same package: moving
                    // between activities inside one app must not restart the
                    // clock and lose the time up to that point.
                    if (openPackage == event.packageName) continue
                    close(event.timestamp)
                    openPackage = event.packageName
                    openedAt = event.timestamp
                }

                ACTIVITY_PAUSED, ACTIVITY_STOPPED ->
                    if (openPackage == event.packageName) close(event.timestamp)

                // Screen off ends the session. Without this, locking the phone
                // on an open app credits it until the next event, which can be
                // hours later.
                SCREEN_NON_INTERACTIVE, KEYGUARD_SHOWN -> close(event.timestamp)

                KEYGUARD_HIDDEN ->
                    if (event.timestamp >= windowStart) keyguardUnlocks++

                SCREEN_INTERACTIVE ->
                    if (event.timestamp >= windowStart) screenWakes++
            }
        }

        // Whatever is in the foreground right now never emitted a pause.
        close(windowEnd)

        return UsageTotals(totals, keyguardUnlocks, screenWakes)
    }

    /** The part of a session that falls inside the window. */
    private fun overlap(
        start: Long,
        end: Long,
        windowStart: Long,
        windowEnd: Long,
    ): Long = (minOf(end, windowEnd) - maxOf(start, windowStart)).coerceAtLeast(0L)
}
