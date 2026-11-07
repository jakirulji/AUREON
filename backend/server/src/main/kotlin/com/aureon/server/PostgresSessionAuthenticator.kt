package com.aureon.server

import java.security.MessageDigest
import java.util.UUID

/**
 * Validates opaque AUREON session tokens by hash only. The bearer token is never
 * queried/stored in plaintext; every request checks expiry, revocation, user and device.
 */
class PostgresSessionAuthenticator(private val database: DatabasePool) : SessionAuthenticator {
    override suspend fun authenticate(bearerToken: String): AuthenticatedSession? {
        if (bearerToken.length !in 32..512 || bearerToken.any { it.isWhitespace() }) return null
        val tokenHash = MessageDigest.getInstance("SHA-256")
            .digest(bearerToken.toByteArray(Charsets.UTF_8))
        return database.withConnection { connection ->
            connection.prepareStatement(
                """
                SELECT s.user_id
                FROM sessions s
                JOIN users u ON u.id = s.user_id
                JOIN devices d ON d.user_id = s.user_id AND d.id = s.device_id
                WHERE s.token_hash = ?
                  AND s.revoked_at IS NULL
                  AND s.expires_at > now()
                  AND u.status = 'active'
                  AND d.status = 'active'
                LIMIT 1
                """.trimIndent()
            ).use { statement ->
                statement.setBytes(1, tokenHash)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) null
                    else {
                        val userId = rows.getObject("user_id", UUID::class.java)
                        connection.prepareStatement(
                            "UPDATE sessions SET last_used_at = now() WHERE token_hash = ? AND revoked_at IS NULL"
                        ).use { update ->
                            update.setBytes(1, tokenHash)
                            update.executeUpdate()
                        }
                        AuthenticatedSession(userId.toString())
                    }
                }
            }
        }
    }
}
