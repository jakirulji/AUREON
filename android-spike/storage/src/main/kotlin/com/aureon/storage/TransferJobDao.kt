package com.aureon.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface TransferJobDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(job: TransferJobEntity)

    @Query("SELECT * FROM transfer_jobs WHERE operationId = :operationId LIMIT 1")
    suspend fun getById(operationId: String): TransferJobEntity?

    @Query(
        """
        UPDATE transfer_jobs
        SET status = 'paused',
            updatedAtEpochMs = :updatedAtEpochMs
        WHERE operationId = :operationId
          AND status IN ('queued', 'uploading')
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
          AND :acknowledgedBytes >= 0
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
          AND status IN ('uploading', 'paused')
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
