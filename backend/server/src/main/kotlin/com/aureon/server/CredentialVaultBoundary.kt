package com.aureon.server

/**
 * Port to a managed KMS/HSM GenerateDataKey operation.
 * Production implementations must use workload identity and authenticated context.
 * This interface intentionally contains no vendor SDK or local master key.
 */
data class GeneratedDataKey(
    val plaintextKey: ByteArray,
    val wrappedKey: ByteArray,
    val keyReference: String,
    val keyVersion: String
)

fun interface KmsDataKeyProvider {
    suspend fun generateDataKey(encryptionContext: Map<String, String>): GeneratedDataKey
}

class KmsUnavailableException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

/**
 * Narrow key-access boundary for the credential broker.
 * The caller's operation runs only after KMS succeeds; plaintext key bytes are
 * zeroed in a finally block. This is an architectural seam, not an encryption
 * implementation. A reviewed AEAD library must encrypt the credential envelope.
 */
class CredentialVaultKeyAccess(private val kms: KmsDataKeyProvider) {
    suspend fun <T> withNewDataKey(
        encryptionContext: Map<String, String>,
        operation: suspend (ByteArray, ByteArray, String, String) -> T
    ): T {
        val material = kms.generateDataKey(encryptionContext)
        return try {
            operation(
                material.plaintextKey,
                material.wrappedKey,
                material.keyReference,
                material.keyVersion
            )
        } finally {
            material.plaintextKey.fill(0)
        }
    }
}
