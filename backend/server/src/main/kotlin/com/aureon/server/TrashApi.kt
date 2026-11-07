package com.aureon.server

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.auth.UserIdPrincipal
import io.ktor.server.auth.principal
import kotlinx.serialization.Serializable
import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID

@Serializable
data class TrashCreateRequest(
    val operationId: String,
    val deviceId: String,
    val providerAccountId: String,
    val providerItemId: String,
    val originalParentProviderItemId: String? = null,
    val trashMode: String,
    val trashContainerProviderItemId: String? = null,
    val providerOutcomeReference: String
)

@Serializable
data class TrashTransitionRequest(
    val operationId: String,
    val deviceId: String,
    val expectedRowVersion: Long,
    val providerOutcomeReference: String
)

@Serializable
data class TrashItemResponse(
    val id: String,
    val providerAccountId: String,
    val providerItemId: String,
    val originalParentProviderItemId: String?,
    val trashMode: String,
    val trashContainerProviderItemId: String?,
    val status: String,
    val trashedAt: String,
    val restoredAt: String?,
    val permanentlyDeletedAt: String?,
    val rowVersion: Long
)

@Serializable
data class TrashPageResponse(val items: List<TrashItemResponse>, val nextCursor: String?)

@Serializable
data class TrashErrorResponse(val code: String)

interface TrashRepository {
    fun list(userId: UUID, limit: Int, before: Instant?): List<TrashItemResponse>
    fun record(userId: UUID, request: TrashCreateRequest): TrashItemResponse
    fun transition(userId: UUID, trashItemId: UUID, request: TrashTransitionRequest, targetStatus: String): TrashItemResponse?
}

fun Route.configureTrashRoutes(repository: TrashRepository) {
    route("/v1/trash/items") {
        get {
            val userId = call.principal<UserIdPrincipal>()?.name?.let(::parseUuid)
            if (userId == null) {
                call.respond(HttpStatusCode.Unauthorized, TrashErrorResponse("UNAUTHORIZED"))
                return@get
            }
            val limit = call.request.queryParameters["limit"]?.toIntOrNull() ?: 50
            if (limit !in 1..100) {
                call.respond(HttpStatusCode.BadRequest, TrashErrorResponse("INVALID_LIMIT"))
                return@get
            }
            val before = call.request.queryParameters["before"]?.let {
                runCatching { Instant.parse(it) }.getOrNull()
            }
            if (call.request.queryParameters["before"] != null && before == null) {
                call.respond(HttpStatusCode.BadRequest, TrashErrorResponse("INVALID_CURSOR"))
                return@get
            }
            val rows = repository.list(userId, limit, before)
            call.respond(HttpStatusCode.OK, TrashPageResponse(rows, rows.lastOrNull()?.trashedAt))
        }
        post {
            val userId = call.principal<UserIdPrincipal>()?.name?.let(::parseUuid)
            if (userId == null) {
                call.respond(HttpStatusCode.Unauthorized, TrashErrorResponse("UNAUTHORIZED"))
                return@post
            }
            val request = runCatching { call.receive<TrashCreateRequest>() }.getOrNull()
            if (request == null || !validCreateRequest(request)) {
                call.respond(HttpStatusCode.BadRequest, TrashErrorResponse("INVALID_TRASH_REQUEST"))
                return@post
            }
            try {
                call.respond(HttpStatusCode.Created, repository.record(userId, request))
            } catch (_: IllegalArgumentException) {
                call.respond(HttpStatusCode.Conflict, TrashErrorResponse("IDEMPOTENCY_CONFLICT"))
            } catch (_: SecurityException) {
                call.respond(HttpStatusCode.Forbidden, TrashErrorResponse("OWNERSHIP_OR_DEVICE_MISMATCH"))
            }
        }
        route("/{trashItemId}") {
            post("/restore") { transitionTrash(repository, "restored") }
            post("/purge") { transitionTrash(repository, "permanently_deleted") }
        }
    }
}

