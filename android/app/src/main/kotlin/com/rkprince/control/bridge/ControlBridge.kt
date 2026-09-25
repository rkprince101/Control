package com.rkprince.control.bridge

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import com.rkprince.control.enforcement.ControlAccessibilityService
import com.rkprince.control.enforcement.EnforcementClock
import com.rkprince.control.enforcement.DeviceAdmin
import com.rkprince.control.enforcement.Plan
import com.rkprince.control.enforcement.BlockDetail
import com.rkprince.control.enforcement.PlanStore
import com.rkprince.control.enforcement.PlanCodec
import com.rkprince.control.enforcement.TamperGuard
import com.rkprince.control.insights.InstalledAppsReader
import com.rkprince.control.insights.AppCategoryResolver
import com.rkprince.control.insights.LocationReader
import com.rkprince.control.insights.StepsReader
import com.rkprince.control.insights.UsageStatsReader
import com.rkprince.control.shortcuts.ShortcutStore
import com.rkprince.control.surface.ControlWidgetProvider
import com.rkprince.control.surface.FocusTimer
import com.rkprince.control.surface.NotificationAccess
import com.rkprince.control.surface.HabitReminder
import com.rkprince.control.surface.HabitReminders
import com.rkprince.control.surface.Summary
import com.rkprince.control.surface.SummaryStore
import com.rkprince.control.surface.WeeklyReport
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * The single seam between the Dart rule engine and Android.
 *
 * Dart supplies enabled rules and signal snapshots. Native keeps recurring
 * schedules, grant expiry and package categories current while Dart is asleep.
 */
class ControlBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val planStore = PlanStore(context)
    private val usage = UsageStatsReader(context)
    private val apps = InstalledAppsReader(context)
    private val categories = AppCategoryResolver(context)
    private val steps = StepsReader(context)
    private val location = LocationReader(context)
    private val shortcuts = ShortcutStore(context)
    private val tamperGuard = TamperGuard(context)
    private val summaries = SummaryStore(context)

    private var channel: MethodChannel? = null
    private val timelineHandler = Handler(Looper.getMainLooper())
    private val timelineLifecycle = Any()
    private var timelineExecutor: ThreadPoolExecutor? = null
    private var timelineGeneration = 0L
    private var timelineRequest = 0L
    private val timelineResults = mutableMapOf<Long, MethodChannel.Result>()

    /**
     * Set while an Activity is attached. Only runtime permission requests need
     * it; everything else works from the application context so it keeps
     * working when the UI is gone.
     */
    private var activity: Activity? = null

    fun attach(messenger: BinaryMessenger, activity: Activity?) {
        detach()
        this.activity = activity
        timelineExecutor = ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(4),
        )
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        synchronized(timelineLifecycle) {
            timelineGeneration++
            timelineExecutor?.shutdownNow()
            timelineExecutor = null
            timelineHandler.removeCallbacksAndMessages(null)
            timelineResults.clear()
        }
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Enforcement -----------------------------------------------------
            "applyPlan" -> applyPlan(call, result)
            "readPlan" -> result.success(planStore.read().toMap())
            "enforcementTime" -> result.success(EnforcementClock.now(context))

            "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
            "openAccessibilitySettings" -> {
                startExternal(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(null)
            }

            // Insights --------------------------------------------------------
            "hasUsageAccess" -> result.success(usage.hasPermission())
            "openUsageAccessSettings" -> {
                startExternal(usage.permissionIntent())
                result.success(null)
            }
            "usageSnapshot" -> usageSnapshot(call, result)
            "usageTimeline" -> usageTimeline(call, result)
            "installedApps" -> result.success(apps.launchable().map { it.toMap() })
            "appIcon" -> appIcon(call, result)

            // Steps -----------------------------------------------------------
            "stepsStatus" -> result.success(
                mapOf(
                    "granted" to steps.hasPermission(),
                    "available" to steps.isAvailable(),
                ),
            )
            "requestStepsPermission" -> {
                requestStepsPermission()
                result.success(null)
            }
            "stepsToday" -> steps.readToday { count -> result.success(count) }

            // Location --------------------------------------------------------
            "locationStatus" -> result.success(
                mapOf(
                    "granted" to location.hasPermission(),
                    "enabled" to location.isEnabled(),
                ),
            )
            "requestLocationPermission" -> {
                requestLocationPermission()
                result.success(null)
            }
            "currentLocation" -> location.current { fix ->
                result.success(
                    if (fix == null) {
                        null
                    } else {
                        mapOf(
                            "latitude" to fix.latitude,
                            "longitude" to fix.longitude,
                            "accuracy" to fix.accuracy.toDouble(),
                        )
                    },
                )
            }

            // Shortcut channels -----------------------------------------------
            "shortcutCounts" -> result.success(shortcuts.counts())
            "fireShortcut" -> {
                val name = call.argument<String>("channel")
                if (name == null) {
                    result.error("bad_args", "channel is required", null)
                } else {
                    result.success(shortcuts.fire(name))
                }
            }

            // Widget, tile and weekly report ---------------------------------
            "updateSummary" -> {
                summaries.write(
                    Summary(
                        screenTime = call.argument<String>("screenTime") ?: "0m",
                        focusToday = call.argument<String>("focusToday") ?: "0m",
                        blockedCount = call.argument<Int>("blockedCount") ?: 0,
                        activeBlocks = call.argument<Int>("activeBlocks") ?: 0,
                        weeklyReport = call.argument<String>("weeklyReport") ?: "",
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
                // The widget cannot recompute anything, so it is refreshed the
                // moment the numbers behind it change.
                ControlWidgetProvider.refresh(context)
                result.success(null)
            }
            "weeklyReportEnabled" -> result.success(summaries.weeklyReportEnabled)
            "setWeeklyReport" -> {
                WeeklyReport.setEnabled(
                    context,
                    call.argument<Boolean>("enabled") ?: false,
                )
                result.success(null)
            }
            "requestNotificationPermission" -> {
                requestNotificationPermission()
                result.success(null)
            }
            "showFocusTimer" -> {
                FocusTimer.show(
                    context,
                    title = call.argument<String>("title") ?: "",
                    text = call.argument<String>("text") ?: "",
                    clockAt = call.argument<Number>("clockAt")?.toLong() ?: 0L,
                    countDown = call.argument<Boolean>("countDown") ?: false,
                    endsAt = call.argument<Number>("endsAt")?.toLong() ?: 0L,
                    doneTitle = call.argument<String>("doneTitle") ?: "",
                    doneText = call.argument<String>("doneText") ?: "",
                )
                result.success(null)
            }
            "cancelFocusTimer" -> {
                FocusTimer.cancel(context)
                result.success(null)
            }
            "finishFocusTimer" -> {
                FocusTimer.finish(context)
                result.success(null)
            }
            "notificationStatus" -> result.success(
                mapOf(
                    "enabled" to NotificationAccess.enabled(context),
                    "exactAlarms" to NotificationAccess.canUseExactAlarms(context),
                    "exactRelevant" to NotificationAccess.exactAlarmsRelevant(),
                ),
            )
            "fixNotifications" -> {
                fixNotifications()
                result.success(null)
            }
            "openExactAlarmSettings" -> {
                NotificationAccess.exactAlarmIntent(context)?.let { startExternal(it) }
                result.success(null)
            }
            "setHabitReminders" -> {
                val raw = call.argument<List<Map<*, *>>>("reminders") ?: emptyList()
                HabitReminders.replace(context, raw.mapNotNull { HabitReminder.fromMap(it) })
                result.success(null)
            }

            // Uninstall protection --------------------------------------------
            "protectionStatus" -> result.success(
                mapOf(
                    "adminActive" to DeviceAdmin.isAdminActive(context),
                    "deviceOwner" to DeviceAdmin.isDeviceOwner(context),
                    "uninstallBlocked" to DeviceAdmin.isUninstallBlocked(context),
                    "hardMode" to tamperGuard.enabled,
                ),
            )
            "deviceOwnerStatus" -> result.success(
                mapOf(
                    "isOwner" to DeviceAdmin.isDeviceOwner(context),
                    "provisioningAllowed" to DeviceAdmin.isProvisioningAllowed(context),
                    "component" to DeviceAdmin.ownerComponent(context),
                ),
            )
            "requestDeviceAdmin" -> requestDeviceAdmin(result)
            "setUninstallBlocked" -> {
                val blocked = call.argument<Boolean>("blocked") ?: true
                result.success(DeviceAdmin.setUninstallBlocked(context, blocked))
            }
            "setHardMode" -> {
                tamperGuard.enabled = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }
            "releaseProtection" -> {
                tamperGuard.enabled = false
                DeviceAdmin.deactivate(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------

    private fun applyPlan(call: MethodCall, result: MethodChannel.Result) {
        val packages = call.argument<List<String>>("blockedPackages")
        if (packages == null) {
            result.error("bad_args", "blockedPackages is required", null)
            return
        }
        val domains = call.argument<List<String>>("blockedDomains").orEmpty()
        val details = call.argument<Map<String, Map<String, Any?>>>("details")
            .orEmpty()
            .mapValues { (_, raw) ->
                BlockDetail(
                    title = raw["title"] as? String ?: "",
                    status = raw["status"] as? String ?: "",
                    progressPercent = (raw["progress"] as? Number)?.toInt() ?: -1,
                    unlockAt = (raw["unlockAt"] as? Number)?.toLong() ?: 0L,
                )
            }
        val nextWakeAt = call.argument<Number>("nextWakeAt")?.toLong() ?: 0L
        val rules = try {
            call.argument<List<Map<String, Any?>>>("rules")?.let {
                PlanCodec.decodeRules(JSONArray(it))
            }
        } catch (error: Exception) {
            result.error("bad_args", "Invalid native rules: ${error.message}", null)
            return
        }

        planStore.write(
            Plan(
                blockedPackages = packages.toSet(),
                blockedDomains = domains.toSet(),
                nextWakeAt = nextWakeAt,
                updatedAt = EnforcementClock.now(context),
                details = details,
                rules = rules,
            ),
        )
        result.success(null)
    }

    private fun usageSnapshot(call: MethodCall, result: MethodChannel.Result) {
        if (!usage.hasPermission()) {
            result.error("permission_denied", "Usage access has not been granted", null)
            return
        }
        val start = call.argument<Number>("startMillis")?.toLong()
        val end = call.argument<Number>("endMillis")?.toLong()
        if (start == null || end == null) {
            result.error("bad_args", "startMillis and endMillis are required", null)
            return
        }

        val snapshot = usage.snapshot(start, end)
        result.success(
            mapOf(
                "totalScreenMillis" to snapshot.totalScreenMillis,
                "pickups" to snapshot.pickups,
                "apps" to snapshot.apps.map {
                    mapOf(
                        "package" to it.packageName,
                        "label" to it.label,
                        "millis" to it.foregroundMillis,
                    )
                },
            ),
        )
    }

    private fun usageTimeline(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Number>("startMillis")?.toLong()
        val end = call.argument<Number>("endMillis")?.toLong()
        val bucket = call.argument<String>("bucket")
        if (start == null || end == null || start < 0 || end < start ||
            end - start > TimeUnit.DAYS.toMillis(366) || bucket !in listOf("hour", "day")
        ) {
            result.error("bad_args", "Supply valid bounds (at most 366 days) and bucket hour or day", null)
            return
        }
        val executor = timelineExecutor
        if (executor == null) {
            result.error("unavailable", "Usage bridge is detached", null)
            return
        }
        val request = ++timelineRequest
        val generation = timelineGeneration
        timelineResults[request] = result
        try {
            // The task holds only an ID, never a Flutter Result or Activity callback.
            executor.execute { queryTimeline(request, generation, start, end, bucket!!) }
        } catch (_: RejectedExecutionException) {
            timelineResults.remove(request)
            result.error("usage_busy", "Usage history is busy. Please try again.", null)
        }
    }

    private fun queryTimeline(request: Long, generation: Long, start: Long, end: Long, bucket: String) {
        var errorCode: String? = null
        var errorMessage: String? = null
        val payload = try {
            val snapshot = usage.timeline(start, end, bucket)
            mapOf(
                "apps" to snapshot.apps.map {
                    mapOf("package" to it.packageName, "label" to it.label, "millis" to it.foregroundMillis)
                },
                "totalScreenMillis" to snapshot.totalScreenMillis,
                "pickups" to snapshot.pickups,
                "buckets" to snapshot.buckets.map {
                    mapOf(
                        "startMillis" to it.startMillis, "endMillis" to it.endMillis,
                        "millis" to it.millis, "pickups" to it.pickups,
                    )
                },
                "startMillis" to snapshot.startMillis,
                "endMillis" to snapshot.endMillis,
                "firstEventAt" to snapshot.firstEventAt,
                "historyNote" to snapshot.historyNote,
            )
        } catch (_: SecurityException) {
            errorCode = "permission_denied"
            errorMessage = "Usage access has not been granted"
            null
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return
        } catch (_: Exception) {
            errorCode = "usage_unavailable"
            errorMessage = "Android could not read usage history. Please try again."
            null
        }
        synchronized(timelineLifecycle) {
            // Serialize posting with detach so no old callback survives a new attachment.
            if (generation != timelineGeneration) return
            timelineHandler.post {
                if (generation == timelineGeneration) {
                    timelineResults.remove(request)?.let {
                        if (errorCode == null) it.success(payload)
                        else it.error(errorCode, errorMessage, null)
                    }
                }
            }
        }
    }

    private fun appIcon(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("package")
        if (packageName == null) {
            result.error("bad_args", "package is required", null)
            return
        }
        result.success(apps.iconPng(packageName))
    }

    /**
     * Launches the system device-admin dialog.
     *
     * Prefers the Activity: some OEM builds refuse to show this dialog when it
     * is started from an application context with NEW_TASK, and the failure is
     * silent, which reads to the user as a dead button.
     */
    private fun requestDeviceAdmin(result: MethodChannel.Result) {
        val intent = DeviceAdmin.activationIntent(context)
        if (intent.resolveActivity(context.packageManager) == null) {
            result.error(
                "unsupported",
                "This device has no device-admin settings screen",
                null,
            )
            return
        }

        val host = activity
        if (host != null) {
            host.startActivity(Intent(intent).apply { flags = 0 })
        } else {
            startExternal(intent)
        }
        result.success(null)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val host = activity ?: return
        notificationPrefs().edit().putBoolean(KEY_ASKED_NOTIFICATIONS, true).apply()
        host.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    /**
     * The Settings row's fix: the system prompt while Android will still show
     * it, the app's notification settings once it will not (denied twice, or
     * notifications switched off there by hand).
     */
    private fun fixNotifications() {
        if (NotificationAccess.enabled(context)) return
        val host = activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            host != null &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED &&
            (!notificationPrefs().getBoolean(KEY_ASKED_NOTIFICATIONS, false) ||
                host.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))
        ) {
            requestNotificationPermission()
            return
        }
        startExternal(NotificationAccess.settingsIntent(context))
    }

    private fun notificationPrefs() =
        context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)

    private fun requestLocationPermission() {
        activity?.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            LOCATION_PERMISSION_REQUEST,
        )
    }

    private fun requestStepsPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        activity?.requestPermissions(
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            STEPS_PERMISSION_REQUEST,
        )
    }

    private fun startExternal(intent: Intent) {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * Reads the enabled-services list rather than asking the service instance,
     * so it stays correct while the app process is fresh and the service has
     * not yet called back.
     */
    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(context, ControlAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false

        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        for (entry in splitter) {
            if (ComponentName.unflattenFromString(entry) == expected) return true
        }
        return false
    }

    private fun Plan.toMap(): Map<String, Any?> {
        val now = EnforcementClock.now(context)
        val candidates = if (rules?.any { it.categories.isNotEmpty() } == true) {
            apps.launchable().map { it.packageName }.toSet()
        } else emptySet()
        return mapOf(
            "blockedPackages" to effectivePackages(candidates, categories::categories, now).toList(),
            "blockedDomains" to effectiveDomains(now).toList(),
            "nextWakeAt" to nextWakeAt,
            "updatedAt" to updatedAt,
        )
    }

    private companion object {
        const val CHANNEL = "dev.control/enforcement"
        const val STEPS_PERMISSION_REQUEST = 4801
        const val LOCATION_PERMISSION_REQUEST = 4802
        const val NOTIFICATION_PERMISSION_REQUEST = 4803
        const val NOTIFICATION_PREFS = "notification_access"
        const val KEY_ASKED_NOTIFICATIONS = "askedForNotifications"
    }
}
