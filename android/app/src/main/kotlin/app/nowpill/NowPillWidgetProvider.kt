package app.nowpill

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * NowPill home-screen widget: today's progress (done/total), a progress bar,
 * and the top habit streak. Tapping opens the app on the Today tab.
 *
 * The Flutter side pushes a JSON snapshot via the `app.nowpill/widget`
 * MethodChannel (see MainActivity); it is stored in shared preferences and
 * every widget instance is re-rendered.
 */
class NowPillWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val snapshot = readSnapshot(context)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, snapshot))
        }
    }

    companion object {
        private const val PREFS = "nowpill_widget"
        private const val KEY_SNAPSHOT = "snapshot"

        /** Persists the snapshot JSON and refreshes all widget instances. */
        fun updateFromJson(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_SNAPSHOT, json)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NowPillWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            val snapshot = parse(json)
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context, snapshot))
            }
        }

        private fun readSnapshot(context: Context): Snapshot {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_SNAPSHOT, null)
            return parse(json)
        }

        private fun parse(json: String?): Snapshot {
            if (json.isNullOrEmpty()) return Snapshot()
            return try {
                val o = JSONObject(json)
                Snapshot(
                    done = o.optInt("done", 0),
                    total = o.optInt("total", 0),
                    remaining = o.optInt("remaining", 0),
                    allDone = o.optBoolean("allDone", false),
                    topStreak = o.optInt("topStreak", 0),
                    topHabitName = o.optString("topHabitName", "")
                )
            } catch (e: Exception) {
                Snapshot()
            }
        }

        private fun buildViews(context: Context, s: Snapshot): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.nowpill_widget)
            views.setTextViewText(R.id.widget_progress, "${s.done}/${s.total}")
            val subtitle = when {
                s.total == 0 -> context.getString(R.string.widget_clear_day)
                s.allDone -> context.getString(R.string.widget_all_done)
                else -> context.getString(R.string.widget_remaining, s.remaining)
            }
            views.setTextViewText(R.id.widget_subtitle, subtitle)
            views.setProgressBar(R.id.widget_bar, 100, percent(s), false)
            val streakText = if (s.topStreak > 0 && s.topHabitName.isNotEmpty()) {
                context.getString(R.string.widget_streak, s.topStreak, s.topHabitName)
            } else {
                context.getString(R.string.widget_no_streak)
            }
            views.setTextViewText(R.id.widget_streak, streakText)

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            return views
        }

        private fun percent(s: Snapshot): Int =
            if (s.total <= 0) 0 else (s.done * 100 / s.total)
    }

    /** Parsed snapshot with safe defaults. */
    data class Snapshot(
        val done: Int = 0,
        val total: Int = 0,
        val remaining: Int = 0,
        val allDone: Boolean = false,
        val topStreak: Int = 0,
        val topHabitName: String = ""
    )
}
