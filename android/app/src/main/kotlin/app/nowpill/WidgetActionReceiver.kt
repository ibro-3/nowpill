package app.nowpill

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Handles check-in taps from the home-screen widgets (Phase 27).
 *
 * Routing mirrors the notification-action split (Phase 22):
 *  * App foregrounded → the live engine's `app.nowpill/widget_action` handler
 *    applies through the shared database (reactive streams update instantly).
 *  * App closed → a headless FlutterEngine runs the `widgetActionMain` entry
 *    point, opens the same database file, applies the check-in, and returns
 *    the fresh snapshot JSON.
 *
 * Either way the returned snapshot is persisted and every widget instance of
 * both providers is re-rendered. No UI is launched.
 */
class WidgetActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CHECK) return
        val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: return
        val appContext = context.applicationContext

        // List-widget label taps: open the app on Today.
        if (payload == NowPillHabitsWidgetProvider.PAYLOAD_OPEN) {
            appContext.startActivity(
                Intent(appContext, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
            )
            return
        }
        val pendingResult = goAsync()

        val live = NowPillEngineHolder.engine
        if (live != null) {
            // Foreground path: the app's own isolate owns the database.
            MethodChannel(live.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("apply", payload, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        finish(appContext, result as? String)
                        pendingResult.finish()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        pendingResult.finish()
                    }

                    override fun notImplemented() {
                        pendingResult.finish()
                    }
                })
            return
        }

        // Background path: headless engine at the widgetActionMain entry point.
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(appContext)
            loader.ensureInitializationComplete(appContext, null)
            val engine = FlutterEngine(appContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "widgetActionMain")
            )
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            // Dart registers its handler synchronously in the entry point;
            // invokeMethod queues until the isolate is ready.
            channel.invokeMethod("apply", payload, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    finish(appContext, result as? String)
                    destroySoon(engine)
                    pendingResult.finish()
                }

                override fun error(code: String, message: String?, details: Any?) {
                    destroySoon(engine)
                    pendingResult.finish()
                }

                override fun notImplemented() {
                    destroySoon(engine)
                    pendingResult.finish()
                }
            })
        } catch (e: Exception) {
            // Guarded: a widget tap must never crash the launcher process.
            pendingResult.finish()
        }
    }

    /**
     * Destroys the one-shot engine on the next main-loop turn so the binary
     * messenger can finish acknowledging the method reply; destroying inline
     * detaches FlutterJNI mid-reply and logs a harmless warning.
     */
    private fun destroySoon(engine: FlutterEngine) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { engine.destroy() }
    }

    private fun finish(context: Context, snapshotJson: String?) {
        if (snapshotJson != null) {
            NowPillWidgetProvider.updateFromJson(context, snapshotJson)
        } else {
            // Action failed or habit gone: re-render from the last snapshot so
            // the pill state stays truthful.
            NowPillWidgetProvider.refreshAll(context)
        }
    }

    companion object {
        const val ACTION_CHECK = "app.nowpill.widget.CHECK"
        const val EXTRA_PAYLOAD = "payload"
        const val CHANNEL = "app.nowpill/widget_action"

        /** Broadcast PendingIntent for a habit check pill (`check:<id>`). */
        fun checkPendingIntent(context: Context, habitId: Int): PendingIntent {
            val intent = Intent(context, WidgetActionReceiver::class.java).apply {
                action = ACTION_CHECK
                putExtra(EXTRA_PAYLOAD, "check:$habitId")
                // Unique data URI so each habit gets a distinct PendingIntent.
                data = android.net.Uri.parse("nowpill://widget-check/$habitId")
            }
            return PendingIntent.getBroadcast(
                context,
                habitId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}