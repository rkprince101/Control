package com.example.control.enforcement

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.UserManager
import com.example.control.R

/**
 * Blocks deletion of the app itself.
 *
 * Two rungs, and the difference matters enough that the UI names both:
 *
 *  - **Device admin.** Granted from a normal dialog. While it is active Android
 *    refuses to uninstall the app; the user has to deactivate admin first,
 *    which is one tap in Settings. Real friction, not a wall.
 *  - **Device owner.** Provisioned with `adb shell dpm set-device-owner` on a
 *    device with no accounts, so in practice after a factory reset. Unlocks
 *    `setUninstallBlocked` and system restrictions. The app's release path can
 *    undo these; recovery and factory reset remain outside its guarantees.
 */
class ControlDeviceAdminReceiver : DeviceAdminReceiver() {

    /**
     * Shown on the confirmation screen when the user tries to strip admin.
     * The last thing standing between a craving and an uninstall, so it states
     * the consequence plainly rather than warning about "reduced functionality".
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        context.getString(R.string.device_admin_disable_warning)
}

object DeviceAdmin {

    fun component(context: Context) =
        ComponentName(context, ControlDeviceAdminReceiver::class.java)

    private fun policyManager(context: Context) =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun isAdminActive(context: Context): Boolean =
        policyManager(context).isAdminActive(component(context))

    fun isDeviceOwner(context: Context): Boolean =
        policyManager(context).isDeviceOwnerApp(context.packageName)

    /** Intent for the system dialog that grants device admin. */
    fun activationIntent(context: Context): Intent =
        Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, component(context))
            .putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                context.getString(R.string.device_admin_explanation),
            )
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Hard uninstall block. Only a device owner may call this; for a plain
     * admin it is a no-op and the weaker admin-level protection is all there is.
     */
    fun setUninstallBlocked(context: Context, blocked: Boolean): Boolean {
        if (!isDeviceOwner(context)) return false
        return runCatching {
            policyManager(context).setUninstallBlocked(
                component(context),
                context.packageName,
                blocked,
            )
            // The uninstall block on its own still leaves force stop, safe
            // mode and adb open, so the restrictions travel with it.
            setOwnerRestrictions(context, blocked)
            true
        }.getOrDefault(false)
    }

    fun isUninstallBlocked(context: Context): Boolean = runCatching {
        policyManager(context).isUninstallBlocked(component(context), context.packageName)
    }.getOrDefault(false)

    /**
     * The restrictions that close the routes hard mode cannot reach.
     *
     * Hard mode lives inside an accessibility service, so anything that stops
     * the service also stops the guard: force stop, safe mode, adb. These are
     * the matching system restrictions, and only a device owner may set them.
     * Applied together, because leaving one open makes the others decorative.
     */
    private val ownerRestrictions = listOf(
        // Force stop and clear data, both on the app info screen.
        UserManager.DISALLOW_APPS_CONTROL,
        // Safe mode does not start accessibility services at all.
        "no_safe_boot",
        // adb uninstall, and adb in general.
        UserManager.DISALLOW_DEBUGGING_FEATURES,
        // A second user can uninstall the app from their own side.
        UserManager.DISALLOW_ADD_USER,
        // The Settings path to a wipe. Recovery is still open; nothing can
        // close that.
        UserManager.DISALLOW_FACTORY_RESET,
    ) + if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        // Prevent clock changes from skipping schedules or expiring grants early.
        listOf(UserManager.DISALLOW_CONFIG_DATE_TIME)
    } else emptyList()

    /**
     * Turns the extra restrictions on or off. No-op unless device owner.
     *
     * Returns the number applied, so the UI can tell "not device owner" apart
     * from "this build refused one of them", which happens on some OEM ROMs.
     */
    fun setOwnerRestrictions(context: Context, enabled: Boolean): Int {
        if (!isDeviceOwner(context)) return 0

        val manager = policyManager(context)
        val admin = component(context)
        var applied = 0

        for (restriction in ownerRestrictions) {
            runCatching {
                if (enabled) {
                    manager.addUserRestriction(admin, restriction)
                } else {
                    manager.clearUserRestriction(admin, restriction)
                }
                applied++
            }
        }
        return applied
    }

    /**
     * Whether this device could still be provisioned as device owner.
     *
     * `isProvisioningAllowed` is the same check the system runs: it returns
     * false once any account is added, once the device is already provisioned,
     * and on secondary users. That makes it the honest answer to "will the adb
     * command work", which is otherwise only discoverable by trying it.
     */
    fun isProvisioningAllowed(context: Context): Boolean = runCatching {
        policyManager(context)
            .isProvisioningAllowed(DevicePolicyManager.ACTION_PROVISION_MANAGED_DEVICE)
    }.getOrDefault(false)

    /** The component string the `dpm set-device-owner` command needs. */
    fun ownerComponent(context: Context): String =
        component(context).flattenToShortString()

    /** Releases admin so the app can be uninstalled normally. */
    fun deactivate(context: Context) {
        if (isDeviceOwner(context)) {
            setUninstallBlocked(context, false)
            setOwnerRestrictions(context, false)
        }
        if (isAdminActive(context)) {
            policyManager(context).removeActiveAdmin(component(context))
        }
    }
}
