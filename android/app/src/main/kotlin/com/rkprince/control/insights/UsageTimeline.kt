package com.rkprince.control.insights

import java.util.Calendar
import java.util.TimeZone

data class UsageTimelineBucket(
    val startMillis: Long,
    val endMillis: Long,
    val millis: Long,
    val pickups: Int,
)

data class UsageTimelineTotals(
    val perPackage: Map<String, Long>,
    val buckets: List<UsageTimelineBucket>,
    val firstEventAt: Long?,
) {
    val totalScreenMillis: Long get() = perPackage.values.sum()
    val pickups: Int get() = buckets.sumOf { it.pickups }
}

/** Splits actual foreground intervals, never aggregate estimates, into local buckets. */
object UsageTimeline {
    fun accumulate(
        events: List<UsageEventRecord>,
        windowStart: Long,
        windowEnd: Long,
        bucket: String,
        timeZone: TimeZone = TimeZone.getDefault(),
        includePackage: (String) -> Boolean = { true },
    ): UsageTimelineTotals {
        require(bucket == "hour" || bucket == "day")
        require(windowEnd >= windowStart)
        val starts = mutableListOf<Long>()
        val ends = mutableListOf<Long>()
        val calendar = Calendar.getInstance(timeZone).apply {
            timeInMillis = windowStart
            if (bucket == "day") {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            } else {
                // Subtract elapsed minutes to preserve which repeated DST hour this is.
                timeInMillis = windowStart - get(Calendar.MINUTE) * 60_000L -
                    get(Calendar.SECOND) * 1_000L - get(Calendar.MILLISECOND)
            }
        }
        var start = windowStart
        while (start < windowEnd) {
            // Calendar dates, not 24-hour durations: DST days can be 23 or 25 hours.
            calendar.add(if (bucket == "day") Calendar.DATE else Calendar.HOUR_OF_DAY, 1)
            if (bucket == "day") {
                // A midnight DST gap may normalize to 01:00; do not carry that
                // hour into the following day's boundary.
                calendar.set(Calendar.HOUR_OF_DAY, 0)
            }
            val end = minOf(calendar.timeInMillis, windowEnd)
            if (end <= start) continue
            starts += start
            ends += end
            start = end
        }
        val boundaries = starts.toLongArray()
        val millis = LongArray(starts.size)
        val unlocks = IntArray(starts.size)
        val wakes = IntArray(starts.size)
        fun indexAt(at: Long): Int {
            val found = boundaries.binarySearch(at)
            return if (found >= 0) found else -found - 2
        }

        val totals = UsageMath.accumulate(
            events, windowStart, windowEnd,
            onSession = { packageName, from, until ->
                if (includePackage(packageName)) {
                    var index = indexAt(from)
                    while (index in starts.indices && starts[index] < until) {
                        millis[index] += minOf(until, ends[index]) - maxOf(from, starts[index])
                        index++
                    }
                }
            },
            onPickup = { type, at ->
                val index = indexAt(at)
                if (index in starts.indices) {
                    if (type == UsageMath.KEYGUARD_HIDDEN) unlocks[index]++ else wakes[index]++
                }
            },
        )
        // Choose one pickup source for the entire window, not separately per bucket.
        val pickups = if (totals.keyguardUnlocks > 0) unlocks else wakes
        return UsageTimelineTotals(
            perPackage = totals.perPackage.filterKeys(includePackage),
            buckets = starts.indices.map {
                UsageTimelineBucket(starts[it], ends[it], millis[it], pickups[it])
            },
            firstEventAt = events.firstOrNull { it.timestamp < windowEnd }?.timestamp,
        )
    }
}
