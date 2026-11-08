package com.aureon.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface TransferJobDao {
    /**
     * Operation IDs are immutable identities. A duplicate enqueue must never
     * replace an existing checkpoint or reset acknowledged progress.
     */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(job: TransferJobEntity)

    @Query("SELECT * FROM transfer_jobs WHERE operationId = :operationId LIMIT 1")
    suspend fun getById(operationId: String): TransferJobEntity?

    @Query("SELECT * FROM transfer_jobs ORDER BY updatedAtEpochMs DESC LIMIT 100")
    suspend fun listRecent(): List<TransferJobEntity>

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'uploading',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status = 'queued'
          AND remoteVerified = 0
        """
    )
    suspend fun markUploading(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'waiting_for_network',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading')
          AND remoteVerified = 0
        """
    )
    suspend fun waitForNetwork(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'waiting_for_auth',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading', 'finalizing', 'verifying')
          AND remoteVerified = 0
        """
    )
    suspend fun waitForAuth(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'waiting_for_quota',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading')
          AND remoteVerified = 0
        """
    )
    suspend fun waitForQuota(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'retry_wait',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading', 'finalizing', 'verifying',
                         'waiting_for_network', 'waiting_for_auth', 'waiting_for_quota')
          AND remoteVerified = 0
        """
    )
    suspend fun scheduleRetry(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'queued',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('waiting_for_network', 'waiting_for_auth', 'waiting_for_quota', 'retry_wait')
          AND remoteVerified = 0
        """
    )
    suspend fun requeue(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'finalizing',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status = 'uploading'
          AND remoteVerified = 0
          AND totalBytes IS NOT NULL
          AND acknowledgedBytes >= totalBytes
        """
    )
    suspend fun beginFinalization(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'verifying',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status = 'finalizing'
          AND remoteVerified = 0
        """
    )
    suspend fun beginVerification(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'paused',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading', 'waiting_for_network', 'waiting_for_auth', 'waiting_for_quota', 'retry_wait')
          AND remoteVerified = 0
        """
    )
    suspend fun pause(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'queued',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status = 'paused'
          AND remoteVerified = 0
        """
    )
    suspend fun resume(operationId: String, updatedAtEpochMs: Long): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET acknowledgedBytes = :acknowledgedBytes,
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading', 'paused')
          AND :acknowledgedBytes >= acknowledgedBytes
          AND (totalBytes IS NULL OR :acknowledgedBytes <= totalBytes)
        """
    )
    suspend fun updateAcknowledgedBytes(
        operationId: String,
        acknowledgedBytes: Long,
        updatedAtEpochMs: Long
    ): Int

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'verified',
            remoteVerified = 1,
            verifiedAtEpochMs = :verifiedAtEpochMs,
            updatedAtEpochMs = :verifiedAtEpochMs
        WHERE operationId = :operationId
          AND status = 'verifying'
          AND totalBytes IS NOT NULL
          AND acknowledgedBytes >= totalBytes
        """
    )
    suspend fun markRemoteVerified(operationId: String, verifiedAtEpochMs: Long): Int

    @Query(
        """
        SELECT EXISTS(
            SELECT 1 FROM transfer_jobs
            WHERE operationId = :operationId
              AND status = 'verified'
              AND remoteVerified = 1
              AND verifiedAtEpochMs IS NOT NULL
              AND sourceCleanupOptIn = 1
              AND sourceCleanupPermissionGranted = 1
        )
        """
    )
    suspend fun canOfferSourceCleanup(operationId: String): Boolean

    @Query(
        """
        SELECT * FROM transfer_jobs
        WHERE status IN (
            'queued', 'uploading', 'finalizing', 'verifying', 'paused',
            'waiting_for_network', 'waiting_for_auth', 'waiting_for_quota', 'retry_wait'
        )
        ORDER BY updatedAtEpochMs
        """
    )
    suspend fun listResumable(): List<TransferJobEntity>
}
