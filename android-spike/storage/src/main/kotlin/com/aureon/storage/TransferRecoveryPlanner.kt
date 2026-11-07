package com.aureon.storage

enum class RecoveryAction {
    ENQUEUE,
    RECONCILE_PROVIDER_SESSION,
    HOLD_FOR_NETWORK,
    HOLD_FOR_AUTH,
    HOLD_FOR_QUOTA,
    KEEP_PAUSED,
    WAIT_FOR_RETRY_WINDOW,
    REQUIRE_MANUAL_REVIEW,
    NO_ACTION
}

data class RecoveryDecision(
    val operationId: String,
    val action: RecoveryAction,
    val acknowledgedBytes: Long,
    val totalBytes: Long?
)

/**
 * Rebuilds a safe recovery plan from durable Room checkpoints after process restart.
 *
 * Crucially, an in-flight upload is never blindly re-enqueued: its provider session
 * must be reconciled first because the last provider acknowledgement may have been
 * lost when the process died.
 */
object TransferRecoveryPlanner {
    fun plan(jobs: List<TransferJobEntity>): List<RecoveryDecision> =
        jobs.sortedBy { it.updatedAtEpochMs }.map { job ->
            val action = when (job.status) {
                "queued" -> RecoveryAction.ENQUEUE
                "uploading", "finalizing", "verifying" ->
                    RecoveryAction.RECONCILE_PROVIDER_SESSION
                "paused" -> RecoveryAction.KEEP_PAUSED
                "waiting_for_network" -> RecoveryAction.HOLD_FOR_NETWORK
                "waiting_for_auth" -> RecoveryAction.HOLD_FOR_AUTH
                "waiting_for_quota" -> RecoveryAction.HOLD_FOR_QUOTA
                "retry_wait" -> RecoveryAction.WAIT_FOR_RETRY_WINDOW
                "conflict", "failed" -> RecoveryAction.REQUIRE_MANUAL_REVIEW
                "verified", "cancelled" -> RecoveryAction.NO_ACTION
                else -> RecoveryAction.REQUIRE_MANUAL_REVIEW
            }
            RecoveryDecision(
                operationId = job.operationId,
                action = action,
                acknowledgedBytes = job.acknowledgedBytes,
                totalBytes = job.totalBytes
            )
        }
}
