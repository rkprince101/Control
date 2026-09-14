package com.example.control.enforcement

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-asserts enforcement after a restart.
 *
 * Most of it survives a reboot on its own: Android restarts enabled
 * accessibility services, and the plan, the hard-mode flag and every lock are
 * on disk. What does not survive is the arithmetic. A plan computed yesterday
 * still names the apps that were blocked yesterday, so a schedule that should
 * have flipped overnight stays wrong until the app is next opened.
 *
 * Until a wake-up alarm exists, the honest fix is to keep enforcing the last
 * plan rather than dropping it, and to mark it stale so the next launch
 * recomputes immediately. Dropping the shield on a reboot would make a restart
 * the easiest bypass in the app.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        val plan = PlanStore(context).read()
        Log.i(
            TAG,
            "restored plan after ${intent.action}: " +
                "${plan.blockedPackages.size} apps, " +
                "${plan.blockedDomains.size} sites, " +
                "hard mode ${TamperGuard(context).enabled}",
        )
    }

    private companion object {
        const val TAG = "ControlBoot"
    }
}
