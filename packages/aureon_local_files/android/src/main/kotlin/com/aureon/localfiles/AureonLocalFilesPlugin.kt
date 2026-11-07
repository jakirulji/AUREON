package com.aureon.localfiles

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.os.Handler
import android.os.Looper
import java.security.MessageDigest
import java.util.UUID
import java.nio.file.FileAlreadyExistsException
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
            "copyFile" -> copyFile(call, result)
            "moveEntry" -> moveEntry(call, result)
            "moveToTrash" -> moveToTrash(call, result)
            "deleteTrashEntry" -> deleteTrashEntry(call, result)
            "listSystemTrash" -> listSystemTrash(call, result)
            "restoreSystemTrashEntry" -> restoreSystemTrashEntry(call, result)
            "deleteSystemTrashEntry" -> deleteSystemTrashEntry(call, result)
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

    private fun copyFile(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val sourceId = call.argument<String>("sourceId")
        val parentId = call.argument<String>("parentId")
        val targetName = call.argument<String>("targetName")?.trim()
        if (root.isNullOrBlank() || sourceId.isNullOrBlank() || parentId.isNullOrBlank() ||
            targetName.isNullOrBlank() || targetName == "." || targetName == ".." ||
            targetName.contains("/") || targetName.contains("\\")) {
            result.error("invalid_arguments", "A valid source, destination folder and file name are required.", null); return
        }
        val resolver = activityBinding?.activity?.contentResolver
        if (resolver == null) { result.error("no_activity", "The Android activity is unavailable.", null); return }
        Thread {
            var temporary: Uri? = null
            try {
                val treeUri = Uri.parse(root)
                val source = DocumentsContract.buildDocumentUriUsingTree(treeUri, sourceId)
                val parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
                val rootDocument = DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri))
                if (!DocumentsContract.isChildDocument(resolver, rootDocument, source) ||
                    (parentId != DocumentsContract.getTreeDocumentId(treeUri) &&
                     !DocumentsContract.isChildDocument(resolver, rootDocument, parent))) {
                    throw SecurityException("Source or destination is outside the selected folder.")
                }
                val sourceMime = resolver.getType(source)
                if (sourceMime == null || sourceMime == Document.MIME_TYPE_DIR) {
                    throw IllegalArgumentException("Only regular files can be copied in this operation.")
                }
                resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId),
                    arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                    val col = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                    while (cursor.moveToNext()) if (cursor.getString(col).equals(targetName, ignoreCase = true))
                        throw FileAlreadyExistsException("An item with that name already exists. Nothing was overwritten.")
                } ?: throw IllegalStateException("Destination folder cannot be listed.")
                temporary = DocumentsContract.createDocument(resolver, parent, sourceMime,
                    ".aureon-copy-" + UUID.randomUUID().toString() + ".partial")
                    ?: throw IllegalStateException("Provider cannot create a temporary copy.")
                val sourceHash = MessageDigest.getInstance("SHA-256")
                resolver.openInputStream(source)?.use { input ->
                    resolver.openOutputStream(temporary, "w")?.use { output ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            sourceHash.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                        output.flush()
                    } ?: throw IllegalStateException("Cannot write the temporary copy.")
                } ?: throw IllegalStateException("Cannot read the source file.")
                val copiedHash = MessageDigest.getInstance("SHA-256")
                resolver.openInputStream(temporary)?.use { input ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copiedHash.update(buffer, 0, count)
                    }
                } ?: throw IllegalStateException("Cannot read back the temporary copy.")
                if (!MessageDigest.isEqual(sourceHash.digest(), copiedHash.digest()))
                    throw IllegalStateException("SHA-256 verification failed. The source was preserved.")
                val finalized = DocumentsContract.renameDocument(resolver, temporary, targetName)
                    ?: throw UnsupportedOperationException("Provider cannot finalize the verified copy.")
                temporary = null
                Handler(Looper.getMainLooper()).post { result.success(DocumentsContract.getDocumentId(finalized)) }
            } catch (error: Exception) {
                temporary?.let { try { DocumentsContract.deleteDocument(resolver, it) } catch (_: Exception) { } }
                val code = when (error) {
                    is SecurityException -> "permission_denied"
                    is FileAlreadyExistsException -> "conflict"
                    is UnsupportedOperationException -> "unsupported"
                    is IllegalArgumentException -> "unsupported_item"
                    else -> "copy_failed"
                }
                Handler(Looper.getMainLooper()).post { result.error(code, error.message ?: "Copy failed; source preserved.", null) }
            }
        }.start()
    }


    private fun moveEntry(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        val sourceParentId = call.argument<String>("sourceParentId")
        val targetParentId = call.argument<String>("targetParentId")
        if (root.isNullOrBlank() || entryId.isNullOrBlank() ||
            sourceParentId.isNullOrBlank() || targetParentId.isNullOrBlank() ||
            sourceParentId == targetParentId) {
            result.error("invalid_arguments", "A source item and two different parent folders are required.", null)
            return
        }
        val resolver = activityBinding?.activity?.contentResolver
        if (resolver == null) {
            result.error("no_activity", "The Android activity is unavailable.", null)
            return
        }
        Thread {
            try {
                val treeUri = Uri.parse(root)
                val rootId = DocumentsContract.getTreeDocumentId(treeUri)
                val rootDocument = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
                val source = DocumentsContract.buildDocumentUriUsingTree(treeUri, entryId)
                val sourceParent = DocumentsContract.buildDocumentUriUsingTree(treeUri, sourceParentId)
                val targetParent = DocumentsContract.buildDocumentUriUsingTree(treeUri, targetParentId)
                fun insideRoot(document: Uri, id: String): Boolean =
                    id == rootId || DocumentsContract.isChildDocument(resolver, rootDocument, document)
                if (!insideRoot(source, entryId) || !insideRoot(sourceParent, sourceParentId) ||
                    !insideRoot(targetParent, targetParentId)) {
                    throw SecurityException("Source or destination is outside the selected folder.")
                }
                var displayName: String? = null
                resolver.query(source, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) displayName = cursor.getString(0)
                } ?: throw IllegalStateException("The source item cannot be inspected.")
                val name = displayName ?: throw IllegalStateException("The source item has no name.")
                var foundSource = false
                resolver.query(
                    DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, sourceParentId),
                    arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null
                )?.use { cursor ->
                    val idColumn = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                    while (cursor.moveToNext()) if (cursor.getString(idColumn) == entryId) foundSource = true
                } ?: throw IllegalStateException("The source parent cannot be listed.")
                if (!foundSource) throw SecurityException("The source item is not inside the supplied source folder.")
                resolver.query(
                    DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, targetParentId),
                    arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null
                )?.use { cursor ->
                    val nameColumn = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                    while (cursor.moveToNext()) {
                        if (cursor.getString(nameColumn).equals(name, ignoreCase = true)) {
                            throw FileAlreadyExistsException("An item with that name already exists. Nothing was overwritten.")
                        }
                    }
                } ?: throw IllegalStateException("The destination folder cannot be listed.")
                val moved = DocumentsContract.moveDocument(resolver, source, sourceParent, targetParent)
                    ?: throw UnsupportedOperationException("This document provider does not support native move. The source was not deleted.")
                Handler(Looper.getMainLooper()).post {
                    result.success(DocumentsContract.getDocumentId(moved))
                }
            } catch (error: Exception) {
                val code = when (error) {
                    is SecurityException -> "permission_denied"
                    is FileAlreadyExistsException -> "conflict"
                    is UnsupportedOperationException -> "unsupported"
                    else -> "move_failed"
                }
                Handler(Looper.getMainLooper()).post {
                    result.error(code, error.message ?: "Move failed; source preserved.", null)
                }
            }
        }.start()
    }


    private fun moveToTrash(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        val parentId = call.argument<String>("parentId")
        if (root.isNullOrBlank() || entryId.isNullOrBlank() || parentId.isNullOrBlank()) {
            result.error("invalid_arguments", "The selected item and parent folder are required.", null)
            return
        }
        val resolver = activityBinding?.activity?.contentResolver
        if (resolver == null) { result.error("no_activity", "The Android activity is unavailable.", null); return }
        Thread {
            try {
                val tree = Uri.parse(root)
                val rootId = DocumentsContract.getTreeDocumentId(tree)
                val rootDoc = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
                val source = DocumentsContract.buildDocumentUriUsingTree(tree, entryId)
                val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
                if (!DocumentsContract.isChildDocument(resolver, rootDoc, source) ||
                    (parentId != rootId && !DocumentsContract.isChildDocument(resolver, rootDoc, parent))) {
                    throw SecurityException("The selected item or parent is outside the selected folder.")
                }
                var name: String? = null
                var mime: String? = null
                var flags = 0
                resolver.query(source, arrayOf(Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS),
                    null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        name = cursor.getString(0)
                        mime = cursor.getString(1)
                        flags = if (cursor.isNull(2)) 0 else cursor.getInt(2)
                    }
                } ?: throw IllegalStateException("The selected item cannot be inspected.")
                val displayName = name ?: throw IllegalStateException("The selected item has no name.")
                if (displayName == ".AUREON Trash (AUREON)") throw IllegalArgumentException("The Trash folder itself cannot be moved to Trash.")
                var sourceIsInParent = false
                resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId),
                    arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                    while (cursor.moveToNext()) if (cursor.getString(idCol) == entryId) sourceIsInParent = true
                } ?: throw IllegalStateException("The source parent cannot be listed.")
                if (!sourceIsInParent) throw SecurityException("The selected item is not inside the supplied parent folder.")
                // Prefer provider-native Android 17 Trash when the document explicitly advertises support.
                if (android.os.Build.VERSION.SDK_INT >= 37 && (flags and 0x00010000) != 0) {
                    try {
                        val method = DocumentsContract::class.java.getMethod(
                            "trashDocument", ContentResolver::class.java, Uri::class.java)
                        val trashed = method.invoke(null, resolver, source) as? Uri
                        if (trashed != null) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf("id" to DocumentsContract.getDocumentId(trashed),
                                    "name" to displayName, "trashFolderId" to "__system__",
                                    "originalParentId" to parentId, "isDirectory" to (mime == Document.MIME_TYPE_DIR),
                                    "trashedAt" to System.currentTimeMillis(), "mode" to "system"))
                            }
                            return@Thread
                        }
                    } catch (_: Exception) { }
                }
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId)
                var trashId: String? = null
                resolver.query(children, arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE),
                    null, null, null)?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                    val nameCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                    val mimeCol = cursor.getColumnIndexOrThrow(Document.COLUMN_MIME_TYPE)
                    while (cursor.moveToNext()) {
                        if (cursor.getString(nameCol) == ".AUREON Trash (AUREON)" &&
                            cursor.getString(mimeCol) == Document.MIME_TYPE_DIR) trashId = cursor.getString(idCol)
                    }
                } ?: throw IllegalStateException("The selected folder cannot be listed.")
                if (trashId == null) {
                    val created = DocumentsContract.createDocument(resolver, rootDoc, Document.MIME_TYPE_DIR, ".AUREON Trash (AUREON)")
                        ?: throw UnsupportedOperationException("This provider cannot create AUREON's Trash folder.")
                    trashId = DocumentsContract.getDocumentId(created)
                }
                if (entryId == trashId) throw IllegalArgumentException("The Trash folder itself cannot be moved.")
                val trashFolder = DocumentsContract.buildDocumentUriUsingTree(tree, trashId!!)
                resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, trashId!!),
                    arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                    val col = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                    while (cursor.moveToNext()) if (cursor.getString(col).equals(displayName, ignoreCase = true))
                        throw FileAlreadyExistsException("An item with that name is already in Trash.")
                } ?: throw IllegalStateException("AUREON Trash cannot be listed.")
                val moved = DocumentsContract.moveDocument(resolver, source, parent, trashFolder)
                    ?: throw UnsupportedOperationException("This provider cannot move items into AUREON Trash. Nothing was deleted.")
                val movedId = DocumentsContract.getDocumentId(moved)
                Handler(Looper.getMainLooper()).post {
                    result.success(mapOf("id" to movedId, "name" to displayName, "trashFolderId" to trashId,
                        "originalParentId" to parentId, "isDirectory" to (mime == Document.MIME_TYPE_DIR),
                        "trashedAt" to System.currentTimeMillis()))
                }
            } catch (error: Exception) {
                val code = when (error) {
                    is SecurityException -> "permission_denied"
                    is FileAlreadyExistsException -> "conflict"
                    is UnsupportedOperationException -> "unsupported"
                    is IllegalArgumentException -> "invalid_item"
                    else -> "trash_failed"
                }
                Handler(Looper.getMainLooper()).post {
                    result.error(code, error.message ?: "Could not move this item to Trash. The original was not intentionally deleted.", null)
                }
            }
        }.start()
    }

    private fun deleteTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        val trashFolderId = call.argument<String>("trashFolderId")
        if (root.isNullOrBlank() || entryId.isNullOrBlank() || trashFolderId.isNullOrBlank()) {
            result.error("invalid_arguments", "Trash item identity is incomplete.", null)
            return
        }
        try {
            val resolver = activityBinding?.activity?.contentResolver
                ?: throw IllegalStateException("The Android activity is unavailable.")
            val tree = Uri.parse(root)
            val rootId = DocumentsContract.getTreeDocumentId(tree)
            val rootDoc = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
            val item = DocumentsContract.buildDocumentUriUsingTree(tree, entryId)
            val trash = DocumentsContract.buildDocumentUriUsingTree(tree, trashFolderId)
            if (!DocumentsContract.isChildDocument(resolver, rootDoc, trash) ||
                !DocumentsContract.isChildDocument(resolver, trash, item)) {
                throw SecurityException("The item is not inside AUREON Trash.")
            }
            if (!DocumentsContract.deleteDocument(resolver, item)) {
                throw IllegalStateException("The provider did not confirm permanent deletion.")
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("permanent_delete_failed", error.message ?: "Permanent deletion failed.", null)
        }
    }

 
    private fun resolveProviderRootId(resolver: ContentResolver, tree: Uri): String? {
        val authority = tree.authority ?: return null
        val selectedId = DocumentsContract.getTreeDocumentId(tree)
        val selected = DocumentsContract.buildDocumentUriUsingTree(tree, selectedId)
        val roots = DocumentsContract.buildRootsUri(authority)
        resolver.query(roots, arrayOf(DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
            val rootIdCol = cursor.getColumnIndexOrThrow(DocumentsContract.Root.COLUMN_ROOT_ID)
            val documentIdCol = cursor.getColumnIndexOrThrow(DocumentsContract.Root.COLUMN_DOCUMENT_ID)
            while (cursor.moveToNext()) {
                val rootId = cursor.getString(rootIdCol)
                val documentId = cursor.getString(documentIdCol)
                if (rootId.isNullOrBlank() || documentId.isNullOrBlank()) continue
                val rootDocument = DocumentsContract.buildDocumentUri(authority, documentId)
                if (documentId == selectedId || DocumentsContract.isChildDocument(resolver, rootDocument, selected)) {
                    return rootId
                }
            }
        }
        return null
    }

    private fun listSystemTrash(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        if (root.isNullOrBlank()) { result.error("invalid_arguments", "rootId is required.", null); return }
        if (android.os.Build.VERSION.SDK_INT < 37) { result.success(emptyList<Map<String, Any?>>()); return }
        val resolver = activityBinding?.activity?.contentResolver
        if (resolver == null) { result.error("no_activity", "The Android activity is unavailable.", null); return }
        try {
            val tree = Uri.parse(root)
            val providerRootId = resolveProviderRootId(resolver, tree)
                ?: throw UnsupportedOperationException("The provider root for this selected folder could not be resolved.")
            val method = DocumentsContract::class.java.getMethod("buildTrashDocumentsUri", String::class.java, String::class.java)
            val trashUri = method.invoke(null, tree.authority ?: "", providerRootId) as Uri
            val rows = mutableListOf<Map<String, Any?>>()
            resolver.query(trashUri, arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE), null, null, null)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                val nameCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(Document.COLUMN_MIME_TYPE)
                val sizeCol = cursor.getColumnIndexOrThrow(Document.COLUMN_SIZE)
                while (cursor.moveToNext()) rows.add(mapOf(
                    "id" to cursor.getString(idCol),
                    "name" to (cursor.getString(nameCol) ?: "Unnamed"),
                    "isDirectory" to (cursor.getString(mimeCol) == Document.MIME_TYPE_DIR),
                    "sizeBytes" to if (cursor.isNull(sizeCol)) null else cursor.getLong(sizeCol),
                    "isSystemTrash" to true))
            }
            result.success(rows)
        } catch (_: Exception) {
            // A provider without Android 17 Trash support returns an empty native Trash view.
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    private fun restoreSystemTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        if (root.isNullOrBlank() || entryId.isNullOrBlank()) {
            result.error("invalid_arguments", "rootId and entryId are required.", null); return
        }
        if (android.os.Build.VERSION.SDK_INT < 37) {
            result.error("unsupported", "Provider-native Trash restore requires Android 17 or later.", null); return
        }
        try {
            val resolver = activityBinding?.activity?.contentResolver
                ?: throw IllegalStateException("The Android activity is unavailable.")
            val tree = Uri.parse(root)
            val source = DocumentsContract.buildDocumentUri(tree.authority!!, entryId)
            val method = DocumentsContract::class.java.getMethod("restoreDocumentFromTrash",
                ContentResolver::class.java, Uri::class.java, Uri::class.java)
            val restored = method.invoke(null, resolver, source, null) as? Uri
                ?: throw UnsupportedOperationException("The provider could not restore this item.")
            result.success(DocumentsContract.getDocumentId(restored))
        } catch (error: Exception) {
            result.error("restore_failed", error.message ?: "Provider-native restore failed.", null)
        }
    }

    private fun deleteSystemTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        val root = call.argument<String>("rootId")
        val entryId = call.argument<String>("entryId")
        if (root.isNullOrBlank() || entryId.isNullOrBlank()) {
            result.error("invalid_arguments", "rootId and entryId are required.", null); return
        }
        if (android.os.Build.VERSION.SDK_INT < 37) {
            result.error("unsupported", "Provider-native Trash deletion requires Android 17 or later.", null); return
        }
        try {
            val resolver = activityBinding?.activity?.contentResolver
                ?: throw IllegalStateException("The Android activity is unavailable.")
            val tree = Uri.parse(root)
            val providerRootId = resolveProviderRootId(resolver, tree)
                ?: throw UnsupportedOperationException("The provider root for this selected folder could not be resolved.")
            val method = DocumentsContract::class.java.getMethod("buildTrashDocumentsUri", String::class.java, String::class.java)
            val trashUri = method.invoke(null, tree.authority ?: "", providerRootId) as Uri
            var found = false
            resolver.query(trashUri, arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
                while (cursor.moveToNext()) if (cursor.getString(idCol) == entryId) found = true
            } ?: throw IllegalStateException("Provider Trash cannot be listed.")
            if (!found) throw SecurityException("The selected item is not in provider Trash.")
            val item = DocumentsContract.buildDocumentUri(tree.authority!!, entryId)
            if (!DocumentsContract.deleteDocument(resolver, item))
                throw IllegalStateException("The provider did not confirm permanent deletion.")
            result.success(true)
        } catch (error: Exception) {
            result.error("permanent_delete_failed", error.message ?: "Provider Trash deletion failed.", null)
        }
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
