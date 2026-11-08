package com.aureon.storage

class TransferCheckpointRepository(private val dao: TransferJobDao) {
    suspend fun enqueue(job: TransferJobEntity) {
        require(job.operationId.isNotBlank())
        require(job.providerAccountId.isNotBlank())
        require(job.acknowledgedBytes >= 0)
        require(job.totalBytes == null || job.acknowledgedBytes <= job.totalBytes) {
            "Acknowledged bytes cannot exceed the declared transfer size"
        }
        require(!job.remoteVerified && job.verifiedAtEpochMs == null) {
            "A new transfer cannot be enqueued as remotely verified"
        }
        // INSERT/ABORT makes operation identity immutable, including under
        // concurrent enqueue attempts. A retry cannot overwrite a checkpoint.
        dao.insert(job)
    }

    suspend fun getTransfer(operationId: String): TransferJobEntity? {
        require(operationId.isNotBlank())
        return dao.getById(operationId)
    }

    suspend fun pause(operationId: String, nowEpochMs: Long) {
        require(operationId.isNotBlank())
        check(dao.pause(operationId, nowEpochMs) == 1) {
            "Transfer cannot be paused from its current state"
        }
    }

    suspend fun resume(operationId: String, nowEpochMs: Long) {
        require(operationId.isNotBlank())
        check(dao.resume(operationId, nowEpochMs) == 1) {
            "Only a paused, unverified transfer can be resumed"
        }
    }

    suspend fun acknowledge(operationId: String, bytes: Long, nowEpochMs: Long) {
        require(bytes >= 0)
        check(dao.updateAcknowledgedBytes(operationId, bytes, nowEpochMs) == 1) {
            "Transfer checkpoint rejected: progress cannot regress or exceed total size"
        }
    }

    suspend fun confirmRemoteVerification(operationId: String, nowEpochMs: Long) {
        check(dao.markRemoteVerified(operationId, nowEpochMs) == 1) {
            "Remote verification cannot be recorded before all bytes are acknowledged"
        }
    }

    suspend fun recoveryPlan(): List<RecoveryDecision> =
        TransferRecoveryPlanner.plan(dao.listResumable())

    suspend fun canOfferSourceCleanup(operationId: String): Boolean =
        dao.canOfferSourceCleanup(operationId)
}
