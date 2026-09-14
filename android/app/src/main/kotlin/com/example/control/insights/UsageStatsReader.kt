package com.example.control.insights

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings

/** One app row on the Insights screen. */
data class AppUsage(
    val packageName: String,
    val label: String,
    val foregroundMillis: Long,
)

data class UsageSnapshot(
    val apps: List<AppUsage>,
    val totalScreenMillis: Long,
    val pickups: Int,
)

/**
 * Reads the Insights numbers from [UsageStatsManager].
 *
 * Uses the raw event stream rather than `queryUsageStats`, whose aggregate
 * buckets are rounded to whole intervals and are useless for anything shorter
 * than a day. Walking resume/pause pairs gives per-second accuracy.
 */
class UsageStatsReader(private val context: Context) {

    private val installedApps = InstalledAppsReader(context)

    fun hasPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun permissionIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Foreground time and pickups between [startMillis] and [endMillis].
     *
     * Three things have to be right for the numbers to match what the system
     * Digital Wellbeing screen shows:
     *
     *  - the query starts before the window, because a session that began
     *    yesterday evening has its resume event outside today and would
     *    otherwise be dropped entirely;
     *  - every session is clipped to the window, so last night's usage is not
     *    credited to today;
     *  - the window never extends past now, or an app currently in the
     *    foreground is credited with all the hours until midnight.
     */
    fun snapshot(startMillis: Long, endMillis: Long): UsageSnapshot {
        val manager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val windowEnd = minOf(endMillis, System.currentTimeMillis())
        if (windowEnd <= startMillis) {
            return UsageSnapshot(emptyList(), 0L, 0)
        }

        val events = manager.queryEvents(startMillis - SESSION_LOOKBACK_MS, windowEnd)
        val records = mutableListOf<UsageEventRecord>()

        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            records += UsageEventRecord(packageName, event.eventType, event.timeStamp)
        }

        val totals = UsageMath.accumulate(records, startMillis, windowEnd)

        // Apps the user can actually open, plus Control itself. Without the
        // launcher filter the system UI, the launcher and the keyboard sit at
        // the top of Insights; without the exception, the one app that is
        // definitely being used while reading this screen is missing from it.
        val visible = installedApps.visibleForUsage()

        val apps = totals.perPackage
            .filterValues { it > 0 }
            .mapNotNull { (packageName, millis) ->
                val label = visible[packageName] ?: return@mapNotNull null
                AppUsage(packageName, label, millis)
            }
            .sortedByDescending { it.foregroundMillis }

        return UsageSnapshot(
            apps = apps,
            totalScreenMillis = apps.sumOf { it.foregroundMillis },
            pickups = totals.pickups,
        )
    }

    private companion object {
        /**
         * How far before the window to start reading events, so a session that
         * was already running when the window opened is picked up.
         */
        const val SESSION_LOOKBACK_MS = 12 * 60 * 60 * 1000L
    }
}
