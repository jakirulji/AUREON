package com.aureon.storage

import androidx.work.ExistingWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.workDataOf

/**
 * Persists one unique WorkManager request per transfer operation.
 *
 * The caller supplies the concrete provider-aware Worker. This layer deliberately
 * does not invent a generic upload worker before provider session reconciliation
 * and provider adapters are implemented.
 */
class TransferWorkScheduler(private val workManager: WorkManager) {
    fun enqueue(
        operationId: String,
        workerClass: Class<out ListenableWorker>
    ): Operation {
        require(operationId.isNotBlank())
        val request = OneTimeWorkRequest.Builder(workerClass)
            .setInputData(workDataOf(OPERATION_ID_KEY to operationId))
            .setConstraints(TransferWorkPolicy.constraints())
            .addTag(TRANSFER_WORK_TAG)
            .build()

        return workManager.enqueueUniqueWork(
            uniqueWorkName(operationId),
            ExistingWorkPolicy.KEEP,
            request
        )
    }

    fun cancel(operationId: String): Operation {
        require(operationId.isNotBlank())
        return workManager.cancelUniqueWork(uniqueWorkName(operationId))
    }

    companion object {
        const val OPERATION_ID_KEY = "aureon.operation_id"
        const val TRANSFER_WORK_TAG = "aureon.transfer"

        fun uniqueWorkName(operationId: String): String =
            "aureon-transfer-$operationId"
    }
}
