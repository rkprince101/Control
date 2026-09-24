package com.example.control.enforcement

import java.util.Calendar

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

/** Enabled rules only. Place/device signals remain owned by Dart. */
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
) {
    fun isBlocked(now: Long, local: Calendar = Calendar.getInstance().apply { timeInMillis = now }): Boolean =
        when (mode) {
            "time" -> {
                val minute = local.get(Calendar.HOUR_OF_DAY) * 60 + local.get(Calendar.MINUTE)
                val weekday = (local.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                val inside = schedule.any { it.contains(minute, weekday) }
                schedule.isNotEmpty() && (if (schedulePolarity == "allowDuring") !inside else inside)
            }
            "condition" -> blocked || (allowedUntil > 0 && allowedUntil <= now)
            else -> blocked
        }

    fun targets(packageName: String, appCategories: Set<String>): Boolean =
        packageName in apps ||
            (packageName !in excludedApps && categories.any { it in appCategories })

    fun detail(): BlockDetail = BlockDetail(
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
