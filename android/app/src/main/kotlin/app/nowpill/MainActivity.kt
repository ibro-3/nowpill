package app.nowpill

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val syncChannelName = "app.nowpill/sync"
    private val openTreeRequestCode = 4711
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Widget taps route to this live engine while the app is running
        // (Phase 27); the receiver falls back to a headless engine otherwise.
        NowPillEngineHolder.engine = flutterEngine
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

        // File-sync folder bridge (Phase 19): SAF tree picker with persistable
        // permission + DocumentFile reads/writes for the sync coordinator.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            syncChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> {
                    if (pendingPickResult != null) {
                        result.error("busy", "A folder pick is already in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                    }
                    startActivityForResult(intent, openTreeRequestCode)
                }
                "isAccessible" -> {
                    val uri = call.arguments as? String
                    val tree = uri?.let { DocumentFile.fromTreeUri(this, Uri.parse(it)) }
                    result.success(tree != null && tree.canRead() && tree.canWrite())
                }
                "readOthers" -> {
                    val args = call.arguments as? Map<*, *>
                    val treeUri = args?.get("treeUri") as? String
                    val exclude = args?.get("exclude") as? String
                    val tree = treeUri?.let { DocumentFile.fromTreeUri(this, Uri.parse(it)) }
                    if (tree == null || !tree.canRead()) {
                        result.success(emptyList<Any>())
                        return@setMethodCallHandler
                    }
                    val files = mutableListOf<Map<String, String>>()
                    for (f in tree.listFiles()) {
                        val name = f.name ?: continue
                        if (!f.isFile) continue
                        if (!name.startsWith("nowpill-sync-") || !name.endsWith(".json")) continue
                        if (name == exclude) continue
                        try {
                            val content = contentResolver.openInputStream(f.uri)
                                ?.bufferedReader()?.use { it.readText() }
                            if (content != null) {
                                files.add(mapOf("name" to name, "content" to content))
                            }
                        } catch (e: Exception) {
                            // Partial/unreadable file mid-copy: skip, retry next poll.
                        }
                    }
                    result.success(files)
                }
                "write" -> {
                    val args = call.arguments as? Map<*, *>
                    val treeUri = args?.get("treeUri") as? String
                    val fileName = args?.get("fileName") as? String
                    val content = args?.get("content") as? String
                    val tree = treeUri?.let { DocumentFile.fromTreeUri(this, Uri.parse(it)) }
                    if (tree == null || fileName == null || content == null || !tree.canWrite()) {
                        result.error("write_failed", "Folder not writable", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // Write to a temp document then rename over the target so
                        // readers never see a half-written envelope.
                        val tmpName = "$fileName.tmp"
                        tree.findFile(tmpName)?.delete()
                        val tmp = tree.createFile("application/json", tmpName)
                        if (tmp == null) {
                            result.error("write_failed", "Could not create file", null)
                            return@setMethodCallHandler
                        }
                        contentResolver.openOutputStream(tmp.uri, "wt")?.use {
                            it.write(content.toByteArray(Charsets.UTF_8))
                            it.flush()
                        }
                        tree.findFile(fileName)?.delete()
                        if (!tmp.renameTo(fileName)) {
                            result.error("write_failed", "Rename failed", null)
                            return@setMethodCallHandler
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("write_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Only clear the holder if it still points at this engine (a new
        // activity may already have registered its own).
        if (NowPillEngineHolder.engine === flutterEngine) {
            NowPillEngineHolder.engine = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != openTreeRequestCode) return
        val result = pendingPickResult ?: return
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // User cancelled.
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            result.error("permission_failed", e.message, null)
            return
        }
        val label = DocumentFile.fromTreeUri(this, uri)?.name
        result.success(mapOf("uri" to uri.toString(), "label" to label))
    }
}
