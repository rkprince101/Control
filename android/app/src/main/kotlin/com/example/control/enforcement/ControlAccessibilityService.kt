package com.example.control.enforcement

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.UserManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.example.control.insights.AppCategoryResolver
import com.example.control.insights.PackageChangeReceiver

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

    private val eventCheck = Runnable {
        eventCheckPending = false
        checkForeground()
    }
    private val tick = object : Runnable {
        override fun run() {
            if (!connected) return
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
        handler.post(tick)
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
            val plan = planStore.read()
            val appCategories = if (plan.rules?.any { it.categories.isNotEmpty() } == true) {
                categories.categories(foreground)
            } else emptySet()
            if (plan.blocks(foreground, appCategories, now)) {
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
        startActivity(Intent(this, BlockOverlayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or
                Intent.FLAG_ACTIVITY_NO_ANIMATION or Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
            putExtra(BlockOverlayActivity.EXTRA_PACKAGE, packageName)
            putExtra(BlockOverlayActivity.EXTRA_DETAIL_KEY, detailKey)
        })
    }

    private fun stopChecks() {
        connected = false
        handler.removeCallbacksAndMessages(null)
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
}
