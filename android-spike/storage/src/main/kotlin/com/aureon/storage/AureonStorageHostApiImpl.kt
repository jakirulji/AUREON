package com.aureon.storage

import com.aureon.storage.generated.AureonStorageHostApi
import com.aureon.storage.generated.TransferSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Kotlin-owned implementation of the Pigeon host contract.
 *
 * The Flutter layer receives metadata only. Source URI envelopes and provider
 * session envelopes remain inside the native storage boundary.
 */
class AureonStorageHostApiImpl(
    private val repository: TransferCheckpointRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val nowEpochMs: () -> Long = System::currentTimeMillis
) : AureonStorageHostApi {

    override fun getTransfer(
        operationId: String,
        callback: (Result<TransferSnapshot?>) -> Unit
    ) {
        scope.launch {
            runCatching {
                repository.getTransfer(operationId)?.let { job ->
                    TransferSnapshot().apply {
                        this.operationId = job.operationId
                        status = job.status
                        acknowledgedBytes = job.acknowledgedBytes
                        totalBytes = job.totalBytes
                        remoteVerified = job.remoteVerified
                    }
                }
            }.fold(
                onSuccess = { callback(Result.success(it)) },
                onFailure = { callback(Result.failure(it)) }
            )
        }
    }

    override fun pauseTransfer(
        operationId: String,
        callback: (Result<Unit>) -> Unit
    ) {
        scope.launch {
            runCatching { repository.pause(operationId, nowEpochMs()) }.fold(
                onSuccess = { callback(Result.success(Unit)) },
                onFailure = { callback(Result.failure(it)) }
            )
        }
    }

    override fun resumeTransfer(
        operationId: String,
        callback: (Result<Unit>) -> Unit
    ) {
        scope.launch {
            runCatching { repository.resume(operationId, nowEpochMs()) }.fold(
                onSuccess = { callback(Result.success(Unit)) },
                onFailure = { callback(Result.failure(it)) }
            )
        }
    }
}
