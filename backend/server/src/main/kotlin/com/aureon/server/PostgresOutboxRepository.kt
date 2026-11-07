package com.aureon.server

import java.sql.Timestamp
import java.time.Instant
import java.util.UUID

data class OutboxLease(
    val id: UUID,
    val userId: UUID?,
    val eventType: String,
    val aggregateType: String,
    val aggregateId: UUID,
    val payloadReferenceJson: String,
    val attemptCount: Int,
    val lockedUntil: Instant
)

/**
 * PostgreSQL outbox leasing model. Payloads must contain non-secret references,
 * never credentials, access tokens or raw provider upload-session URLs.
 */
class PostgresOutboxRepository(private val database: DatabasePool) {
    fun claimBatch(limit: Int, leaseSeconds: Long): List<OutboxLease> {
        require(limit in 1..100)
        require(leaseSeconds in 10..900)
        return database.withConnection { connection ->
            connection.prepareStatement(
                """
                WITH candidates AS (
                    SELECT id
                    FROM outbox_events
                    WHERE processed_at IS NULL
                      AND available_at <= now()
                      AND (locked_until IS NULL OR locked_until < now())
                    ORDER BY available_at, created_at
                    LIMIT ?
                    FOR UPDATE SKIP LOCKED
                )
                UPDATE outbox_events AS event
                SET locked_until = now() + (? * INTERVAL '1 second'),
                    attempt_count = attempt_count + 1
                FROM candidates
                WHERE event.id = candidates.id
                RETURNING event.id, event.user_id, event.event_type,
                          event.aggregate_type, event.aggregate_id,
                          event.payload_reference::text AS payload_reference_json,
                          event.attempt_count, event.locked_until
                """.trimIndent()
            ).use { statement ->
                statement.setInt(1, limit)
                statement.setLong(2, leaseSeconds)
                statement.executeQuery().use { result ->
                    buildList {
                        while (result.next()) {
                            add(
                                OutboxLease(
                                    id = result.getObject("id", UUID::class.java),
                                    userId = result.getObject("user_id", UUID::class.java),
                                    eventType = result.getString("event_type"),
                                    aggregateType = result.getString("aggregate_type"),
                                    aggregateId = result.getObject("aggregate_id", UUID::class.java),
                                    payloadReferenceJson = result.getString("payload_reference_json"),
                                    attemptCount = result.getInt("attempt_count"),
                                    lockedUntil = result.getTimestamp("locked_until").toInstant()
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    fun complete(lease: OutboxLease): Boolean = database.withConnection { connection ->
        connection.prepareStatement(
            """
            UPDATE outbox_events
            SET processed_at = now(), locked_until = NULL
            WHERE id = ? AND processed_at IS NULL AND locked_until = ?
            """.trimIndent()
        ).use { statement ->
            statement.setObject(1, lease.id)
            statement.setTimestamp(2, Timestamp.from(lease.lockedUntil))
            statement.executeUpdate() == 1
        }
    }

    fun reschedule(lease: OutboxLease, nextAttemptAt: Instant, safeErrorCode: String): Boolean {
        require(safeErrorCode.matches(Regex("[A-Z0-9_]{1,64}")))
        return database.withConnection { connection ->
            connection.prepareStatement(
                """
                UPDATE outbox_events
                SET available_at = ?, locked_until = NULL, last_error_code = ?
                WHERE id = ? AND processed_at IS NULL AND locked_until = ?
                """.trimIndent()
            ).use { statement ->
                statement.setTimestamp(1, Timestamp.from(nextAttemptAt))
                statement.setString(2, safeErrorCode)
                statement.setObject(3, lease.id)
                statement.setTimestamp(4, Timestamp.from(lease.lockedUntil))
                statement.executeUpdate() == 1
            }
        }
    }
}
