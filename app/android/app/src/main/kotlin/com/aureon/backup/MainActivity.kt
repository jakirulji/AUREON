package com.aureon.backup

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.aureon.storage.AureonStoragePlugin
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var openWithChannel: MethodChannel? = null
    private var driveChannel: MethodChannel? = null
    private var pendingOpen: Map<String, String>? = null

    // Access tokens exist only in this process. Google Identity Services owns
    // the on-device token cache and can issue a fresh short-lived token later.
    private val driveTokens = ConcurrentHashMap<String, String>()
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingDriveSlotId: String? = null
    private var pendingDriveResult: MethodChannel.Result? = null

    companion object {
        private const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"
        private const val GOOGLE_DRIVE_ABOUT =
            "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,displayName)"
        private const val DRIVE_AUTHORIZATION_REQUEST_CODE = 7401
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DRIVE_AUTHORIZATION_REQUEST_CODE) return

        val slotId = pendingDriveSlotId
        val result = pendingDriveResult
        pendingDriveSlotId = null
        pendingDriveResult = null
        if (slotId == null || result == null) return

        if (resultCode != Activity.RESULT_OK) {
            result.error("AUTHORIZATION_CANCELLED", "Google Drive authorization was cancelled.", null)
            return
        }
        try {
            val authorization = Identity.getAuthorizationClient(this)
                .getAuthorizationResultFromIntent(data)
            completeDriveAuthorization(slotId, authorization, result)
        } catch (error: Exception) {
            result.error("AUTHORIZATION_FAILED", safeMessage(error), null)
        }
    }

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

        driveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aureon/google_drive")
        driveChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "authorizeDrive" -> {
                    val slotId = call.argument<String>("slotId")?.trim()
                    if (slotId.isNullOrEmpty() || slotId.length > 64) {
                        result.error("INVALID_SLOT", "A valid AUREON connection slot is required.", null)
                    } else {
                        authorizeDrive(slotId, result)
                    }
                }
                "listDriveFiles" -> {
                    val slotId = call.argument<String>("slotId")?.trim()
                    val pageToken = call.argument<String>("pageToken")
                    if (slotId.isNullOrEmpty()) {
                        result.error("INVALID_SLOT", "A valid AUREON connection slot is required.", null)
                    } else {
                        listDriveFiles(slotId, pageToken, result)
                    }
                }
                "clearDriveSession" -> {
                    val slotId = call.argument<String>("slotId")?.trim()
                    if (slotId.isNullOrEmpty()) {
                        result.error("INVALID_SLOT", "A valid AUREON connection slot is required.", null)
                    } else {
                        driveTokens.remove(slotId)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
        pendingOpen = readOpenWithIntent(intent)
    }

    private fun authorizeDrive(slotId: String, result: MethodChannel.Result) {
        if (pendingDriveResult != null) {
            result.error("AUTHORIZATION_BUSY", "Another Google authorization is already in progress.", null)
            return
        }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(DRIVE_SCOPE)))
            .setPrompt(AuthorizationRequest.Prompt.SELECT_ACCOUNT)
            .build()
        Identity.getAuthorizationClient(this)
            .authorize(request)
            .addOnSuccessListener { authorization ->
                if (authorization.hasResolution()) {
                    val pendingIntent = authorization.pendingIntent
                    if (pendingIntent == null) {
                        result.error("AUTHORIZATION_FAILED", "Google did not provide an authorization prompt.", null)
                        return@addOnSuccessListener
                    }
                    pendingDriveSlotId = slotId
                    pendingDriveResult = result
                    try {
                        startIntentSenderForResult(
                            pendingIntent.intentSender,
                            DRIVE_AUTHORIZATION_REQUEST_CODE,
                            null,
                            0,
                            0,
                            0
                        )
                    } catch (error: Exception) {
                        pendingDriveSlotId = null
                        pendingDriveResult = null
                        result.error("AUTHORIZATION_FAILED", safeMessage(error), null)
                    }
                } else {
                    completeDriveAuthorization(slotId, authorization, result)
                }
            }
            .addOnFailureListener { error ->
                result.error("AUTHORIZATION_FAILED", safeMessage(error), null)
            }
    }

    private fun completeDriveAuthorization(
        slotId: String,
        authorization: AuthorizationResult,
        result: MethodChannel.Result
    ) {
        val accessToken = authorization.accessToken
        if (accessToken.isNullOrBlank()) {
            result.error("EMPTY_ACCESS_TOKEN", "Google did not return a Drive access token.", null)
            return
        }
        // Identify the selected Google account through Drive's own about
        // endpoint. This response is kept on-device and is never synced.
        ioExecutor.execute {
            try {
                val about = googleGet(accessToken, GOOGLE_DRIVE_ABOUT)
                val user = about.optJSONObject("user")
                    ?: throw IllegalStateException("Google Drive did not return account details.")
                val email = user.optString("emailAddress").trim()
                if (email.isEmpty()) throw IllegalStateException("Google Drive account email is unavailable.")
                driveTokens[slotId] = accessToken
                val payload = mapOf(
                    "email" to email,
                    "displayName" to user.optString("displayName", email),
                )
                runOnUiThread { result.success(payload) }
            } catch (error: Exception) {
                runOnUiThread { result.error("DRIVE_ACCOUNT_LOOKUP_FAILED", safeMessage(error), null) }
            }
        }
    }

    private fun listDriveFiles(slotId: String, pageToken: String?, result: MethodChannel.Result) {
        val accessToken = driveTokens[slotId]
        if (accessToken.isNullOrBlank()) {
            result.error("DRIVE_NOT_CONNECTED", "Reconnect this Google Drive account first.", null)
            return
        }
        ioExecutor.execute {
            try {
                val builder = Uri.parse("https://www.googleapis.com/drive/v3/files").buildUpon()
                    .appendQueryParameter("q", "trashed=false")
                    .appendQueryParameter("pageSize", "100")
                    .appendQueryParameter("orderBy", "name")
                    .appendQueryParameter("spaces", "drive")
                    .appendQueryParameter("corpora", "allDrives")
                    .appendQueryParameter("supportsAllDrives", "true")
                    .appendQueryParameter("includeItemsFromAllDrives", "true")
                    .appendQueryParameter(
                        "fields",
                        "nextPageToken,files(id,name,mimeType,size,modifiedTime,parents,webViewLink)"
                    )
                if (!pageToken.isNullOrBlank()) builder.appendQueryParameter("pageToken", pageToken)
                val response = googleGet(accessToken, builder.build().toString())
                val filesJson = response.optJSONArray("files")
                val files = ArrayList<Map<String, Any?>>()
                if (filesJson != null) {
                    for (index in 0 until filesJson.length()) {
                        val item = filesJson.optJSONObject(index) ?: continue
                        val parents = item.optJSONArray("parents")
                        val parentList = ArrayList<String>()
                        if (parents != null) {
                            for (parentIndex in 0 until parents.length()) {
                                val parent = parents.optString(parentIndex)
                                if (parent.isNotBlank()) parentList.add(parent)
                            }
                        }
                        files.add(mapOf(
                            "id" to item.optString("id"),
                            "name" to item.optString("name"),
                            "mimeType" to item.optString("mimeType"),
                            "size" to item.optString("size"),
                            "modifiedTime" to item.optString("modifiedTime"),
                            "parents" to parentList,
                            "webViewLink" to item.optString("webViewLink"),
                        ))
                    }
                }
                val payload = mapOf(
                    "files" to files,
                    "nextPageToken" to response.optString("nextPageToken").takeIf { it.isNotBlank() },
                )
                runOnUiThread { result.success(payload) }
            } catch (error: Exception) {
                runOnUiThread { result.error("DRIVE_LIST_FAILED", safeMessage(error), null) }
            }
        }
    }

    private fun googleGet(accessToken: String, url: String): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.setRequestProperty("Authorization", "Bearer $accessToken")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Cache-Control", "no-store")
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val message = try {
                    JSONObject(body).optJSONObject("error")?.optString("message")
                } catch (_: Exception) { null }
                throw IllegalStateException(message?.takeIf { it.isNotBlank() }
                    ?: "Google Drive API returned HTTP $status.")
            }
            return JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun safeMessage(error: Throwable): String =
        error.message?.take(240) ?: "The Google Drive request could not be completed."

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = readOpenWithIntent(intent) ?: return
        pendingOpen = payload
        openWithChannel?.invokeMethod("openWith", payload)
    }

    override fun onDestroy() {
        driveTokens.clear()
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun readOpenWithIntent(source: Intent?): Map<String, String>? {
        if (source?.getBooleanExtra("aureon_open_with", false) != true) return null
        val kind = source.getStringExtra("aureon_kind") ?: return null
        val path = source.getStringExtra("aureon_path") ?: return null
        val name = source.getStringExtra("aureon_name") ?: path.substringAfterLast('/')
        return mapOf("kind" to kind, "path" to path, "name" to name)
    }
}