private suspend fun io.ktor.server.routing.RoutingContext.transitionTrash(
    repository: TrashRepository,
    target: String
) {
    val userId = call.principal<UserIdPrincipal>()?.name?.let(::parseUuid)
    val itemId = call.parameters["trashItemId"]?.let(::parseUuid)
    if (userId == null || itemId == null) {
        call.respond(HttpStatusCode.BadRequest, TrashErrorResponse("INVALID_ID"))
        return
    }
    val request = runCatching { call.receive<TrashTransitionRequest>() }.getOrNull()
    if (request == null || parseUuid(request.operationId) == null ||
        parseUuid(request.deviceId) == null || request.expectedRowVersion < 1 ||
        request.providerOutcomeReference.isBlank() || request.providerOutcomeReference.length > 2048) {
        call.respond(HttpStatusCode.BadRequest, TrashErrorResponse("INVALID_TRANSITION_REQUEST"))
        return
    }
    try {
        val result = repository.transition(userId, itemId, request, target)
        if (result == null) call.respond(HttpStatusCode.Conflict, TrashErrorResponse("STALE_OR_TERMINAL_TRASH_ITEM"))
        else call.respond(HttpStatusCode.OK, result)
    } catch (_: SecurityException) {
        call.respond(HttpStatusCode.Forbidden, TrashErrorResponse("DEVICE_OWNERSHIP_MISMATCH"))
    }
}

private fun validCreateRequest(request: TrashCreateRequest): Boolean =
    parseUuid(request.operationId) != null &&
        parseUuid(request.deviceId) != null &&
        parseUuid(request.providerAccountId) != null &&
        request.providerItemId.isNotBlank() && request.providerItemId.length <= 1024 &&
        (request.originalParentProviderItemId == null || request.originalParentProviderItemId.length <= 1024) &&
        request.trashMode in setOf("provider_native", "provider_folder") &&
        ((request.trashMode == "provider_native" && request.trashContainerProviderItemId == null) ||
            (request.trashMode == "provider_folder" && !request.trashContainerProviderItemId.isNullOrBlank())) &&
        request.providerOutcomeReference.isNotBlank() && request.providerOutcomeReference.length <= 2048

private fun parseUuid(value: String): UUID? = runCatching { UUID.fromString(value) }.getOrNull()

class PostgresTrashRepository(private val database: DatabasePool) : TrashRepository {
    override fun list(userId: UUID, limit: Int, before: Instant?): List<TrashItemResponse> {
        require(limit in 1..100)
        return database.withConnection { connection ->
            val sql = """
                SELECT id, provider_account_id, provider_item_id, original_parent_provider_item_id,
                       trash_mode, trash_container_provider_item_id, status, trashed_at,
                       restored_at, permanently_deleted_at, row_version
                FROM trash_items
                WHERE user_id = ? AND status = 'trashed'
                  AND (? IS NULL OR trashed_at < ?)
                ORDER BY trashed_at DESC, id DESC LIMIT ?
            """.trimIndent()
            connection.prepareStatement(sql).use { statement ->
                statement.setObject(1, userId)
                statement.setTimestamp(2, before?.let(Timestamp::from))
                statement.setTimestamp(3, before?.let(Timestamp::from))
                statement.setInt(4, limit)
                statement.executeQuery().use { rows ->
                    buildList { while (rows.next()) add(rows.toTrashResponse()) }
                }
            }
        }
    }

