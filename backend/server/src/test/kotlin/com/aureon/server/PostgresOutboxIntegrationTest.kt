package com.aureon.server

import java.time.Instant
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

class PostgresOutboxIntegrationTest {
    @Test
    fun concurrentWorkersClaimOneEventAndOnlyLeaseOwnerCanComplete() {
        val jdbcUrl = System.getenv("AUREON_TEST_DATABASE_URL")
        assumeTrue(!jdbcUrl.isNullOrBlank(), "PostgreSQL integration is enabled in GitHub Actions")
        val username = System.getenv("AUREON_TEST_DATABASE_USER") ?: "aureon"
        val password = System.getenv("AUREON_TEST_DATABASE_PASSWORD") ?: ""
        val eventId = UUID.randomUUID()
        val aggregateId = UUID.randomUUID()

        DatabasePool(DatabasePoolSettings(jdbcUrl!!, username, password, maximumPoolSize = 4)).use { pool ->
            insertEvent(pool, eventId, aggregateId)
            try {
                val repository = PostgresOutboxRepository(pool)
                val start = CountDownLatch(1)
                val executor = Executors.newFixedThreadPool(2)
                try {
                    val a = executor.submit<List<OutboxLease>> {
                        start.await()
                        repository.claimBatch(1, 60)
                    }
                    val b = executor.submit<List<OutboxLease>> {
                        start.await()
                        repository.claimBatch(1, 60)
                    }
                    start.countDown()
                    val claimed = listOf(a.get(10, TimeUnit.SECONDS), b.get(10, TimeUnit.SECONDS)).flatten()
                    assertEquals(1, claimed.size)
                    val lease = claimed.single()
                    assertEquals(eventId, lease.id)
                    assertEquals(1, lease.attemptCount)
                    assertTrue(lease.payloadReferenceJson.contains("test-reference"))
                    assertTrue(repository.complete(lease))
                    assertFalse(repository.complete(lease))
                    assertTrue(repository.claimBatch(1, 60).isEmpty())
                } finally {
                    executor.shutdownNow()
                }
            } finally {
                pool.withConnection { connection ->
                    connection.prepareStatement("DELETE FROM outbox_events WHERE id = ?").use {
                        it.setObject(1, eventId)
                        it.executeUpdate()
                    }
                }
            }
        }
    }

    @Test
    fun failedOutboxEventCanBeSafelyRescheduled() {
        val jdbcUrl = System.getenv("AUREON_TEST_DATABASE_URL")
        assumeTrue(!jdbcUrl.isNullOrBlank(), "PostgreSQL integration is enabled in GitHub Actions")
        val username = System.getenv("AUREON_TEST_DATABASE_USER") ?: "aureon"
        val password = System.getenv("AUREON_TEST_DATABASE_PASSWORD") ?: ""
        val eventId = UUID.randomUUID()

        DatabasePool(DatabasePoolSettings(jdbcUrl!!, username, password, maximumPoolSize = 2)).use { pool ->
            insertEvent(pool, eventId, UUID.randomUUID())
            try {
                val repository = PostgresOutboxRepository(pool)
                val lease = assertNotNull(repository.claimBatch(1, 60).firstOrNull())
                assertTrue(repository.reschedule(lease, Instant.now().minusSeconds(1), "TEMPORARY_FAILURE"))
                val retry = assertNotNull(repository.claimBatch(1, 60).firstOrNull())
                assertEquals(2, retry.attemptCount)
                assertTrue(repository.complete(retry))
            } finally {
                pool.withConnection { connection ->
                    connection.prepareStatement("DELETE FROM outbox_events WHERE id = ?").use {
                        it.setObject(1, eventId)
                        it.executeUpdate()
                    }
                }
            }
        }
    }

    private fun insertEvent(pool: DatabasePool, eventId: UUID, aggregateId: UUID) {
        pool.withConnection { connection ->
            connection.prepareStatement(
                """
                INSERT INTO outbox_events(id, event_type, aggregate_type, aggregate_id, payload_reference)
                VALUES (?, 'provider.inventory.scan', 'provider_account', ?, '{"reference":"test-reference"}'::jsonb)
                """.trimIndent()
            ).use { statement ->
                statement.setObject(1, eventId)
                statement.setObject(2, aggregateId)
                statement.executeUpdate()
            }
        }
    }
}
