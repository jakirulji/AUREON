package com.aureon.backup

import android.content.Intent
import com.aureon.storage.AureonStoragePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var openWithChannel: MethodChannel? = null
    private var pendingOpen: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AureonStoragePlugin())
        openWithChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aureon/open_with")
        openWithChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingOpenWith") {
                result.success(pendingOpen)
                pendingOpen = null
            } else {
                result.notImplemented()
            }
        }
        pendingOpen = readOpenWithIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = readOpenWithIntent(intent) ?: return
        pendingOpen = payload
        openWithChannel?.invokeMethod("openWith", payload)
    }

    private fun readOpenWithIntent(source: Intent?): Map<String, String>? {
        if (source?.getBooleanExtra("aureon_open_with", false) != true) return null
        val kind = source.getStringExtra("aureon_kind") ?: return null
        val path = source.getStringExtra("aureon_path") ?: return null
        val name = source.getStringExtra("aureon_name") ?: path.substringAfterLast('/')
        return mapOf("kind" to kind, "path" to path, "name" to name)
    }
}