    override fun record(userId: UUID, request: TrashCreateRequest): TrashItemResponse {
        val operationId = UUID.fromString(request.operationId)
        val deviceId = UUID.fromString(request.deviceId)
        val accountId = UUID.fromString(request.providerAccountId)
        return database.withConnection { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    """
                    INSERT INTO trash_items(user_id, provider_account_id, provider_item_id,
                        original_parent_provider_item_id, trash_mode, trash_container_provider_item_id,
                        operation_id, created_by_device_id, updated_by_device_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (user_id, operation_id) DO NOTHING
                    """.trimIndent()
                ).use { statement ->
                    statement.setObject(1, userId)
                    statement.setObject(2, accountId)
                    statement.setString(3, request.providerItemId)
                    statement.setString(4, request.originalParentProviderItemId)
                    statement.setString(5, request.trashMode)
                    statement.setString(6, request.trashContainerProviderItemId)
                    statement.setObject(7, operationId)
                    statement.setObject(8, deviceId)
                    statement.setObject(9, deviceId)
                    statement.executeUpdate()
                }
                val response = connection.prepareStatement(
                    """
                    SELECT id, provider_account_id, provider_item_id, original_parent_provider_item_id,
                           trash_mode, trash_container_provider_item_id, status, trashed_at,
                           restored_at, permanently_deleted_at, row_version, operation_id,
                           created_by_device_id
                    FROM trash_items WHERE user_id = ? AND operation_id = ?
                    """.trimIndent()
                ).use { statement ->
                    statement.setObject(1, userId)
                    statement.setObject(2, operationId)
                    statement.executeQuery().use { rows ->
                        if (!rows.next()) throw IllegalArgumentException("Idempotency operation not found")
                        if (rows.getObject("provider_account_id", UUID::class.java) != accountId ||
                            rows.getString("provider_item_id") != request.providerItemId ||
                            rows.getString("trash_mode") != request.trashMode) {
                            throw IllegalArgumentException("Idempotency key reused with different request")
                        }
                        rows.toTrashResponse()
                    }
                }
                connection.commit()
                response
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
    }

    override fun transition(
        userId: UUID,
        trashItemId: UUID,
        request: TrashTransitionRequest,
        targetStatus: String
    ): TrashItemResponse? {
        require(targetStatus in setOf("restored", "permanently_deleted"))
        val deviceId = UUID.fromString(request.deviceId)
        return database.withConnection { connection ->
            connection.autoCommit = false
            try {
                val updated = connection.prepareStatement(
                    """
                    UPDATE trash_items t
                    SET status = ?, restored_at = CASE WHEN ? = 'restored' THEN now() ELSE NULL END,
                        permanently_deleted_at = CASE WHEN ? = 'permanently_deleted' THEN now() ELSE NULL END,
                        updated_by_device_id = ?, updated_at = now(), row_version = row_version + 1
                    WHERE t.user_id = ? AND t.id = ? AND t.status = 'trashed'
                      AND t.row_version = ?
                      AND EXISTS (SELECT 1 FROM devices d WHERE d.user_id = ? AND d.id = ?)
                    RETURNING t.id, t.provider_account_id, t.provider_item_id,
                      t.original_parent_provider_item_id, t.trash_mode, t.trash_container_provider_item_id,
                      t.status, t.trashed_at, t.restored_at, t.permanently_deleted_at, t.row_version
                    """.trimIndent()
                ).use { statement ->
                    statement.setString(1, targetStatus)
                    statement.setString(2, targetStatus)
                    statement.setString(3, targetStatus)
                    statement.setObject(4, deviceId)
                    statement.setObject(5, userId)
                    statement.setObject(6, trashItemId)
                    statement.setLong(7, request.expectedRowVersion)
                    statement.setObject(8, userId)
                    statement.setObject(9, deviceId)
                    statement.executeQuery().use { rows -> if (rows.next()) rows.toTrashResponse() else null }
                }
                connection.commit()
                updated
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
    }
}

private fun java.sql.ResultSet.toTrashResponse() = TrashItemResponse(
    id = getObject("id", UUID::class.java).toString(),
    providerAccountId = getObject("provider_account_id", UUID::class.java).toString(),
    providerItemId = getString("provider_item_id"),
    originalParentProviderItemId = getString("original_parent_provider_item_id"),
    trashMode = getString("trash_mode"),
    trashContainerProviderItemId = getString("trash_container_provider_item_id"),
    status = getString("status"),
    trashedAt = getTimestamp("trashed_at").toInstant().toString(),
    restoredAt = getTimestamp("restored_at")?.toInstant()?.toString(),
    permanentlyDeletedAt = getTimestamp("permanently_deleted_at")?.toInstant()?.toString(),
    rowVersion = getLong("row_version")
)
