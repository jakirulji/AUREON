package com.aureon.storage

import com.aureon.storage.generated.AureonStorageHostApi
import com.aureon.storage.generated.TransferSnapshot

/**
 * Kotlin-owned implementation of the Pigeon host contract.
 *
 * Flutter receives transfer metadata only. Source URI and provider session
 * envelopes remain inside the native storage boundary.
 */
class AureonStorageHostApiImpl(
    private val repository: TransferCheckpointRepository,
    private val nowEpochMs: () -> Long = System::currentTimeMillis
) : AureonStorageHostApi {

    override suspend fun getTransfer(operationId: String): TransferSnapshot? {
        return repository.getTransfer(operationId)?.let { job ->
            TransferSnapshot(
                operationId = job.operationId,
                status = job.status,
                acknowledgedBytes = job.acknowledgedBytes,
                totalBytes = job.totalBytes,
                remoteVerified = job.remoteVerified
            )
        }
    }

    override suspend fun listTransfers(): List<TransferSnapshot> =
        repository.listTransfers().map { job ->
            TransferSnapshot(
                operationId = job.operationId,
                status = job.status,
                acknowledgedBytes = job.acknowledgedBytes,
                totalBytes = job.totalBytes,
                remoteVerified = job.remoteVerified
            )
        }

    override suspend fun pauseTransfer(operationId: String) {
        repository.pause(operationId, nowEpochMs())
    }

    override suspend fun resumeTransfer(operationId: String) {
        repository.resume(operationId, nowEpochMs())
    }
}
