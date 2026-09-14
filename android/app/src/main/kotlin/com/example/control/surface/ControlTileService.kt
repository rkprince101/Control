package com.example.control.surface

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.example.control.MainActivity
import com.example.control.enforcement.PlanStore

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
        val blocked = PlanStore(this).read().blockedPackages.size

        tile.state = if (blocked > 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(com.example.control.R.string.app_name)
        tile.subtitle = if (blocked == 0) {
            getString(com.example.control.R.string.tile_nothing_blocked)
        } else {
            resources.getQuantityString(
                com.example.control.R.plurals.tile_blocked,
                blocked,
                blocked,
            )
        }
        tile.updateTile()
    }
}
