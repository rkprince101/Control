package com.example.control.surface

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.control.MainActivity
import com.example.control.R

/**
 * Home-screen widget: today's screen time and focus, without opening the app.
 *
 * Reads the cached [Summary] rather than computing anything. A widget update
 * runs in a broadcast receiver with no Flutter engine, so anything it cannot
 * read from a file it cannot show.
 */
class ControlWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        val summary = SummaryStore(context).read()

        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_control).apply {
                setTextViewText(R.id.widget_screen_time, summary.screenTime)
                setTextViewText(R.id.widget_focus, summary.focusToday)
                setTextViewText(
                    R.id.widget_blocked,
                    if (summary.blockedCount == 0) {
                        context.getString(R.string.widget_nothing_blocked)
                    } else {
                        context.resources.getQuantityString(
                            R.plurals.tile_blocked,
                            summary.blockedCount,
                            summary.blockedCount,
                        )
                    },
                )
                setOnClickPendingIntent(R.id.widget_root, openApp(context))
            }
            manager.updateAppWidget(id, views)
        }
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        /** Called after Dart writes a new summary, so the widget is never stale. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ControlWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return

            context.sendBroadcast(
                Intent(context, ControlWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                },
            )
        }
    }
}
