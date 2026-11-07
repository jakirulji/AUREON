package com.aureon.storage

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedContractFixtureTest {
    @Test
    fun androidReadsTheSameVersionedFixtureAsDartAndWindows() {
        val stream = javaClass.classLoader!!.getResourceAsStream("contract-v1.json")
            ?: error("Shared contract fixture is missing")
        val fixture = JsonParser.parseString(
            stream.bufferedReader().use { it.readText() }
        ).asJsonObject

        assertEquals(1, fixture.get("schemaVersion").asInt)

        val identity = fixture.getAsJsonObject("fileIdentity")
        assertEquals("file-fixture-001", identity.get("fileId").asString)
        assertEquals("version-fixture-001", identity.get("versionId").asString)
        assertEquals("provider-folder-001", identity.get("providerParentId").asString)
        assertEquals(64, identity.get("contentFingerprintSha256").asString.length)

        val capabilities = fixture.getAsJsonObject("providerCapabilities")
        assertTrue(capabilities.get("resumableUpload").asBoolean)
        assertFalse(capabilities.get("remoteChecksum").asBoolean)
        assertEquals(8388608L, capabilities.get("maximumChunkBytes").asLong)

        val checkpoint = fixture.getAsJsonObject("transferCheckpoint")
        assertEquals("waitingForAuth", checkpoint.get("state").asString)
        assertEquals("authRequired", checkpoint.get("error").asString)
        assertEquals(524288L, checkpoint.get("acknowledgedBytes").asLong)
        assertTrue(
            checkpoint.get("acknowledgedBytes").asLong <=
                checkpoint.get("totalBytes").asLong
        )

        val cleanup = fixture.getAsJsonObject("cleanupEvidence")
        assertTrue(cleanup.get("remoteVerified").asBoolean)
        assertFalse(cleanup.get("userOptedIn").asBoolean)
        assertFalse(cleanup.get("eligible").asBoolean)
    }
}
