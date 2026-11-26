package app.nowpill

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

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

        // GitHub release updater: system DownloadManager + verified install.
        val updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.nowpill/update"
        )
        val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        updateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "download" -> {
                    val args = call.arguments as? Map<*, *>
                    val url = args?.get("url") as? String
                    val fileName = args?.get("fileName") as? String
                    if (url == null || fileName == null) {
                        result.error("invalid_args", "Expected url and fileName", null)
                        return@setMethodCallHandler
                    }
                    val uri = Uri.parse(url)
                    val host = uri.host.orEmpty()
                    if (host != "github.com" && !host.endsWith(".githubusercontent.com")) {
                        result.error("untrusted_host", "Only GitHub release assets are allowed", null)
                        return@setMethodCallHandler
                    }
                    val request = DownloadManager.Request(uri).apply {
                        setTitle("NowPill update")
                        setDescription(fileName)
                        setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
                        setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        setAllowedOverMetered(true)
                        setAllowedOverRoaming(true)
                    }
                    try {
                        result.success(downloadManager.enqueue(request).toInt())
                    } catch (e: Exception) {
                        result.error("download_failed", e.message, null)
                    }
                }
                "status" -> {
                    val id = (call.arguments as? Number)?.toLong()
                    if (id == null) {
                        result.error("invalid_args", "Expected a download id", null)
                        return@setMethodCallHandler
                    }
                    val cursor = downloadManager.query(DownloadManager.Query().setFilterById(id))
                    cursor.use { c ->
                        if (!c.moveToFirst()) {
                            result.success(mapOf("status" to -1))
                            return@setMethodCallHandler
                        }
                        result.success(
                            mapOf(
                                "status" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                                "received" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                                "total" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                                "uri" to c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                            )
                        )
                    }
                }
                "verifyAndInstall" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = (args?.get("id") as? Number)?.toLong()
                    val expected = args?.get("sha256") as? String
                    val fileName = args?.get("fileName") as? String
                    if (id == null || fileName == null) {
                        result.error("invalid_args", "Expected id and fileName", null)
                        return@setMethodCallHandler
                    }
                    val cursor = downloadManager.query(DownloadManager.Query().setFilterById(id))
                    val sourceUri = cursor.use { c ->
                        if (c.moveToFirst()) {
                            Uri.parse(c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)))
                        } else null
                    }
                    if (sourceUri == null) {
                        result.error("not_found", "Download not found", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val updateDir = File(cacheDir, "updates").apply { mkdirs() }
                        val local = File(updateDir, fileName)
                        contentResolver.openInputStream(sourceUri)?.use { input ->
                            FileOutputStream(local).use { output -> input.copyTo(output) }
                        } ?: throw IllegalStateException("Could not read the downloaded file")
                        if (!expected.isNullOrEmpty()) {
                            val actual = MessageDigest.getInstance("SHA-256")
                                .digest(local.readBytes())
                                .joinToString("") { "%02x".format(it) }
                            if (!actual.equals(expected, ignoreCase = true)) {
                                local.delete()
                                result.error("checksum_mismatch", "Downloaded APK failed verification", null)
                                return@setMethodCallHandler
                            }
                        }
                        if (!packageManager.canRequestPackageInstalls()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            local
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("settings_failed", e.message, null)
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
