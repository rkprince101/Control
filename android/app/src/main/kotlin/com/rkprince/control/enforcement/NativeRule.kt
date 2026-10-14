package com.rkprince.control.enforcement

import java.util.Calendar
import java.util.Locale

data class NativeTimeRange(
    val startMinute: Int,
    val endMinute: Int,
    val weekdays: Set<Int>,
) {
    fun contains(minute: Int, weekday: Int): Boolean {
        if (endMinute > startMinute) {
            return weekday in weekdays && minute >= startMinute && minute < endMinute
        }
        val yesterday = if (weekday == 1) 7 else weekday - 1
        return (minute >= startMinute && weekday in weekdays) ||
            (minute < endMinute && yesterday in weekdays)
    }
}

/**
 * Enabled rules only. Place/device signals remain owned by Dart.
 *
 * Steps are the one condition Android can settle on its own: when [stepsTarget]
 * is set, Dart has found every other condition met, and reaching the target
 * mints an allowance natively ([StepUnlockRules]) without Flutter running.
 */
data class NativeRule(
    val id: String,
    val title: String,
    val mode: String,
    val apps: Set<String> = emptySet(),
    val categories: Set<String> = emptySet(),
    val excludedApps: Set<String> = emptySet(),
    val blockedDomains: Set<String> = emptySet(),
    val schedule: List<NativeTimeRange> = emptyList(),
    val schedulePolarity: String = "blockDuring",
    val blocked: Boolean = false,
    val allowedUntil: Long = 0L,
    /** Steps that unlock this rule natively, or 0 when Dart decides alone. */
    val stepsTarget: Int = 0,
    /** How long a native allowance lasts; 0 means until midnight. */
    val unlockForMillis: Long = 0L,
    /** Runtime only, never stored: end of a native allowance in force. */
    val grantUntil: Long = 0L,
) {
    fun isBlocked(now: Long, local: Calendar = Calendar.getInstance().apply { timeInMillis = now }): Boolean =
        when (mode) {
            "time" -> {
                val minute = local.get(Calendar.HOUR_OF_DAY) * 60 + local.get(Calendar.MINUTE)
                val weekday = (local.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                val inside = schedule.any { it.contains(minute, weekday) }
                schedule.isNotEmpty() && (if (schedulePolarity == "allowDuring") !inside else inside)
            }
            "condition" -> grantUntil <= now &&
                (blocked || (allowedUntil > 0 && allowedUntil <= now))
            else -> blocked
        }

    fun targets(packageName: String, appCategories: Set<String>): Boolean =
        packageName in apps ||
            (packageName !in excludedApps && categories.any { it in appCategories })

    fun detail(stepsToday: Int = -1): BlockDetail {
        if (mode == "condition" && stepsTarget > 0 && stepsToday >= 0) {
            val done = stepsToday.coerceAtMost(stepsTarget)
            return BlockDetail(
                title = title,
                // Blocked with the target met means today's allowance from
                // walking has already been spent.
                status = if (done >= stepsTarget) {
                    "Today's walk already bought its time. It unlocks again tomorrow."
                } else {
                    String.format(
                        Locale.getDefault(),
                        "%,d of %,d steps today. Reach it and this unlocks.",
                        done,
                        stepsTarget,
                    )
                },
                progressPercent = (done * 100L / stepsTarget).toInt(),
                unlockAt = 0L,
            )
        }
        return staticDetail()
    }

    private fun staticDetail(): BlockDetail = BlockDetail(
        title = title,
        status = when (mode) {
            "time" -> "Blocked by your recurring schedule."
            "condition" -> "Complete your conditions to unlock."
            "place" -> "Blocked by your place rule."
            "device" -> "Blocked by your device rule."
            else -> "Blocked by your rule."
        },
        progressPercent = -1,
        // A flattened countdown can belong to a different rule or a past window.
        unlockAt = 0L,
    )
}
