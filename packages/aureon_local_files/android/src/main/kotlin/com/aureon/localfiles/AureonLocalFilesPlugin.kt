package com.aureon.localfiles

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/**
 * Android shared-storage file access.
 *
 * Android 11+ requires the user to explicitly grant MANAGE_EXTERNAL_STORAGE
 * in Special App Access. The app never attempts to bypass Android's sandbox.
 */
class AureonLocalFilesPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingAccessResult: MethodChannel.Result? = null
    private var pendingPicker: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "aureon/local_files")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingAccessResult?.error("detached", "AUREON closed while permission settings were open.", null)
        pendingPicker?.error("detached", "AUREON closed while folder selection was open.", null)
        pendingAccessResult = null
        pendingPicker = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
            "requestAllFilesAccess" -> requestAllFilesAccess(result)
            "defaultRoot" -> result.success(defaultRoot())
            "pickRoot" -> pickRoot(result)
            "listChildren" -> listChildren(call, result)
            "getThumbnail" -> getThumbnail(call, result)
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

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager()
        else true

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (hasAllFilesAccess()) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("no_activity", "AUREON needs an active screen to request storage access.", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(false)
            return
        }
        if (pendingAccessResult != null) {
            result.error("permission_request_busy", "A storage permission request is already active.", null)
            return
        }
        pendingAccessResult = result
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivityForResult(intent, REQUEST_ALL_FILES_ACCESS)
        } catch (_: Exception) {
            pendingAccessResult = null
            try {
                activity.startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    REQUEST_ALL_FILES_ACCESS
                )
                pendingAccessResult = result
            } catch (error: Exception) {
                pendingAccessResult = null
                result.error("settings_unavailable", error.message ?: "Android storage access settings could not be opened.", null)
            }
        }
    }

    private fun defaultRoot(): Map<String, String>? {
        if (!hasAllFilesAccess()) return null
        val root = Environment.getExternalStorageDirectory().canonicalFile
        return mapOf("rootId" to root.path, "displayName" to "Internal storage", "rootDocumentId" to root.path)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_ALL_FILES_ACCESS) {
            val pending = pendingAccessResult ?: return true
            pendingAccessResult = null
            pending.success(hasAllFilesAccess())
            return true
        }
        if (requestCode == PICK_ROOT_REQUEST) {
            val pending = pendingPicker ?: return true
            pendingPicker = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
            } else {
                // Retain a SAF grant for removable drives/providers. Main internal
                // storage browsing uses direct filesystem access after All files access.
                pending.error("secondary_root_unsupported", "Additional document-provider roots are not enabled in this build. Internal shared storage is available through All files access.", null)
            }
            return true
        }
        return false
    }

    private fun pickRoot(result: MethodChannel.Result) {
        // Kept as an explicit secondary-storage entry point. Internal storage no
        // longer requires this picker.
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("no_activity", "AUREON needs an active screen to open folder selection.", null)
            return
        }
        if (pendingPicker != null) {
            result.error("picker_busy", "A folder selection is already active.", null)
            return
        }
        pendingPicker = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            activity.startActivityForResult(intent, PICK_ROOT_REQUEST)
        } catch (error: Exception) {
            pendingPicker = null
            result.error("picker_failed", error.message ?: "Unable to open folder selection.", null)
        }
    }

    private fun requireAccess(result: MethodChannel.Result): Boolean {
        if (!hasAllFilesAccess()) {
            result.error("all_files_access_required", "Grant AUREON the All files access permission in Android Settings, then try again.", null)
            return false
        }
        return true
    }

    private fun rootFile(rootId: String): File {
        val root = File(rootId).canonicalFile
        val allowed = Environment.getExternalStorageDirectory().canonicalFile
        if (root != allowed) throw SecurityException("Only the authorized shared-storage root is supported.")
        return root
    }

    private fun resolve(rootId: String, entryId: String): File {
        val root = rootFile(rootId)
        val candidate = File(entryId).canonicalFile
        if (candidate.path != root.path && !candidate.path.startsWith(root.path + File.separator)) {
            throw SecurityException("The requested path is outside AUREON's shared-storage root.")
        }
        return candidate
    }

    private fun safeName(name: String?): String {
        val value = name?.trim().orEmpty()
        require(value.isNotEmpty() && value != "." && value != ".." &&
            !value.contains("/") && !value.contains("\\") && !value.contains('\u0000')) {
            "A valid file or folder name is required."
        }
        return value
    }

    private fun entry(file: File): Map<String, Any?> = mapOf(
        "id" to file.canonicalPath,
        "name" to file.name.ifEmpty { "Internal storage" },
        "isDirectory" to file.isDirectory,
        "isHidden" to file.name.startsWith("."),
        "sizeBytes" to if (file.isFile) file.length() else null,
        "modifiedEpochMs" to file.lastModified().takeIf { it > 0L },
        "isSystemTrash" to false
    )

    private fun listChildren(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = call.argument<String>("rootId") ?: error("rootId is required.")
            val parentId = call.argument<String>("parentId") ?: error("parentId is required.")
            val parent = resolve(root, parentId)
            if (!parent.exists() || !parent.isDirectory) {
                result.error("not_a_directory", "This folder no longer exists or is not accessible.", null)
                return
            }
            val children = parent.listFiles() ?: throw SecurityException("Android could not list this folder.")
            val visibleChildren = ArrayList<Map<String, Any?>>()
            val isStorageRoot = parent.canonicalFile == rootFile(root).canonicalFile
            for (child in children) {
                if (isStorageRoot && child.canonicalFile == trashDir(rootFile(root)).canonicalFile) continue
                visibleChildren.add(entry(child))
            }
            visibleChildren.sortWith(Comparator { left, right ->
                val leftDirectory = left["isDirectory"] == true
                val rightDirectory = right["isDirectory"] == true
                if (leftDirectory != rightDirectory) {
                    if (leftDirectory) -1 else 1
                } else {
                    (left["name"] as String).compareTo(right["name"] as String, ignoreCase = true)
                }
            })
            result.success(visibleChildren)
        } catch (error: Exception) {
            result.error(if (error is SecurityException) "permission_denied" else "listing_failed",
                error.message ?: "Unable to list this folder.", null)
        }
    }

    private fun createFolder(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = call.argument<String>("rootId") ?: error("rootId is required.")
            val parent = resolve(root, call.argument<String>("parentId") ?: error("parentId is required."))
            val name = safeName(call.argument<String>("name"))
            val target = File(parent, name)
            if (target.exists()) throw IllegalStateException("An item with that name already exists.")
            if (!target.mkdirs()) throw IllegalStateException("Could not create the folder.")
            result.success(target.canonicalPath)
        } catch (error: Exception) { result.error("create_folder_failed", error.message, null) }
    }

    private fun renameEntry(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = call.argument<String>("rootId") ?: error("rootId is required.")
            val source = resolve(root, call.argument<String>("entryId") ?: error("entryId is required."))
            val name = safeName(call.argument<String>("newName"))
            val target = File(source.parentFile, name)
            if (!source.exists() || source == rootFile(root)) throw IllegalStateException("The item no longer exists or cannot be renamed.")
            if (target.exists()) throw IllegalStateException("An item with that name already exists.")
            if (!source.renameTo(target)) throw IllegalStateException("Rename failed.")
            result.success(target.canonicalPath)
        } catch (error: Exception) { result.error("rename_failed", error.message, null) }
    }

    private fun copyFile(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = call.argument<String>("rootId") ?: error("rootId is required.")
            val source = resolve(root, call.argument<String>("sourceId") ?: error("sourceId is required."))
            val parent = resolve(root, call.argument<String>("parentId") ?: error("parentId is required."))
            val target = File(parent, safeName(call.argument<String>("targetName")))
            if (!source.isFile || !parent.isDirectory) throw IllegalArgumentException("A file and destination folder are required.")
            if (target.exists()) throw IllegalStateException("An item with that name already exists; nothing was overwritten.")
            val partial = File(parent, ".aureon-copy-${UUID.randomUUID()}.partial")
            try {
                Files.copy(source.toPath(), partial.toPath())
                if (source.length() != partial.length()) throw IllegalStateException("Copy verification failed; source preserved.")
                if (!partial.renameTo(target)) throw IllegalStateException("Could not finalize copied file.")
            } finally { if (partial.exists()) partial.delete() }
            result.success(target.canonicalPath)
        } catch (error: Exception) { result.error("copy_failed", error.message, null) }
    }

    private fun moveEntry(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = call.argument<String>("rootId") ?: error("rootId is required.")
            val source = resolve(root, call.argument<String>("entryId") ?: error("entryId is required."))
            val parent = resolve(root, call.argument<String>("targetParentId") ?: error("targetParentId is required."))
            if (!source.exists() || source == rootFile(root) || !parent.isDirectory) throw IllegalArgumentException("Source or destination is unavailable.")
            val target = File(parent, source.name)
            if (target.exists()) throw IllegalStateException("An item with that name already exists; nothing was overwritten.")
            if (!source.renameTo(target)) {
                // Cross-volume moves are copied and verified before source removal.
                if (source.isDirectory) throw IllegalStateException("Moving folders across storage volumes is not supported.")
                val partial = File(parent, ".aureon-move-${UUID.randomUUID()}.partial")
                try {
                    Files.copy(source.toPath(), partial.toPath())
                    if (source.length() != partial.length()) throw IllegalStateException("Move verification failed; source preserved.")
                    if (!partial.renameTo(target)) throw IllegalStateException("Could not finalize moved file.")
                    if (!source.delete()) { target.delete(); throw IllegalStateException("Could not remove source after verified copy.") }
                } finally { if (partial.exists()) partial.delete() }
            }
            result.success(target.canonicalPath)
        } catch (error: Exception) { result.error("move_failed", error.message, null) }
    }

    private fun trashDir(root: File) = File(root, ".AUREON Trash (AUREON)")
    private fun trashIndex(root: File) = File(trashDir(root), ".aureon-trash-index.json")

    private fun readTrashIndex(root: File): JSONObject {
        val file = trashIndex(root)
        return if (file.exists()) JSONObject(file.readText()) else JSONObject()
    }

    private fun moveToTrash(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val rootId = call.argument<String>("rootId") ?: error("rootId is required.")
            val root = rootFile(rootId)
            val source = resolve(rootId, call.argument<String>("entryId") ?: error("entryId is required."))
            if (!source.exists() || source == root || source.parentFile == trashDir(root)) throw IllegalArgumentException("This item cannot be moved to Trash.")
            val trash = trashDir(root)
            if (!trash.exists() && !trash.mkdirs()) throw IllegalStateException("Could not create AUREON Trash.")
            val id = UUID.randomUUID().toString()
            val target = File(trash, id + "_" + source.name)
            val index = readTrashIndex(root)
            val parent = source.parentFile?.canonicalPath ?: root.path
            val name = source.name
            if (!source.renameTo(target)) {
                if (!source.isFile) throw IllegalStateException("Could not move this folder to Trash.")
                Files.copy(source.toPath(), target.toPath())
                if (source.length() != target.length()) { target.delete(); throw IllegalStateException("Trash verification failed; original preserved.") }
                if (!source.delete()) { target.delete(); throw IllegalStateException("Could not remove original after verified Trash copy.") }
            }
            index.put(target.name, JSONObject().put("originalParent", parent).put("originalName", name).put("trashedAt", System.currentTimeMillis()))
            trashIndex(root).writeText(index.toString())
            result.success(mapOf("id" to target.canonicalPath, "name" to name, "trashFolderId" to trash.canonicalPath,
                "originalParentId" to parent, "trashedAt" to System.currentTimeMillis(), "mode" to "managed"))
        } catch (error: Exception) { result.error("trash_failed", error.message, null) }
    }

    private fun listSystemTrash(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val root = rootFile(call.argument<String>("rootId") ?: error("rootId is required."))
            val trash = trashDir(root)
            val files = trash.listFiles()?.filter { it.name != ".aureon-trash-index.json" }.orEmpty()
            result.success(files.map { file ->
                val meta = readTrashIndex(root).optJSONObject(file.name)
                mapOf("id" to file.canonicalPath, "name" to (meta?.optString("originalName")?.takeIf { it.isNotBlank() } ?: file.name),
                    "isDirectory" to file.isDirectory, "isHidden" to false, "sizeBytes" to if (file.isFile) file.length() else null,
                    "modifiedEpochMs" to file.lastModified(), "isSystemTrash" to true)
            })
        } catch (error: Exception) { result.error("trash_list_failed", error.message, null) }
    }

    private fun restoreSystemTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val rootId = call.argument<String>("rootId") ?: error("rootId is required.")
            val root = rootFile(rootId)
            val trashed = resolve(rootId, call.argument<String>("entryId") ?: error("entryId is required."))
            val index = readTrashIndex(root)
            val meta = index.optJSONObject(trashed.name) ?: throw IllegalStateException("Trash restore metadata is missing.")
            val parent = resolve(rootId, meta.getString("originalParent"))
            if (!parent.isDirectory) throw IllegalStateException("Original folder is unavailable.")
            val originalName = safeName(meta.getString("originalName"))
            var target = File(parent, originalName)
            if (target.exists()) target = File(parent, "${System.currentTimeMillis()}_$originalName")
            if (!trashed.renameTo(target)) throw IllegalStateException("Could not restore this item.")
            index.remove(trashed.name)
            trashIndex(root).writeText(index.toString())
            result.success(null)
        } catch (error: Exception) { result.error("trash_restore_failed", error.message, null) }
    }

    private fun deleteSystemTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        deleteTrashEntry(call, result)
    }

    private fun deleteTrashEntry(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val rootId = call.argument<String>("rootId") ?: error("rootId is required.")
            val root = rootFile(rootId)
            val file = resolve(rootId, call.argument<String>("entryId") ?: error("entryId is required."))
            if (file.parentFile != trashDir(root)) throw SecurityException("Only AUREON Trash items can be permanently deleted here.")
            if (!deleteRecursively(file)) throw IllegalStateException("Could not permanently delete the Trash item.")
            val index = readTrashIndex(root)
            index.remove(file.name)
            trashIndex(root).writeText(index.toString())
            result.success(null)
        } catch (error: Exception) { result.error("trash_delete_failed", error.message, null) }
    }

    private fun deleteRecursively(file: File): Boolean {
        if (file.isDirectory) file.listFiles()?.forEach { if (!deleteRecursively(it)) return false }
        return !file.exists() || file.delete()
    }

    private fun getThumbnail(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        val rootId = call.argument<String>("rootId")
        val fileId = call.argument<String>("fileId")
        if (rootId.isNullOrBlank() || fileId.isNullOrBlank()) {
            result.error("invalid_arguments", "rootId and fileId are required.", null)
            return
        }
        Thread {
            var bitmap: Bitmap? = null
            try {
                val file = resolve(rootId, fileId)
                if (!file.isFile || !file.exists()) {
                    result.success(null)
                    return@Thread
                }
                val extension = file.extension.lowercase()
                if (extension in IMAGE_EXTENSIONS) {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.absolutePath, bounds)
                    if (bounds.outWidth > 0 && bounds.outHeight > 0) {
                        var sample = 1
                        while (bounds.outWidth / sample > 512 || bounds.outHeight / sample > 512) sample *= 2
                        bitmap = BitmapFactory.decodeFile(file.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample })
                    }
                } else if (extension in VIDEO_EXTENSIONS) {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(file.absolutePath)
                        bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } finally {
                        retriever.release()
                    }
                }
                val output = ByteArrayOutputStream()
                val bytes = bitmap?.let {
                    val scaled = if (it.width > 384 || it.height > 384) {
                        val ratio = minOf(384.0 / it.width, 384.0 / it.height)
                        Bitmap.createScaledBitmap(it, (it.width * ratio).toInt().coerceAtLeast(1),
                            (it.height * ratio).toInt().coerceAtLeast(1), true)
                    } else it
                    scaled.compress(Bitmap.CompressFormat.JPEG, 78, output)
                    if (scaled !== it) scaled.recycle()
                    output.toByteArray().takeIf { data -> data.isNotEmpty() && data.size <= MAX_THUMBNAIL_BYTES }
                }
                Handler(Looper.getMainLooper()).post { result.success(bytes) }
            } catch (_: Exception) {
                Handler(Looper.getMainLooper()).post { result.success(null) }
            } finally {
                bitmap?.recycle()
            }
        }.start()
    }

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        if (!requireAccess(result)) return
        try {
            val rootId = call.argument<String>("rootId") ?: error("rootId is required.")
            val file = resolve(rootId, call.argument<String>("fileId") ?: error("fileId is required."))
            if (!file.isFile) throw IllegalArgumentException("The selected item is not a file.")
            val activity = activityBinding?.activity ?: throw IllegalStateException("AUREON has no active screen.")
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.aureon.fileprovider", file)
            val mime = activity.contentResolver.getType(uri) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val extension = file.extension.lowercase()
            val kind = when (extension) {
                in VIDEO_EXTENSIONS -> "video"
                in AUDIO_EXTENSIONS -> "audio"
                in IMAGE_EXTENSIONS -> "image"
                else -> null
            }
            val chooser = Intent.createChooser(intent, "Open with")
            if (kind != null) {
                val alias = when (kind) {
                    "video" -> "AureonVideoPlayer"
                    "audio" -> "AureonAudioPlayer"
                    else -> "AureonImageViewer"
                }
                val aureonChoice = Intent(intent).apply {
                    component = android.content.ComponentName(activity.packageName, activity.packageName + "." + alias)
                    putExtra("aureon_open_with", true)
                    putExtra("aureon_kind", kind)
                    putExtra("aureon_path", file.canonicalPath)
                    putExtra("aureon_name", file.name)
                }
                chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(aureonChoice))
            }
            activity.startActivity(chooser)
            result.success(null)
        } catch (error: Exception) { result.error("open_failed", error.message, null) }
    }

    companion object {
        private const val MAX_THUMBNAIL_BYTES = 512 * 1024
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "bmp", "gif", "heic", "heif")
        private val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "mov", "webm", "3gp", "avi", "m4v", "mpeg", "mpg", "ts", "m2ts", "flv")
        private val AUDIO_EXTENSIONS = setOf("mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "amr", "aiff", "alac")
        private const val REQUEST_ALL_FILES_ACCESS = 0xA0E1
        private const val PICK_ROOT_REQUEST = 0xA0E0
    }
}
