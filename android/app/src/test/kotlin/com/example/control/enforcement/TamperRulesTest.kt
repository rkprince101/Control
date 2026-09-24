package com.example.control.enforcement

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The regression suite for hard mode.
 *
 * The first version of these rules closed the Settings app entirely: the app is
 * called "Control", that word is a substring of "Device controls", and
 * "Accessibility" is an ordinary menu entry, so the home page matched. Anything
 * that loosens the gates has to keep the "leaves alone" cases below passing.
 */
class TamperRulesTest {

    private val label = "Control"

    private fun tamper(className: String?, text: String?) =
        TamperRules.isTamperScreen(className, text, label)

    // Screens that must be closed --------------------------------------------

    @Test
    fun `device admin removal is caught by class alone`() {
        assertTrue(tamper("com.android.settings.DeviceAdminAdd", null))
    }

    @Test
    fun `uninstall confirmation naming the app is caught`() {
        assertTrue(
            tamper(
                "com.android.packageinstaller.UninstallerActivity",
                "Do you want to uninstall this app? Control",
            ),
        )
    }

    @Test
    fun `app info page offering uninstall is caught`() {
        assertTrue(
            tamper(
                "com.android.settings.applications.InstalledAppDetails",
                "Control App info Uninstall Force stop Storage",
            ),
        )
    }

    @Test
    fun `the accessibility page for this app is caught`() {
        assertTrue(
            tamper(
                "com.android.settings.SubSettings",
                "Control Use Control Deactivate service",
            ),
        )
    }

    @Test
    fun `the private dns screen is caught without naming the app`() {
        // It never mentions Control, and switching it off unblocks every
        // filtered site in every app at once.
        assertTrue(
            tamper("com.android.settings.network.PrivateDnsModeDialogFragment", null),
        )
    }

    // Screens that must be left alone ----------------------------------------

    @Test
    fun `the settings home page is left alone`() {
        // The exact screen the first version broke: no dangerous class, and the
        // label only appears inside longer words.
        assertFalse(
            tamper(
                "com.android.settings.homepage.SettingsHomepageActivity",
                "Network and internet Connected devices Apps Notifications " +
                    "Accessibility Device controls Parental controls",
            ),
        )
    }

    @Test
    fun `a sensitive screen about a different app is left alone`() {
        assertFalse(
            tamper(
                "com.android.settings.applications.InstalledAppDetails",
                "Instagram App info Uninstall Force stop",
            ),
        )
    }

    @Test
    fun `a screen merely containing the label as a substring is left alone`() {
        assertFalse(
            tamper(
                "com.android.settings.SubSettings",
                "Parental controls Device controls Uninstall unused apps",
            ),
        )
    }

    @Test
    fun `an unreadable window on a harmless screen is left alone`() {
        assertFalse(tamper("com.android.settings.Settings", null))
    }

    // Package gate ------------------------------------------------------------

    @Test
    fun `service toggle and disable confirmation need this app identity`() {
        assertTrue(tamper("com.android.settings.accessibility.ToggleAccessibilityService", "Control On"))
        assertTrue(tamper("com.android.settings.SubSettings", "Control Use Control On"))
        assertTrue(tamper("android.app.AlertDialog", "Turn off Control? Stop"))
        assertFalse(tamper("com.android.settings.accessibility.ToggleAccessibilityService", "TalkBack On"))
        assertFalse(tamper("com.android.settings.SubSettings", "Accessibility Installed apps Control TalkBack"))
        assertFalse(tamper("com.android.settings.SettingsHomepageActivity", "Accessibility Control"))
        assertFalse(tamper("android.app.AlertDialog", "Turn off TalkBack? Control"))
    }

    @Test
    fun `the store and oem managers are guarded, ordinary apps are not`() {
        assertTrue(TamperRules.guards("com.android.vending"))
        assertTrue(TamperRules.guards("com.miui.securitycenter"))
        assertTrue(TamperRules.guards("com.android.settings"))
        assertFalse(TamperRules.guards("com.instagram.android"))
    }

    // Word matching -----------------------------------------------------------

    @Test
    fun `whole word matching ignores longer words that contain it`() {
        assertTrue(TamperRules.containsWord("uninstall control ?", "control"))
        assertTrue(TamperRules.containsWord("control", "control"))
        assertFalse(TamperRules.containsWord("device controls", "control"))
        assertFalse(TamperRules.containsWord("parental controls only", "control"))
    }
}
