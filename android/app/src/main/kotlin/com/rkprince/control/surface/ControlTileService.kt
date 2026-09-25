package com.rkprince.control.surface

import android.app.PendingIntent
import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.rkprince.control.MainActivity
import com.rkprince.control.enforcement.PlanStore
import com.rkprince.control.enforcement.EnforcementClock
import com.rkprince.control.insights.AppCategoryResolver
import com.rkprince.control.insights.InstalledAppsReader

/**
 * Quick Settings tile: how much is blocked right now, one swipe from anywhere.
 *
 * Read-only on purpose. A tile that toggled blocking would be a bypass sitting
 * in the notification shade, reachable from the lock screen, which is precisely
 * the opposite of what this app is for.
 */
class ControlTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    // The PendingIntent overload does not exist before API 34; the legacy call is guarded.
    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // The Intent overload was removed in favour of a PendingIntent in
            // API 34, and throws if called there.
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun render() {
        val tile = qsTile ?: return
        val plan = PlanStore(this).read()
        val candidates = if (plan.rules?.any { it.categories.isNotEmpty() } == true) {
            InstalledAppsReader(this).launchable().map { it.packageName }.toSet()
        } else emptySet()
        val blocked = plan.effectivePackages(
            candidates, AppCategoryResolver(this)::categories, EnforcementClock.now(this),
        ).size

        tile.state = if (blocked > 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(com.rkprince.control.R.string.app_name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (blocked == 0) {
                getString(com.rkprince.control.R.string.tile_nothing_blocked)
            } else {
                resources.getQuantityString(
                    com.rkprince.control.R.plurals.tile_blocked,
                    blocked,
                    blocked,
                )
            }
        }
        tile.updateTile()
    }
}
