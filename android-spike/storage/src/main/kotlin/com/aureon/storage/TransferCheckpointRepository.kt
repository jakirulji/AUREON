package com.aureon.storage

class TransferCheckpointRepository(private val dao: TransferJobDao) {
    suspend fun enqueue(job: TransferJobEntity) {
        require(job.operationId.isNotBlank())
        require(job.providerAccountId.isNotBlank())
        require(job.acknowledgedBytes >= 0)
        dao.upsert(job)
    }

    suspend fun acknowledge(operationId: String, bytes: Long, nowEpochMs: Long) {
        require(bytes >= 0)
        check(dao.updateAcknowledgedBytes(operationId, bytes, nowEpochMs) == 1) {
            "Transfer checkpoint rejected by current state or size invariant"
        }
    }

    suspend fun confirmRemoteVerification(operationId: String, nowEpochMs: Long) {
        check(dao.markRemoteVerified(operationId, nowEpochMs) == 1) {
            "Remote verification cannot be recorded before all bytes are acknowledged"
        }
    }

    suspend fun canOfferSourceCleanup(operationId: String): Boolean =
        dao.canOfferSourceCleanup(operationId)
}
