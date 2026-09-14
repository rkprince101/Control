package com.example.control.bridge

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import com.example.control.enforcement.ControlAccessibilityService
import com.example.control.enforcement.DeviceAdmin
import com.example.control.enforcement.Plan
import com.example.control.enforcement.BlockDetail
import com.example.control.enforcement.PlanStore
import com.example.control.enforcement.TamperGuard
import com.example.control.insights.InstalledAppsReader
import com.example.control.insights.LocationReader
import com.example.control.insights.StepsReader
import com.example.control.insights.UsageStatsReader
import com.example.control.shortcuts.ShortcutStore
import com.example.control.surface.ControlWidgetProvider
import com.example.control.surface.Summary
import com.example.control.surface.SummaryStore
import com.example.control.surface.WeeklyReport
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The single seam between the Dart rule engine and Android.
 *
 * Dart owns every decision and pushes a flattened plan down; native owns
 * permissions, measurement, and the actual blocking. Nothing here re-implements
 * a rule, so the two sides can never disagree about what should be blocked.
 */
class ControlBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val planStore = PlanStore(context)
    private val usage = UsageStatsReader(context)
    private val apps = InstalledAppsReader(context)
    private val steps = StepsReader(context)
    private val location = LocationReader(context)
    private val shortcuts = ShortcutStore(context)
    private val tamperGuard = TamperGuard(context)
    private val summaries = SummaryStore(context)

    private var channel: MethodChannel? = null

    /**
     * Set while an Activity is attached. Only runtime permission requests need
     * it; everything else works from the application context so it keeps
     * working when the UI is gone.
     */
    private var activity: Activity? = null

    fun attach(messenger: BinaryMessenger, activity: Activity?) {
        this.activity = activity
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Enforcement -----------------------------------------------------
            "applyPlan" -> applyPlan(call, result)
            "readPlan" -> result.success(planStore.read().toMap())

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

        planStore.write(
            Plan(
                blockedPackages = packages.toSet(),
                blockedDomains = domains.toSet(),
                nextWakeAt = nextWakeAt,
                updatedAt = System.currentTimeMillis(),
                details = details,
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
        activity?.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

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

    private fun Plan.toMap(): Map<String, Any?> = mapOf(
        "blockedPackages" to blockedPackages.toList(),
        "blockedDomains" to blockedDomains.toList(),
        "nextWakeAt" to nextWakeAt,
        "updatedAt" to updatedAt,
    )

    private companion object {
        const val CHANNEL = "dev.control/enforcement"
        const val STEPS_PERMISSION_REQUEST = 4801
        const val LOCATION_PERMISSION_REQUEST = 4802
        const val NOTIFICATION_PERMISSION_REQUEST = 4803
    }
}
