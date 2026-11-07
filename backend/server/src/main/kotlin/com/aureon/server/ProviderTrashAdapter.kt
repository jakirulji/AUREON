package com.aureon.server

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

data class ProviderTrashReceipt(
    val providerItemId: String,
    val originalParentProviderItemId: String?,
    val trashMode: String,
    val trashContainerProviderItemId: String?,
    val outcomeReference: String
)

interface ProviderTrashAdapter {
    fun moveToTrash(accessToken: String, providerItemId: String): ProviderTrashReceipt
    fun restore(accessToken: String, providerItemId: String): ProviderTrashReceipt
    fun permanentlyDelete(accessToken: String, providerItemId: String): ProviderTrashReceipt
}

/** Google Drive v3 native Trash adapter. Tokens are short-lived and never persisted or logged. */
class GoogleDriveTrashAdapter(
    private val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build(),
    private val apiBase: String = "https://www.googleapis.com/drive/v3"
) : ProviderTrashAdapter {
    private val json = Json { ignoreUnknownKeys = true }

    override fun moveToTrash(accessToken: String, providerItemId: String): ProviderTrashReceipt {
        val before = getMetadata(accessToken, providerItemId)
        require(!before.trashed) { "Provider item is already trashed" }
        val response = request(accessToken, "PATCH", "/files/\${encode(providerItemId)}?supportsAllDrives=true", """{"trashed":true}""")
        return ProviderTrashReceipt(providerItemId, before.parents.firstOrNull(), "provider_native", null, response.reference)
    }

    override fun restore(accessToken: String, providerItemId: String): ProviderTrashReceipt {
        val response = request(accessToken, "PATCH", "/files/\${encode(providerItemId)}?supportsAllDrives=true", """{"trashed":false}""")
        val after = getMetadata(accessToken, providerItemId)
        require(!after.trashed) { "Provider did not confirm restore" }
        return ProviderTrashReceipt(providerItemId, after.parents.firstOrNull(), "provider_native", null, response.reference)
    }

    override fun permanentlyDelete(accessToken: String, providerItemId: String): ProviderTrashReceipt {
        val before = getMetadata(accessToken, providerItemId)
        require(before.trashed) { "Refusing permanent deletion of an item not in Trash" }
        val response = request(accessToken, "DELETE", "/files/\${encode(providerItemId)}?supportsAllDrives=true", null)
        return ProviderTrashReceipt(providerItemId, before.parents.firstOrNull(), "provider_native", null, response.reference)
    }

    private data class Metadata(val trashed: Boolean, val parents: List<String>)
    private data class Outcome(val body: String, val reference: String)

    private fun getMetadata(token: String, itemId: String): Metadata {
        val response = request(token, "GET", "/files/\${encode(itemId)}?fields=id,parents,trashed&supportsAllDrives=true", null)
        val root = json.parseToJsonElement(response.body).jsonObject
        val parents = root["parents"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
        val trashed = root["trashed"]?.jsonPrimitive?.content?.toBooleanStrictOrNull() ?: false
        return Metadata(trashed, parents)
    }

    private fun request(token: String, method: String, path: String, body: String?): Outcome {
        require(token.isNotBlank() && token.length <= 8192) { "Short-lived provider access token required" }
        val builder = HttpRequest.newBuilder(URI.create(apiBase + path))
            .timeout(Duration.ofSeconds(20))
            .header("Authorization", "Bearer " + token)
            .header("Accept", "application/json")
        if (body != null) builder.header("Content-Type", "application/json")
        val request = when (method) {
            "GET" -> builder.GET().build()
            "PATCH" -> builder.method("PATCH", HttpRequest.BodyPublishers.ofString(body!!)).build()
            "DELETE" -> builder.DELETE().build()
            else -> error("Unsupported provider HTTP method")
        }
        val response = http.send(request, HttpResponse.BodyHandlers.ofString())
        if (response.statusCode() !in 200..299) throw ProviderOperationException("GOOGLE_DRIVE_HTTP_" + response.statusCode())
        val requestId = response.headers().firstValue("x-guploader-uploadid").orElse(null)
            ?: response.headers().firstValue("etag").orElse(null)
            ?: "http-" + response.statusCode()
        return Outcome(response.body(), requestId)
    }

    private fun encode(value: String): String =
        java.net.URLEncoder.encode(value, Charsets.UTF_8).replace("+", "%20")
}

class ProviderOperationException(val safeCode: String) : RuntimeException(safeCode)
