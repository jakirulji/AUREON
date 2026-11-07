package com.aureon.localfiles

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** User-authorized SAF folder access. No broad storage permission is requested. */
class AureonLocalFilesPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPicker: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "aureon/local_files")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingPicker?.error("detached", "Plugin detached while folder picker was open.", null)
        pendingPicker = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickRoot" -> pickRoot(result)
            "listChildren" -> listChildren(call, result)
            "openFile" -> openFile(call, result)
            "renameEntry" -> renameEntry(call, result)
            "createFolder" -> createFolder(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickRoot(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("no_activity", "AUREON needs an active screen to open the folder picker.", null)
            return
        }
        if (pendingPicker != null) {
            result.error("picker_busy", "A folder picker request is already active.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        pendingPicker = result
        try {
            activity.startActivityForResult(intent, PICK_ROOT_REQUEST)
        } catch (error: Exception) {
            pendingPicker = null
            result.error("picker_failed", error.message ?: "Unable to open the system folder picker.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_ROOT_REQUEST) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            result.error("invalid_selection", "The system picker returned no folder.", null)
            return true
        }
        try {
            val granted = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            activityBinding?.activity?.contentResolver?.takePersistableUriPermission(uri, granted)
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            val name = queryDisplayName(uri) ?: "Selected folder"
            result.success(mapOf("rootId" to uri.toString(), "displayName" to name, "rootDocumentId" to documentId))
        } catch (error: Exception) {
            result.error("permission_failed", error.message ?: "Could not retain folder access.", null)
        }
        return true
    }

    private fun queryDisplayName(uri: Uri): String? {
        val resolver = activityBinding?.activity?.contentResolver ?: return null
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            uri, DocumentsContract.getTreeDocumentId(uri)
        )
        return resolver.query(documentUri, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    }

    private fun renameEntry(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        val newName = call.argument<String>("newName")?.trim()
        if (root.isNullOrBlank() || entryId.isNullOrBlank() || newName.isNullOrBlank() ||
            newName == "." || newName == ".." || newName.contains("/") || newName.contains("\\")) {
            result.error("invalid_arguments", "A valid new name and entry identity are required.", null); return
        }
        try {
            val resolver = activityBinding?.activity?.contentResolver
            if (resolver == null) { result.error("no_activity", "The Android activity is unavailable.", null); return }
            val uri = DocumentsContract.buildDocumentUriUsingTree(Uri.parse(root), entryId)
            val renamed = DocumentsContract.renameDocument(resolver, uri, newName)
            if (renamed == null) { result.error("unsupported", "This document provider does not support renaming.", null); return }
            result.success(DocumentsContract.getDocumentId(renamed))
        } catch (error: SecurityException) {
            result.error("permission_denied", "Write access was revoked. Re-select the folder.", null)
        } catch (error: Exception) {
            result.error("rename_failed", error.message ?: "Unable to rename this item.", null)
        }
    }

    private fun createFolder(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val parentId = call.argument<String>("parentId")
        val name = call.argument<String>("name")?.trim()
        if (root.isNullOrBlank() || parentId.isNullOrBlank() || name.isNullOrBlank() ||
            name == "." || name == ".." || name.contains("/") || name.contains("\\")) {
            result.error("invalid_arguments", "A valid folder name and parent identity are required.", null); return
        }
        try {
            val resolver = activityBinding?.activity?.contentResolver
            if (resolver == null) { result.error("no_activity", "The Android activity is unavailable.", null); return }
            val parent = DocumentsContract.buildDocumentUriUsingTree(Uri.parse(root), parentId)
            val created = DocumentsContract.createDocument(resolver, parent, Document.MIME_TYPE_DIR, name)
            if (created == null) { result.error("unsupported", "This document provider does not support creating folders.", null); return }
            result.success(DocumentsContract.getDocumentId(created))
        } catch (error: SecurityException) {
            result.error("permission_denied", "Write access was revoked. Re-select the folder.", null)
        } catch (error: Exception) {
            result.error("create_failed", error.message ?: "Unable to create this folder.", null)
        }
    }

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val fileId = call.argument<String>("fileId")
        if (root.isNullOrBlank() || fileId.isNullOrBlank()) {
            result.error("invalid_arguments", "rootId and fileId are required.", null); return
        }
        val activity = activityBinding?.activity
        if (activity == null) { result.error("no_activity", "An active screen is required.", null); return }
        try {
            val uri = DocumentsContract.buildDocumentUriUsingTree(Uri.parse(root), fileId)
            val mime = activity.contentResolver.getType(uri) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (error: android.content.ActivityNotFoundException) {
            result.error("no_viewer", "No installed app can open this file type.", null)
        } catch (error: SecurityException) {
            result.error("permission_denied", "File access was revoked. Re-select its folder.", null)
        } catch (error: Exception) {
            result.error("open_failed", error.message ?: "Unable to open this file.", null)
        }
    }

    private fun listChildren(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val parentId = call.argument<String>("parentId")
        if (root.isNullOrBlank() || parentId.isNullOrBlank()) {
            result.error("invalid_arguments", "rootId and parentId are required.", null)
            return
        }
        try {
            val treeUri = Uri.parse(root)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            val resolver = activityBinding?.activity?.contentResolver
            if (resolver == null) {
                result.error("no_activity", "The Android activity is unavailable.", null)
                return
            }
            val projection = arrayOf(
                Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE,
                Document.COLUMN_SIZE,
                Document.COLUMN_LAST_MODIFIED
            )
            val entries = mutableListOf<Map<String, Any?>>()
            resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                val nameCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(Document.COLUMN_MIME_TYPE)
                val sizeCol = cursor.getColumnIndexOrThrow(Document.COLUMN_SIZE)
                val modifiedCol = cursor.getColumnIndexOrThrow(Document.COLUMN_LAST_MODIFIED)
                while (cursor.moveToNext()) {
                    val mime = cursor.getString(mimeCol)
                    val isDirectory = mime == Document.MIME_TYPE_DIR
                    val id = cursor.getString(idCol)
                    entries.add(
                        mapOf(
                            "id" to id,
                            "name" to (cursor.getString(nameCol) ?: "Unnamed"),
                            "isDirectory" to isDirectory,
                            "isHidden" to (cursor.getString(nameCol)?.startsWith(".") == true),
                            "sizeBytes" to if (isDirectory || cursor.isNull(sizeCol)) null else cursor.getLong(sizeCol),
                            "modifiedEpochMs" to if (cursor.isNull(modifiedCol)) null else cursor.getLong(modifiedCol),
                        )
                    )
                }
            } ?: run {
                result.error("listing_unavailable", "The selected folder could not be listed by its document provider.", null)
                return
            }
            entries.sortWith(compareByDescending<Map<String, Any?>> { it["isDirectory"] == true }
                .thenBy { (it["name"] as String).lowercase() })
            result.success(entries)
        } catch (error: SecurityException) {
            result.error("permission_denied", "Folder access was revoked. Select the folder again.", null)
        } catch (error: Exception) {
            result.error("listing_failed", error.message ?: "Unable to list this folder.", null)
        }
    }

    companion object {
        private const val PICK_ROOT_REQUEST = 0xA0E0
    }
}
