package app.nowpill

import io.flutter.embedding.engine.FlutterEngine

/**
 * Tracks the live FlutterEngine so widget taps can be routed to the app's
 * own isolate while it is running (Phase 27). Set in MainActivity's
 * configureFlutterEngine / cleanUpFlutterEngine; null while the app is closed.
 */
object NowPillEngineHolder {
    @Volatile
    var engine: FlutterEngine? = null
}