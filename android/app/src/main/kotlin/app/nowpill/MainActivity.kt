package app.nowpill

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Home-screen widget bridge: the Flutter side pushes a today-summary
        // JSON snapshot whenever the data changes (Phase 15).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.nowpill/widget"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSnapshot" -> {
                    val json = call.arguments as? String
                    if (json == null) {
                        result.error("invalid_args", "Expected a JSON string", null)
                    } else {
                        NowPillWidgetProvider.updateFromJson(applicationContext, json)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
