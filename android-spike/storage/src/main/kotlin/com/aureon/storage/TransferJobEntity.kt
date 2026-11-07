package com.aureon.storage

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "transfer_jobs",
    indices = [
        Index(value = ["status", "updatedAtEpochMs"]),
        Index(value = ["providerAccountId", "status"])
    ]
)
data class TransferJobEntity(
    @PrimaryKey val operationId: String,
    val providerAccountId: String,
    /** Encrypted reference to a persistable SAF URI; never store a raw source path here. */
    val sourceReferenceEnvelope: ByteArray?,
    val sourceFingerprintSha256: ByteArray?,
    val totalBytes: Long?,
    val acknowledgedBytes: Long,
    /** Encrypted provider upload-session state; never store a bearer URL in plaintext. */
    val uploadSessionEnvelope: ByteArray?,
    val status: String,
    val sourceCleanupOptIn: Boolean,
    val sourceCleanupPermissionGranted: Boolean,
    val remoteVerified: Boolean,
    val verifiedAtEpochMs: Long?,
    val createdAtEpochMs: Long,
    val updatedAtEpochMs: Long
)
