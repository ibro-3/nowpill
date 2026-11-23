package app.nowpill

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat

/**
 * NowPill "Today habits" list widget (Phase 27): every habit due today with
 * a per-row check pill. Rows come from the persisted snapshot via a
 * [RemoteViewsService].
 *
 * RemoteViews collections only support fill-in intents over one template, so
 * the template is a mutable broadcast to [WidgetActionReceiver]: pill taps
 * fill in `check:<id>`, label taps fill in `open` (the receiver launches the
 * app). Same apply path as the summary widget's check button.
 */
class NowPillHabitsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val snapshot = NowPillWidgetProvider.readSnapshot(context)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, snapshot))
        }
    }

    companion object {
        const val PAYLOAD_OPEN = "open"

        fun buildViews(
            context: Context,
            s: NowPillWidgetProvider.Snapshot
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.nowpill_habits_widget)
            views.setTextViewText(R.id.habits_progress, "${s.done}/${s.total}")

            val serviceIntent = Intent(context, NowPillHabitsWidgetService::class.java)
            views.setRemoteAdapter(R.id.habits_list, serviceIntent)
            views.setEmptyView(R.id.habits_list, R.id.habits_empty)

            // One mutable broadcast template; each row fills in its payload.
            val template = Intent(context, WidgetActionReceiver::class.java).apply {
                action = WidgetActionReceiver.ACTION_CHECK
            }
            val templatePending = PendingIntent.getBroadcast(
                context,
                2,
                template,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(R.id.habits_list, templatePending)
            return views
        }
    }
}

/** Supplies habit rows to the list widget from the persisted snapshot. */
class NowPillHabitsWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        HabitsRemoteViewsFactory(applicationContext)
}

class HabitsRemoteViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var rows: List<NowPillWidgetProvider.HabitRow> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        rows = NowPillWidgetProvider.readSnapshot(context).habits
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = rows[position]
        val views = RemoteViews(context.packageName, R.layout.nowpill_habit_row)
        views.setTextViewText(R.id.habit_row_name, row.name)
        views.setTextColor(R.id.habit_row_dot, row.color)

        // Label tap opens the app.
        views.setOnClickFillInIntent(
            R.id.habit_row_name,
            Intent().putExtra(
                WidgetActionReceiver.EXTRA_PAYLOAD,
                NowPillHabitsWidgetProvider.PAYLOAD_OPEN
            )
        )

        if (row.done) {
            views.setTextViewText(R.id.habit_row_pill, context.getString(R.string.widget_done))
            views.setInt(R.id.habit_row_pill, "setBackgroundResource", R.drawable.widget_pill_done)
            views.setTextColor(
                R.id.habit_row_pill,
                ContextCompat.getColor(context, R.color.widget_done_text)
            )
            views.setOnClickFillInIntent(
                R.id.habit_row_pill,
                Intent().putExtra(
                    WidgetActionReceiver.EXTRA_PAYLOAD,
                    NowPillHabitsWidgetProvider.PAYLOAD_OPEN
                )
            )
        } else {
            views.setTextViewText(R.id.habit_row_pill, pillLabel(row))
            views.setInt(R.id.habit_row_pill, "setBackgroundResource", R.drawable.widget_pill_open)
            views.setTextColor(
                R.id.habit_row_pill,
                ContextCompat.getColor(context, R.color.widget_check_text)
            )
            views.setOnClickFillInIntent(
                R.id.habit_row_pill,
                Intent().putExtra(
                    WidgetActionReceiver.EXTRA_PAYLOAD,
                    "check:${row.id}"
                )
            )
        }
        return views
    }

    private fun pillLabel(row: NowPillWidgetProvider.HabitRow): String {
        val amount = row.amount
        val target = row.target
        if (amount != null && target != null && target > 0) {
            // Measurable habit: show progress toward the goal.
            return "${fmt(amount)}/${fmt(target)}"
        }
        return context.getString(R.string.widget_check)
    }

    private fun fmt(d: Double): String =
        if (d == d.toLong().toDouble()) d.toLong().toString() else d.toString()

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = rows[position].id.toLong()

    override fun hasStableIds(): Boolean = true
}