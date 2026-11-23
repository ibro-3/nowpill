package app.nowpill

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * NowPill summary home-screen widget: today's progress (done/total), a
 * progress bar, the top habit streak, and (v0.4) a one-tap check-in button
 * for the next undone habit. Tapping the body opens the app on Today.
 *
 * The Flutter side pushes a JSON snapshot via the `app.nowpill/widget`
 * MethodChannel (see MainActivity); widget check-in taps come back through
 * [WidgetActionReceiver]. Both paths persist the snapshot and re-render
 * every instance of both widget providers.
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
            refreshAll(context)
        }

        /** Re-renders every instance of both widget providers from prefs. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val snapshot = readSnapshot(context)

            val summary = ComponentName(context, NowPillWidgetProvider::class.java)
            for (id in manager.getAppWidgetIds(summary)) {
                manager.updateAppWidget(id, buildViews(context, snapshot))
            }

            val habits = ComponentName(context, NowPillHabitsWidgetProvider::class.java)
            val habitIds = manager.getAppWidgetIds(habits)
            if (habitIds.isNotEmpty()) {
                // List rows are rebuilt by the RemoteViewsFactory from prefs.
                manager.notifyAppWidgetViewDataChanged(habitIds, R.id.habits_list)
                for (id in habitIds) {
                    manager.updateAppWidget(
                        id, NowPillHabitsWidgetProvider.buildViews(context, snapshot)
                    )
                }
            }
        }

        fun readSnapshot(context: Context): Snapshot {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_SNAPSHOT, null)
            return parse(json)
        }

        fun parse(json: String?): Snapshot {
            if (json.isNullOrEmpty()) return Snapshot()
            return try {
                val o = JSONObject(json)
                val habits = mutableListOf<HabitRow>()
                o.optJSONArray("habits")?.let { arr ->
                    for (i in 0 until arr.length()) {
                        val h = arr.optJSONObject(i) ?: continue
                        habits.add(
                            HabitRow(
                                id = h.optInt("id", -1),
                                name = h.optString("name", ""),
                                done = h.optBoolean("done", false),
                                color = h.optInt("color", 0xFF2DD4A8.toInt()),
                                amount = if (h.isNull("amount")) null else h.optDouble("amount"),
                                target = if (h.isNull("target")) null else h.optDouble("target")
                            )
                        )
                    }
                }
                Snapshot(
                    done = o.optInt("done", 0),
                    total = o.optInt("total", 0),
                    remaining = o.optInt("remaining", 0),
                    allDone = o.optBoolean("allDone", false),
                    topStreak = o.optInt("topStreak", 0),
                    topHabitName = o.optString("topHabitName", ""),
                    habits = habits
                )
            } catch (e: Exception) {
                Snapshot()
            }
        }

        fun buildViews(context: Context, s: Snapshot): RemoteViews {
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

            // v0.4: one-tap check-in for the next undone habit.
            val next = s.habits.firstOrNull { !it.done && it.id >= 0 }
            if (next != null) {
                views.setViewVisibility(R.id.widget_check_row, View.VISIBLE)
                views.setTextViewText(R.id.widget_check_name, next.name)
                views.setTextColor(R.id.widget_check_name, next.color)
                views.setOnClickPendingIntent(
                    R.id.widget_check_button,
                    WidgetActionReceiver.checkPendingIntent(context, next.id)
                )
            } else {
                views.setViewVisibility(R.id.widget_check_row, View.GONE)
            }

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
        val topHabitName: String = "",
        val habits: List<HabitRow> = emptyList()
    )

    /** One habit row in the snapshot (v2). */
    data class HabitRow(
        val id: Int,
        val name: String,
        val done: Boolean,
        val color: Int,
        val amount: Double?,
        val target: Double?
    )
}