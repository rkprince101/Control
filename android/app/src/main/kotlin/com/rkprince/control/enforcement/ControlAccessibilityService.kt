package com.rkprince.control.enforcement

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.UserManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import com.rkprince.control.R
import com.rkprince.control.insights.AppCategoryResolver
import com.rkprince.control.insights.PackageChangeReceiver
import com.rkprince.control.insights.StepsReader

/** Accessibility is a deterrent, not protection against safe mode or recovery. */
class ControlAccessibilityService : AccessibilityService() {
    private lateinit var planStore: PlanStore
    private lateinit var tamperGuard: TamperGuard
    private lateinit var categories: AppCategoryResolver
    private val handler = Handler(Looper.getMainLooper())
    private var connected = false
    private var packageReceiver: PackageChangeReceiver? = null
    private var windowPackage: String? = null
    private var windowClass: String? = null
    private var windowId = -1
    private var lastBlockedKey: String? = null
    private var lastBlockedAt = 0L
    private var eventCheckPending = false
    private var lastFallbackToastAt = 0L
    private var lastLoggedPackage: String? = null
    private var ticks = 0L
    private var steps: StepsReader? = null
    private var stepsListener: SensorEventListener? = null

    private val eventCheck = Runnable {
        eventCheckPending = false
        checkForeground()
    }
    private val tick = object : Runnable {
        override fun run() {
            if (!connected) return
            // Activity recognition can be granted while the service runs.
            if (ticks++ % STEP_LISTENER_RETRY_TICKS == 0L) listenForSteps()
            checkForeground()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        stopChecks()
        planStore = PlanStore(this)
        tamperGuard = TamperGuard(this)
        categories = AppCategoryResolver(this)
        AppCategoryResolver.invalidate()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        }
        packageReceiver = PackageChangeReceiver().also {
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(it, filter, RECEIVER_NOT_EXPORTED)
            else registerReceiver(it, filter)
        }
        connected = true
        ticks = 0L
        handler.post(tick)
    }

    /**
     * Keeps the step counter's last reading current all day, so the split at
     * midnight is exact and a steps rule can unlock the moment its target is
     * reached, with Flutter not running. Batched: the sensor hub holds steps
     * and hands them over together, which costs next to nothing.
     */
    private fun listenForSteps() {
        if (stepsListener != null) return
        val reader = steps ?: StepsReader(this).also { steps = it }
        if (!reader.hasPermission()) return
        val manager = getSystemService(SensorManager::class.java) ?: return
        val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) ?: return
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                runCatching { reader.record(event) }
                    .onFailure { Log.w("ControlA11y", "Could not record steps", it) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        val registered = runCatching {
            manager.registerListener(
                listener,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL,
                STEP_BATCH_MICROS,
            )
        }.getOrDefault(false)
        if (registered) stepsListener = listener
    }

