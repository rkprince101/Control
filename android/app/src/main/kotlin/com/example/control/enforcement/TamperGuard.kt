package com.example.control.enforcement

import android.content.Context
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale

/**
 * Hard mode: backs out of the screens that lead to removing Control.
 *
 * Plain device admin no longer stops an uninstall on current Android. Settings
 * offers "Deactivate and uninstall" as a single step, so admin buys a
 * confirmation dialog and nothing more. The two ways past that are device
 * owner, which costs a factory reset, and this: notice the tamper screen and
 * leave it.
 *
 * It is a deterrent, not a wall. Safe mode does not start accessibility
 * services, and turning App blocking off before opening Settings walks straight
 * through. The app says as much rather than overselling it.
 *
 * This class holds the Android plumbing only. The matching rules live in
 * [TamperRules], where they can be tested.
 */
class TamperGuard(context: Context) {

    private val context = context.applicationContext
    private val prefs
        get() = EnforcementStorage.preferences(context, PREFS)

    private val appLabel: String = runCatching {
        val info = context.applicationInfo
        context.packageManager.getApplicationLabel(info).toString()
    }.getOrDefault("Control")

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    fun guards(packageName: String) = enabled && TamperRules.guards(packageName)

    fun isTamperScreen(className: CharSequence?, root: AccessibilityNodeInfo?): Boolean =
        root != null && guards(root.packageName?.toString().orEmpty()) && TamperRules.isTamperScreen(
            className = className?.toString(),
            screenText = collectText(root),
            appLabel = appLabel,
        )

    /**
     * Flattens the visible text of a window.
     *
     * Depth-limited and node-capped: this runs on the main thread of an
     * accessibility service, and a runaway walk of a dense settings screen is
     * felt as system-wide jank.
     */
    private fun collectText(root: AccessibilityNodeInfo): String {
        val builder = StringBuilder()
        var visited = 0

        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > MAX_DEPTH || visited > MAX_NODES) return
            visited++

            node.text?.let { builder.append(it).append(' ') }
            node.contentDescription?.let { builder.append(it).append(' ') }

            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                try {
                    walk(child, depth + 1)
                } finally {
                    @Suppress("DEPRECATION")
                    child.recycle()
                }
            }
        }

        walk(root, 0)
        return builder.toString().lowercase(Locale.ROOT)
    }

    private companion object {
        const val PREFS = "control_guard"
        const val KEY_ENABLED = "hardMode"

        const val MAX_DEPTH = 12
        const val MAX_NODES = 400
    }
}
