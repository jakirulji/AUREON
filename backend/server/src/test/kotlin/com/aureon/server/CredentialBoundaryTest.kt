package com.aureon.server

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CredentialBoundaryTest {
    @Test
    fun kmsFailureFailsClosedBeforeCredentialOperation() = runBlocking {
        val kms = KmsDataKeyProvider { throw KmsUnavailableException("test KMS unavailable") }
        val access = CredentialVaultKeyAccess(kms)
        var operationInvoked = false

        assertFailsWith<KmsUnavailableException> {
            access.withNewDataKey(mapOf("purpose" to "provider-credential")) { _, _, _, _ ->
                operationInvoked = true
            }
        }
        assertFalse(operationInvoked)
    }

    @Test
    fun plaintextDataKeyIsZeroedAfterUse() = runBlocking {
        val plaintext = ByteArray(32) { 7 }
        val kms = KmsDataKeyProvider {
            GeneratedDataKey(
                plaintextKey = plaintext,
                wrappedKey = byteArrayOf(1, 2, 3),
                keyReference = "fake-kms/test-key",
                keyVersion = "test-v1"
            )
        }
        val access = CredentialVaultKeyAccess(kms)
        val observedSize = access.withNewDataKey(mapOf("user" to "test-user")) {
                key, wrapped, keyReference, keyVersion ->
            assertEquals(32, key.size)
            assertEquals(3, wrapped.size)
            assertEquals("fake-kms/test-key", keyReference)
            assertEquals("test-v1", keyVersion)
            key.size
        }

        assertEquals(32, observedSize)
        assertTrue(plaintext.all { it == 0.toByte() })
    }
}
