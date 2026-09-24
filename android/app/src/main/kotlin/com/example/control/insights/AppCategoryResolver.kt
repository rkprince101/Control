package com.example.control.insights

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.telecom.TelecomManager

/** Capability-based tokens, shared by the picker and live enforcement. */
object AppCategoryRules {
    fun canBlockBeforeUnlock(systemApp: Boolean, essential: Boolean): Boolean =
        !systemApp && !essential

    fun categories(launchable: Boolean, essential: Boolean, browser: Boolean, game: Boolean): Set<String> =
        if (essential) emptySet() else buildSet {
            if (launchable) add("all_apps")
            if (browser) add("browsers")
            if (game) add("games")
        }
}

class AppCategoryResolver(context: Context) {
    private val context = context.applicationContext
    private val manager = context.packageManager
    private data class Capabilities(val launchable: Boolean, val browser: Boolean, val game: Boolean)
    private val cache = mutableMapOf<String, Capabilities>()
    private var seenGeneration = -1L
    private var expiresAt = 0L

    @Synchronized
    fun categories(packageName: String): Set<String> {
        val now = SystemClock.elapsedRealtime()
        if (seenGeneration != generation || now >= expiresAt) {
            cache.clear()
            seenGeneration = generation
            expiresAt = now + 30_000L
        }
        // Resolve on cache miss rather than depending on an install broadcast arriving first.
        val info = cache[packageName] ?: runCatching {
            val app = manager.getApplicationInfo(packageName, 0)
            @Suppress("DEPRECATION")
            val legacyGame = app.flags and ApplicationInfo.FLAG_IS_GAME != 0
            Capabilities(
                launchable = handles(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), packageName),
                browser = handles(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER), packageName) ||
                    listOf("http", "https").any { scheme ->
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("$scheme://control-category-check.invalid/"))
                            .addCategory(Intent.CATEGORY_BROWSABLE).setPackage(packageName)
                        manager.queryIntentActivities(intent, PackageManager.GET_RESOLVED_FILTER).any {
                            // App links to one site do not make an app a general browser.
                            val filter = it.filter
                            filter != null && filter.countDataAuthorities() == 0 && filter.countDataPaths() == 0
                        }
                    },
                game = legacyGame || (Build.VERSION.SDK_INT >= 26 && app.category == ApplicationInfo.CATEGORY_GAME),
            )
        }.getOrNull()?.also { cache[packageName] = it } ?: return emptySet()

        // Roles can change without a package install. Never cache the safety decision.
        return AppCategoryRules.categories(info.launchable, isEssential(packageName), info.browser, info.game)
    }

    private fun handles(intent: Intent, packageName: String): Boolean =
        manager.queryIntentActivities(intent.setPackage(packageName), 0).isNotEmpty()

    fun canBlockBeforeUnlock(packageName: String): Boolean = runCatching {
        val flags = manager.getApplicationInfo(packageName, 0).flags
        AppCategoryRules.canBlockBeforeUnlock(
            systemApp = flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0,
            essential = isEssential(packageName),
        )
    }.getOrDefault(false)

    private fun isEssential(packageName: String): Boolean {
        if (packageName == context.packageName || packageName in criticalPackages) return true
        return runCatching {
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val homePackage = manager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo?.packageName
            val dialer = (context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage
            val flags = manager.getApplicationInfo(packageName, 0).flags
            val systemApp = flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            // Declaring a phone/home intent must not exempt an arbitrary new browser.
            // Protect actual selected roles and trusted system fallback handlers.
            packageName == homePackage || packageName == dialer || (systemApp && (
                handles(home, packageName) ||
                    handles(Intent(Intent.ACTION_DIAL, Uri.parse("tel:")), packageName) ||
                    handles(Intent("android.intent.action.EMERGENCY_DIAL"), packageName) ||
                    handles(Intent("android.intent.action.MANAGE_PERMISSIONS"), packageName)
                ))
        }.getOrDefault(true) // Unknown safety state must not block critical system flows.
    }

    companion object {
        @Volatile private var generation = 0L
        @Synchronized fun invalidate() { generation++ }

        private val criticalPackages = setOf(
            "android", "com.android.systemui", "com.android.phone", "com.android.server.telecom",
            "com.android.emergency", "com.google.android.apps.safetyhub",
            "com.android.permissioncontroller", "com.google.android.permissioncontroller",
            "com.android.packageinstaller", "com.google.android.packageinstaller",
            // Settings remains usable; hard mode guards only specific tamper screens.
            "com.android.settings", "com.android.settings.intelligence",
        )
    }
}

class PackageChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in setOf(Intent.ACTION_PACKAGE_ADDED, Intent.ACTION_PACKAGE_REMOVED,
                Intent.ACTION_PACKAGE_REPLACED, Intent.ACTION_PACKAGE_CHANGED)) {
            AppCategoryResolver.invalidate()
        }
    }
}
