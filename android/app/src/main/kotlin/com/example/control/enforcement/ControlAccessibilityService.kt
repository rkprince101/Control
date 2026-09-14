package com.example.control.enforcement

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.example.control.R
import android.view.accessibility.AccessibilityEvent

/**
 * Android has no public equivalent of the iOS Screen Time shield, so the block
 * is built from the one signal a normal app can get: an accessibility service
 * is told which package just came to the foreground. When that package is in
 * the current [Plan], we immediately push a full-screen block activity on top.
 *
 * This is the Deterrent tier. It is defeated by turning the service off in
 * Settings, and by safe mode, which does not start accessibility services at
 * all. Closing those holes needs Device Owner, handled elsewhere.
 */
class ControlAccessibilityService : AccessibilityService() {

    private lateinit var planStore: PlanStore
    private lateinit var tamperGuard: TamperGuard

    /** Last package we reacted to, so one app switch does not spawn a stack of screens. */
    private var lastBlockedPackage: String? = null
    private var lastBlockedAt = 0L

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        planStore = PlanStore(this)
        tamperGuard = TamperGuard(this)
        Log.i(TAG, "accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) return

        if (tamperGuard.guards(packageName)) {
            val className = event.className
            if (tamperGuard.isTamperScreen(className, rootInActiveWindow)) {
                retreat()
                return
            }
            // The window is often reported before its content exists, so a
            // screen that looks innocent right now gets a second look once it
            // has drawn. Without this the uninstall dialog slips through on
            // slower devices.
            handler.postDelayed({
                if (tamperGuard.isTamperScreen(className, rootInActiveWindow)) {
                    retreat()
                }
            }, RECHECK_DELAY_MS)
        }

        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val plan = planStore.read()

        if (plan.blockedDomains.isNotEmpty() && WebRules.isBrowser(packageName)) {
            checkBrowser(packageName, plan)
            // The address bar is often still showing the previous page when the
            // event arrives, and navigation inside a tab may not raise another
            // one, so look again shortly after.
            for (delay in BROWSER_RECHECK_DELAYS_MS) {
                handler.postDelayed({ checkBrowser(packageName, plan) }, delay)
            }
        }

        if (!plan.blocks(packageName)) {
            // Leaving a blocked app clears the debounce so returning to it
            // blocks again straight away.
            if (packageName != lastBlockedPackage) lastBlockedPackage = null
            return
        }

        val now = SystemClock.elapsedRealtime()
        val isRepeat = packageName == lastBlockedPackage &&
            now - lastBlockedAt < DEBOUNCE_MS
        if (isRepeat) return

        lastBlockedPackage = packageName
        lastBlockedAt = now
        showBlockScreen(packageName, detailKey = packageName)
    }

    private fun showBlockScreen(packageName: String, detailKey: String) {
        val intent = Intent(this, BlockOverlayActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
            )
            putExtra(BlockOverlayActivity.EXTRA_PACKAGE, packageName)
            putExtra(BlockOverlayActivity.EXTRA_DETAIL_KEY, detailKey)
        }
        startActivity(intent)
    }

    /**
     * Turns the browser away from a blocked site.
     *
     * Reads the address bar only: the page itself is never inspected, so this
     * sees the host you navigated to and nothing else about the browsing.
     */
    private fun checkBrowser(packageName: String, plan: Plan) {
        val viewId = WebRules.browserUrlBars[packageName] ?: return
        val bar = runCatching {
            rootInActiveWindow
                ?.findAccessibilityNodeInfosByViewId(viewId)
                ?.firstOrNull()
                ?.text
                ?.toString()
        }.getOrNull()

        val host = WebRules.hostOf(bar) ?: return
        val domain = WebRules.matches(host, plan.blockedDomains) ?: return

        showBlockScreen(packageName, detailKey = domain)
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    /**
     * Leaves a tamper screen: back first, so a dialog closes rather than the
     * whole task, then home to make sure the screen behind it is gone too.
     */
    private fun retreat() {
        performGlobalAction(GLOBAL_ACTION_BACK)
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    override fun onInterrupt() = Unit

    private companion object {
        const val TAG = "ControlA11y"

        /**
         * A blocked app can fire several window-state events while it starts
         * up. React once, then ignore the rest for a moment.
         */
        const val DEBOUNCE_MS = 600L

        /** Time to let a guarded window finish drawing before looking again. */
        const val RECHECK_DELAY_MS = 350L

        /** The address bar settles later than the window does. */
        val BROWSER_RECHECK_DELAYS_MS = longArrayOf(400L, 1200L)
    }
}
