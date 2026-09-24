package com.example.control.enforcement

import java.util.Locale

/**
 * The decision half of hard mode, with no Android types in it so it can be
 * unit-tested on the JVM.
 *
 * Worth the separation: the first version of these rules matched the Settings
 * home page and made Settings unopenable, because the app is called "Control",
 * the word appears inside "Device controls" and "Parental controls", and
 * "Accessibility" is an ordinary Settings menu entry. Those are exactly the
 * cases the tests below pin down.
 */
object TamperRules {

    /**
     * Every package that owns a route to removing an app.
     *
     * Settings and the package installers are the obvious two. The Play Store
     * has its own uninstall button, settings search can jump straight to the
     * app page, and most OEM skins ship a security or phone-manager app with a
     * bulk uninstaller. Missing one is a hole; watching one costs nothing,
     * because the text of a window is only read once its package is on this
     * list.
     */
    val guardedPackages = setOf(
        "com.android.settings",
        "com.android.settings.intelligence",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.vending",
        // OEM skins with their own app managers.
        "com.miui.securitycenter",
        "com.miui.cleanmaster",
        "com.samsung.android.lool",
        "com.samsung.android.sm",
        "com.samsung.android.sm_cn",
        "com.coloros.safecenter",
        "com.oplus.safecenter",
        "com.oppo.safe",
        "com.huawei.systemmanager",
        "com.oneplus.security",
        "com.transsion.phonemaster",
        "com.vivo.permissionmanager",
        "com.iqoo.secure",
    )

    /** Only ever shown for an admin app, so intent is proven by the class alone. */
    private val deviceAdminScreens = listOf(
        "DeviceAdminAdd",
        "DeviceAdminSettings",
    )

    /** Only ever exist to remove a package; the class stands in for the verb. */
    private val uninstallScreens = listOf(
        "UninstallerActivity",
        "UninstallAppProgress",
        "UninstallAlertDialog",
    )

    /**
     * Screens where a destructive action is even possible. Every other screen
     * is left alone however its text reads, which is what keeps the rest of
     * Settings usable.
     *
     * `SubSettings` hosts most Settings detail fragments, including app info
     * and the accessibility service page, so it has to be here despite being
     * generic. The label and verb gates carry the precision from there.
     */
    private val sensitiveScreens = uninstallScreens + listOf(
        "InstalledAppDetails",
        "AppInfoDashboard",
        "ApplicationDetails",
        "AppManagementActivity",
        "AppDetailsActivity",
        "ToggleAccessibilityService",
        "AccessibilityDetails",
        "SubSettings",
    )

    private val accessibilityServiceScreens = listOf(
        "ToggleAccessibilityService", "AccessibilityServiceDetails", "AccessibilityDetails",
    )

    /**
     * Lowercase, because the haystack is lowercased. Deliberately excludes the
     * bare word "accessibility": it appears on the Settings home page and in a
     * dozen unrelated menus, and the accessibility service page is already
     * caught by its class name.
     */
    private val dangerousActions = listOf(
        "uninstall",
        "deactivate",
        "force stop",
        "device admin",
        "clear storage",
        "clear data",
    )

    /**
     * Screens that are dangerous on their own, with no app name needed.
     *
     * Private DNS is the one setting that filters every app and browser at
     * once, so turning it off is a bypass for everything at once. It is a
     * system screen that never mentions Control, which is why it cannot go
     * through the app-name gate.
     */
    private val standaloneScreens = listOf(
        "PrivateDnsMode",
        "PrivateDnsPreference",
    )

    fun guards(packageName: String) = packageName in guardedPackages

    /**
     * True when this screen is an attempt to remove or disable the app.
     *
     * @param className the foreground activity or fragment class
     * @param screenText all visible text on the window, or null if unreadable
     * @param appLabel the app's own name
     */
    fun isTamperScreen(
        className: String?,
        screenText: String?,
        appLabel: String,
    ): Boolean {
        val screen = className.orEmpty()
        val text = screenText?.lowercase(Locale.ROOT)
        val label = appLabel.lowercase(Locale.ROOT)
        val namesApp = text != null && containsWord(text, label)
        // Service-specific detail pages often only say "Use Control", not "deactivate".
        if (namesApp && accessibilityServiceScreens.any { screen.contains(it, ignoreCase = true) }) {
            return true
        }
        if (namesApp &&
            (screen.contains("SubSettings", ignoreCase = true) || screen.contains("Dialog", ignoreCase = true))) {
            if (listOf("use $label", "turn off $label", "stop $label", "disable $label")
                    .any { containsWord(text, it) }) return true
        }
        if (deviceAdminScreens.any { screen.contains(it, ignoreCase = true) }) {
            return true
        }
        if (standaloneScreens.any { screen.contains(it, ignoreCase = true) }) {
            return true
        }
        if (!sensitiveScreens.any { screen.contains(it, ignoreCase = true) }) {
            return false
        }

        if (text == null || !namesApp) return false

        if (uninstallScreens.any { screen.contains(it, ignoreCase = true) }) {
            return true
        }
        return dangerousActions.any { text.contains(it) }
    }

    /**
     * Whole-word match, so a label that happens to be an ordinary English word
     * does not match every screen that uses it in a sentence.
     */
    fun containsWord(haystack: String, word: String): Boolean {
        if (word.isEmpty()) return false

        var index = haystack.indexOf(word)
        while (index >= 0) {
            val before = if (index == 0) ' ' else haystack[index - 1]
            val afterIndex = index + word.length
            val after = if (afterIndex >= haystack.length) ' ' else haystack[afterIndex]
            if (!before.isLetterOrDigit() && !after.isLetterOrDigit()) return true
            index = haystack.indexOf(word, index + 1)
        }
        return false
    }
}
