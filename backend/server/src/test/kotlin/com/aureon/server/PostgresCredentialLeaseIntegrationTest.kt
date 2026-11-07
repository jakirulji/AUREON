package com.aureon.server

import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue

class PostgresCredentialLeaseIntegrationTest {
    @Test
    fun postgresAllowsOneRefreshLeaseWinnerAndRejectsStaleCommit() {
        val jdbcUrl = System.getenv("AUREON_TEST_DATABASE_URL")
        assumeTrue(!jdbcUrl.isNullOrBlank(), "PostgreSQL integration is enabled in GitHub Actions")
        val username = System.getenv("AUREON_TEST_DATABASE_USER") ?: "aureon"
        val password = System.getenv("AUREON_TEST_DATABASE_PASSWORD") ?: ""
        val userId = UUID.randomUUID()
        val providerAccountId = UUID.randomUUID()
        val login = "lease-test-$userId@aureon.invalid"

        DatabasePool(DatabasePoolSettings(jdbcUrl!!, username, password, maximumPoolSize = 4)).use { pool ->
            insertFixture(pool, userId, providerAccountId, login)
            try {
                val repository = PostgresCredentialLeaseRepository(pool)
                val leaseA = UUID.randomUUID()
                val leaseB = UUID.randomUUID()
                val start = CountDownLatch(1)
                val executor = Executors.newFixedThreadPool(2)
                try {
                    val futureA = executor.submit<Boolean> {
                        start.await()
                        repository.acquire(userId, providerAccountId, 1, leaseA, 60)
                    }
                    val futureB = executor.submit<Boolean> {
                        start.await()
                        repository.acquire(userId, providerAccountId, 1, leaseB, 60)
                    }
                    start.countDown()
                    val acquiredA = futureA.get(10, TimeUnit.SECONDS)
                    val acquiredB = futureB.get(10, TimeUnit.SECONDS)
                    assertEquals(1, listOf(acquiredA, acquiredB).count { it })

                    val winner = if (acquiredA) leaseA else leaseB
                    val loser = if (acquiredA) leaseB else leaseA
                    assertFalse(repository.commitRotation(userId, providerAccountId, 1, loser, byteArrayOf(9, 9, 9)))
                    assertTrue(repository.commitRotation(userId, providerAccountId, 1, winner, byteArrayOf(4, 5, 6)))

                    val final = assertNotNull(repository.get(userId, providerAccountId))
                    assertEquals(2, final.version)
                    assertEquals("active", final.status)
                    assertEquals(null, final.leaseId)
                    assertTrue(final.encryptedEnvelope.contentEquals(byteArrayOf(4, 5, 6)))
                } finally {
                    executor.shutdownNow()
                }
            } finally {
                deleteFixture(pool, userId)
            }
        }
    }

    private fun insertFixture(pool: DatabasePool, userId: UUID, providerAccountId: UUID, login: String) {
        pool.withConnection { connection ->
            connection.prepareStatement(
                "INSERT INTO users(id, normalized_login_identifier, status) VALUES (?, ?, 'active')"
            ).use { statement ->
                statement.setObject(1, userId)
                statement.setString(2, login)
                statement.executeUpdate()
            }
            connection.prepareStatement(
                """
                INSERT INTO provider_accounts(id, user_id, provider, provider_subject, status)
                VALUES (?, ?, 'google_drive', ?, 'connected')
                """.trimIndent()
            ).use { statement ->
                statement.setObject(1, providerAccountId)
                statement.setObject(2, userId)
                statement.setString(3, "lease-subject-$providerAccountId")
                statement.executeUpdate()
            }
            connection.prepareStatement(
                """
                INSERT INTO provider_credentials(
                    provider_account_id, user_id, encrypted_refresh_envelope,
                    envelope_version, kms_key_reference, kms_key_version,
                    credential_status, consented_at
                ) VALUES (?, ?, ?, 1, 'ci/kms/test', 'test-v1', 'active', now())
                """.trimIndent()
            ).use { statement ->
                statement.setObject(1, providerAccountId)
                statement.setObject(2, userId)
                statement.setBytes(3, byteArrayOf(1, 2, 3))
                statement.executeUpdate()
            }
        }
    }

    private fun deleteFixture(pool: DatabasePool, userId: UUID) {
        pool.withConnection { connection ->
            connection.prepareStatement("DELETE FROM provider_credentials WHERE user_id = ?").use {
                it.setObject(1, userId)
                it.executeUpdate()
            }
            connection.prepareStatement("DELETE FROM provider_accounts WHERE user_id = ?").use {
                it.setObject(1, userId)
                it.executeUpdate()
            }
            connection.prepareStatement("DELETE FROM users WHERE id = ?").use {
                it.setObject(1, userId)
                it.executeUpdate()
            }
        }
    }
}
