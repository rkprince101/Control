package com.rkprince.control.enforcement

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.rkprince.control.surface.HabitReminders
import com.rkprince.control.surface.WeeklyReport

/**
 * Restores inputs without starting Flutter. Android rebinds enabled accessibility
 * services itself; apps cannot force that binding or enable a disabled service.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!handles(intent.action)) return

        // Warm/migrate the persisted inputs; native rules evaluate current time
        // when the service connects, not the old flattened package snapshot.
        runCatching {
            val plan = PlanStore(context).read()
            TamperGuard(context).enabled
            EnforcementClock.now(context)
            Log.i(TAG, "loaded ${plan.rules?.size ?: 0} native rules after ${intent.action}")
        }.onFailure { Log.e(TAG, "Could not restore enforcement inputs", it) }

        // Reminders and the weekly report live in credential-protected
        // storage, which is still shut at locked boot; the unlocked boot that
        // follows puts them back. Android drops every alarm on reboot.
        if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            runCatching {
                HabitReminders.rescheduleAll(context)
                WeeklyReport.restore(context)
            }.onFailure { Log.e(TAG, "Could not restore reminders and reports", it) }
        }
    }

    companion object {
        private const val TAG = "ControlBoot"

        internal fun handles(action: String?): Boolean =
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
                action == Intent.ACTION_BOOT_COMPLETED ||
                action == Intent.ACTION_MY_PACKAGE_REPLACED
    }
}
