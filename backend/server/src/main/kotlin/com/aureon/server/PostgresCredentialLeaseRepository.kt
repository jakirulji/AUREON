package com.aureon.server

import java.util.UUID

data class PersistedCredentialLease(
    val version: Long,
    val status: String,
    val leaseId: UUID?,
    val encryptedEnvelope: ByteArray
)

/**
 * PostgreSQL compare-and-swap implementation for the credential refresh lease.
 * The caller must be the isolated credential broker. This repository never
 * decrypts envelopes and must not be wired into the ordinary API workload.
 */
class PostgresCredentialLeaseRepository(private val database: DatabasePool) {
    fun acquire(userId: UUID, providerAccountId: UUID, expectedVersion: Long, leaseId: UUID, leaseSeconds: Long): Boolean {
        require(leaseSeconds in 10..900)
        return database.withConnection { connection ->
            connection.prepareStatement(
                """
                UPDATE provider_credentials
                SET credential_status = 'refreshing',
                    refresh_lease_id = ?,
                    refresh_lease_expires_at = now() + (? * INTERVAL '1 second'),
                    last_refresh_attempt_at = now(),
                    last_error_code = NULL,
                    updated_at = now()
                WHERE user_id = ?
                  AND provider_account_id = ?
                  AND credential_version = ?
                  AND (
                    credential_status = 'active'
                    OR (credential_status = 'refreshing' AND refresh_lease_expires_at < now())
                  )
                RETURNING credential_version
                """.trimIndent()
            ).use { statement ->
                statement.setObject(1, leaseId)
                statement.setLong(2, leaseSeconds)
                statement.setObject(3, userId)
                statement.setObject(4, providerAccountId)
                statement.setLong(5, expectedVersion)
                statement.executeQuery().use { it.next() }
            }
        }
    }

    fun commitRotation(userId: UUID, providerAccountId: UUID, expectedVersion: Long, leaseId: UUID, newEncryptedEnvelope: ByteArray): Boolean =
        database.withConnection { connection ->
            connection.prepareStatement(
                """
                UPDATE provider_credentials
                SET encrypted_refresh_envelope = ?,
                    credential_version = credential_version + 1,
                    credential_status = 'active',
                    refresh_lease_id = NULL,
                    refresh_lease_expires_at = NULL,
                    last_refresh_success_at = now(),
                    updated_at = now(),
                    last_error_code = NULL
                WHERE user_id = ?
                  AND provider_account_id = ?
                  AND credential_version = ?
                  AND credential_status = 'refreshing'
                  AND refresh_lease_id = ?
                  AND refresh_lease_expires_at > now()
                """.trimIndent()
            ).use { statement ->
                statement.setBytes(1, newEncryptedEnvelope)
                statement.setObject(2, userId)
                statement.setObject(3, providerAccountId)
                statement.setLong(4, expectedVersion)
                statement.setObject(5, leaseId)
                statement.executeUpdate() == 1
            }
        }

    fun releaseAfterFailure(userId: UUID, providerAccountId: UUID, expectedVersion: Long, leaseId: UUID, safeErrorCode: String): Boolean {
        require(safeErrorCode.matches(Regex("[A-Z0-9_]{1,64}")))
        return database.withConnection { connection ->
            connection.prepareStatement(
                """
                UPDATE provider_credentials
                SET credential_status = 'active',
                    refresh_lease_id = NULL,
                    refresh_lease_expires_at = NULL,
                    last_error_code = ?,
                    updated_at = now()
                WHERE user_id = ?
                  AND provider_account_id = ?
                  AND credential_version = ?
                  AND credential_status = 'refreshing'
                  AND refresh_lease_id = ?
                """.trimIndent()
            ).use { statement ->
                statement.setString(1, safeErrorCode)
                statement.setObject(2, userId)
                statement.setObject(3, providerAccountId)
                statement.setLong(4, expectedVersion)
                statement.setObject(5, leaseId)
                statement.executeUpdate() == 1
            }
        }
    }

    fun get(userId: UUID, providerAccountId: UUID): PersistedCredentialLease? =
        database.withConnection { connection ->
            connection.prepareStatement(
                """
                SELECT credential_version, credential_status, refresh_lease_id, encrypted_refresh_envelope
                FROM provider_credentials
                WHERE user_id = ? AND provider_account_id = ?
                """.trimIndent()
            ).use { statement ->
                statement.setObject(1, userId)
                statement.setObject(2, providerAccountId)
                statement.executeQuery().use { result ->
                    if (!result.next()) null
                    else PersistedCredentialLease(
                        version = result.getLong("credential_version"),
                        status = result.getString("credential_status"),
                        leaseId = result.getObject("refresh_lease_id", UUID::class.java),
                        encryptedEnvelope = result.getBytes("encrypted_refresh_envelope")
                    )
                }
            }
        }
}
