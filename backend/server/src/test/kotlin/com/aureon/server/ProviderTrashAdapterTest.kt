package com.aureon.server

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ProviderTrashAdapterTest {
    @Test
    fun googleDriveTrashUsesEncodedIdAndNativeTrashedFlag() {
        val requests = CopyOnWriteArrayList<Pair<String, String>>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val body = exchange.requestBody.bufferedReader().use { it.readText() }
            requests += exchange.requestMethod to (exchange.requestURI.toString() + "|" + body)
            val response = when (exchange.requestMethod) {
                "GET" -> """{"id":"folder/file id","parents":["parent-1"],"trashed":false}"""
                "PATCH" -> """{"id":"folder/file id","trashed":true}"""
                else -> "{}"
            }
            val bytes = response.toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val adapter = GoogleDriveTrashAdapter(
                apiBase = "http://127.0.0.1:" + server.address.port
            )
            val receipt = adapter.moveToTrash("access-token-not-real", "folder/file id")
            assertEquals("folder/file id", receipt.providerItemId)
            assertEquals("parent-1", receipt.originalParentProviderItemId)
            assertEquals("provider_native", receipt.trashMode)
            assertTrue(requests.any { it.first == "GET" && it.second.contains("folder%2Ffile%20id") })
            assertTrue(requests.any { it.first == "PATCH" && it.second.contains("folder%2Ffile%20id") && it.second.endsWith("""|{"trashed":true}""") })
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun googleDrivePermanentDeleteRequiresItemAlreadyInTrash() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val bytes = """{"id":"file-1","parents":["folder-1"],"trashed":false}""".toByteArray()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val adapter = GoogleDriveTrashAdapter(apiBase = "http://127.0.0.1:" + server.address.port)
            assertFailsWith<IllegalArgumentException> {
                adapter.permanentlyDelete("access-token-not-real", "file-1")
            }
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun providerCredentialBrokerFailsClosedWhenNotConfigured() {
        assertFailsWith<ProviderCredentialUnavailableException> {
            kotlinx.coroutines.runBlocking {
                UnavailableProviderAccessTokenBroker.withAccessToken(
                    java.util.UUID.randomUUID(),
                    java.util.UUID.randomUUID(),
                    setOf("https://www.googleapis.com/auth/drive")
                ) { "must-not-run" }
            }
        }
    }
}
