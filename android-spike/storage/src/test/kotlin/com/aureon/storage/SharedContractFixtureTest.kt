package com.aureon.storage

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedContractFixtureTest {
    @Test
    fun androidReadsTheSameVersionedFixtureAsDartAndWindows() {
        val stream = javaClass.classLoader!!.getResourceAsStream("contract-v1.json")
            ?: error("Shared contract fixture is missing")
        val fixture = JSONObject(stream.bufferedReader().use { it.readText() })

        assertEquals(1, fixture.getInt("schemaVersion"))

        val identity = fixture.getJSONObject("fileIdentity")
        assertEquals("file-fixture-001", identity.getString("fileId"))
        assertEquals("version-fixture-001", identity.getString("versionId"))
        assertEquals("provider-folder-001", identity.getString("providerParentId"))
        assertEquals(64, identity.getString("contentFingerprintSha256").length)

        val capabilities = fixture.getJSONObject("providerCapabilities")
        assertTrue(capabilities.getBoolean("resumableUpload"))
        assertFalse(capabilities.getBoolean("remoteChecksum"))
        assertEquals(8388608L, capabilities.getLong("maximumChunkBytes"))

        val checkpoint = fixture.getJSONObject("transferCheckpoint")
        assertEquals("waitingForAuth", checkpoint.getString("state"))
        assertEquals("authRequired", checkpoint.getString("error"))
        assertEquals(524288L, checkpoint.getLong("acknowledgedBytes"))
        assertTrue(checkpoint.getLong("acknowledgedBytes") <= checkpoint.getLong("totalBytes"))

        val cleanup = fixture.getJSONObject("cleanupEvidence")
        assertTrue(cleanup.getBoolean("remoteVerified"))
        assertFalse(cleanup.getBoolean("userOptedIn"))
        assertFalse(cleanup.getBoolean("eligible"))
    }
}
