package com.tinkerpro.support

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class RemindersWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val state = widgetData.getString("rem_state", "") ?: ""
        val badge = (widgetData.getString("rem_badge", "0") ?: "0").toIntOrNull() ?: 0
        val summary = widgetData.getString("rem_summary", "") ?: ""
        val updated = widgetData.getString("rem_updated", "") ?: ""
        val lines = LINE_IDS.indices.map { widgetData.getString("rem_line_$it", "") ?: "" }
        val fetchedAt = (widgetData.getString("rem_fetched_at", "0") ?: "0").toLongOrNull() ?: 0L

        val openIntent = openRemindersIntent(context)
        val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("tinkerprosupport://reminders/refresh"),
        )

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.reminders_widget)

            views.setTextViewText(
                R.id.rem_summary,
                when {
                    summary.isNotEmpty() -> summary
                    state.isEmpty() -> "Open TinkerPro Support to load your reminders"
                    else -> "All caught up"
                },
            )

            if (badge > 0) {
                views.setTextViewText(R.id.rem_badge, if (badge > 99) "99+" else badge.toString())
                views.setViewVisibility(R.id.rem_badge, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.rem_badge, View.GONE)
            }

            LINE_IDS.forEachIndexed { index, viewId ->
                val text = lines[index]
                if (text.isNotEmpty()) {
                    views.setTextViewText(viewId, "•  $text")
                    views.setViewVisibility(viewId, View.VISIBLE)
                } else {
                    views.setViewVisibility(viewId, View.GONE)
                }
            }

            views.setTextViewText(R.id.rem_updated, updated)
            views.setViewVisibility(R.id.rem_updated, if (updated.isEmpty()) View.GONE else View.VISIBLE)

            views.setOnClickPendingIntent(R.id.rem_root, openIntent)
            views.setOnClickPendingIntent(R.id.rem_refresh, refreshIntent)

            appWidgetManager.updateAppWidget(id, views)
        }

        if (state == "ok" && System.currentTimeMillis() - fetchedAt > STALE_AFTER_MS) {
            try {
                refreshIntent.send()
            } catch (e: Throwable) {
            }
        }
    }

    private fun openRemindersIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = Uri.parse("tinkerprosupport://reminders")
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        if (Build.VERSION.SDK_INT < 34) {
            return PendingIntent.getActivity(context, REQUEST_OPEN, intent, flags)
        }
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 35) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
            )
        } else {
            options.pendingIntentBackgroundActivityStartMode =
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        }
        return PendingIntent.getActivity(context, REQUEST_OPEN, intent, flags, options.toBundle())
    }

    companion object {
        private const val STALE_AFTER_MS = 45L * 60L * 1000L
        private const val REQUEST_OPEN = 4101

        private val LINE_IDS = intArrayOf(
            R.id.rem_line_0,
            R.id.rem_line_1,
            R.id.rem_line_2,
            R.id.rem_line_3,
        )
    }
}