    private fun stopListeningForSteps() {
        val listener = stepsListener ?: return
        stepsListener = null
        runCatching { getSystemService(SensorManager::class.java)?.unregisterListener(listener) }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!connected || event == null) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (windowPackage != event.packageName?.toString() || windowId != event.windowId) {
                windowClass = null
            }
            windowPackage = event.packageName?.toString()
            val reportedClass = event.className?.toString()
            if (reportedClass != null && !reportedClass.startsWith("android.widget.") &&
                !reportedClass.startsWith("android.view.")) windowClass = reportedClass
            windowId = event.windowId
            checkForeground()
        }
        // Coalesce noisy content events without postponing indefinitely while a page animates.
        if (!eventCheckPending) {
            eventCheckPending = true
            handler.postDelayed(eventCheck, 150L)
        }
    }

    private fun checkForeground() {
        if (!connected) return
        val now = EnforcementClock.now(this)
        val root = rootInActiveWindow ?: return
        try {
            val foreground = root.packageName?.toString() ?: return
            if (foreground == applicationContext.packageName) {
                lastBlockedKey = null
                return
            }
            // Direct Boot must never interfere with first unlock, system UI or
            // emergency calls, even when a legacy/explicit rule targets them.
            if (getSystemService(UserManager::class.java)?.isUserUnlocked != true &&
                !categories.canBlockBeforeUnlock(foreground)) return
            val screenClass = if (foreground == windowPackage && root.windowId == windowId) {
                windowClass
            } else root.className?.toString()
            if (tamperGuard.guards(foreground) && tamperGuard.isTamperScreen(screenClass, root)) {
                performGlobalAction(GLOBAL_ACTION_BACK)
                performGlobalAction(GLOBAL_ACTION_HOME)
                return
            }

            // Always read now, including callbacks scheduled before a plan edit or time boundary.
            val plan = StepUnlocks.apply(this, planStore.read(), now)
            val appCategories = if (plan.rules?.any { it.categories.isNotEmpty() } == true) {
                categories.categories(foreground)
            } else emptySet()
            val blocked = plan.blocks(foreground, appCategories, now)
            if (foreground != lastLoggedPackage) {
                // One line per app switch, never per tick: enough to tell "not
                // matched" from "matched but not blocked" from the outside.
                lastLoggedPackage = foreground
                Log.i(
                    "ControlA11y",
                    "foreground=$foreground categories=$appCategories " +
                        "rules=${plan.rules?.size ?: -1} blocked=$blocked " +
                        "active=${plan.rules?.count { it.isBlocked(now) } ?: -1}",
                )
            }
            if (blocked) {
                showBlockScreen(foreground, foreground)
                return
            }
            val domains = plan.effectiveDomains(now)
            val viewId = WebRules.browserUrlBars[foreground]
            if (domains.isNotEmpty() && viewId != null) {
                val bars = root.findAccessibilityNodeInfosByViewId(viewId).orEmpty()
                try {
                    val host = WebRules.hostOf(bars.firstOrNull { it.isVisibleToUser }?.text?.toString())
                    val domain = WebRules.matches(host, domains)
                    if (domain != null) {
                        // Back first: a back action after launching can dismiss our own shield.
                        performGlobalAction(GLOBAL_ACTION_BACK)
                        showBlockScreen(foreground, domain)
                        return
                    }
                } finally {
                    @Suppress("DEPRECATION")
                    bars.forEach { it.recycle() }
                }
            }
            lastBlockedKey = null
        } catch (error: RuntimeException) {
            // Windows can disappear during inspection. Retry from the current root next tick.
            Log.w("ControlA11y", "Foreground check interrupted", error)
        } finally {
            @Suppress("DEPRECATION")
            root.recycle()
        }
    }

    private fun showBlockScreen(packageName: String, detailKey: String) {
        val key = "$packageName:$detailKey"
        val now = SystemClock.elapsedRealtime()
        if (lastBlockedKey == key && now - lastBlockedAt < 600L) return
        lastBlockedKey = key
        lastBlockedAt = now
        val started = runCatching {
            startActivity(Intent(this, BlockOverlayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION or Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                putExtra(BlockOverlayActivity.EXTRA_PACKAGE, packageName)
                putExtra(BlockOverlayActivity.EXTRA_DETAIL_KEY, detailKey)
            })
        }.isSuccess
        if (started) {
            handler.postDelayed({ verifyShield(packageName) }, SHIELD_CHECK_MS)
        } else {
            fallBackToHome(packageName)
        }
    }

    /**
     * The block screen is an activity, and some builds refuse to start one
     * from the background without saying so: MIUI and HyperOS do unless
     * "Display pop-up windows while running in the background" is allowed for
     * Control. When the blocked app is still in front after the screen should
     * have appeared, Home is used instead, which no build refuses, so a
     * blocked app is never simply left open.
     */
    private fun verifyShield(packageName: String) {
        if (!connected) return
        val root = rootInActiveWindow ?: return
        val foreground = try {
            root.packageName?.toString()
        } finally {
            @Suppress("DEPRECATION")
            root.recycle()
        }
        if (foreground == packageName) fallBackToHome(packageName)
    }

    private fun fallBackToHome(packageName: String) {
        performGlobalAction(GLOBAL_ACTION_HOME)
        ShieldHealth.recordFallback(this)
        val now = SystemClock.elapsedRealtime()
        if (now - lastFallbackToastAt < FALLBACK_TOAST_GAP_MS) return
        lastFallbackToastAt = now
        val label = runCatching {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0))
        }.getOrDefault(packageName)
        Toast.makeText(this, getString(R.string.block_fallback_toast, label), Toast.LENGTH_LONG).show()
    }

    private fun stopChecks() {
        connected = false
        handler.removeCallbacksAndMessages(null)
        stopListeningForSteps()
        eventCheckPending = false
        packageReceiver?.let { unregisterReceiver(it) }
        packageReceiver = null
        windowPackage = null
        windowClass = null
        windowId = -1
        lastBlockedKey = null
    }

    override fun onUnbind(intent: Intent?): Boolean {
        stopChecks()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        stopChecks()
        super.onDestroy()
    }

    override fun onInterrupt() = Unit

    private companion object {
        /** Let the hub hold steps up to this long before delivering them. */
        const val STEP_BATCH_MICROS = 10_000_000
        const val STEP_LISTENER_RETRY_TICKS = 60L

        /** Long enough for a slow phone to draw the block screen. */
        const val SHIELD_CHECK_MS = 900L
        const val FALLBACK_TOAST_GAP_MS = 5_000L
    }
}
