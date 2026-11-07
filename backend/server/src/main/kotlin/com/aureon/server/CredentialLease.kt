package com.aureon.server

import java.util.concurrent.atomic.AtomicReference

enum class CredentialStateStatus { ACTIVE, REFRESHING, REAUTH_REQUIRED, REVOKED }

data class CredentialLeaseState(
    val version: Long,
    val status: CredentialStateStatus,
    val leaseId: String?,
    val encryptedEnvelope: String
)

/**
 * In-memory CAS model used only by the A0 spike.
 * Production must implement the same transition with a PostgreSQL transaction
 * and row-level compare-and-swap; this class is not a persistent credential store.
 */
class InMemoryCredentialLeaseModel(initialEnvelope: String = "opaque-test-envelope") {
    private val state = AtomicReference(
        CredentialLeaseState(1, CredentialStateStatus.ACTIVE, null, initialEnvelope)
    )

    fun snapshot(): CredentialLeaseState = state.get()

    fun acquire(expectedVersion: Long, leaseId: String): Boolean {
        while (true) {
            val current = state.get()
            if (current.version != expectedVersion || current.status != CredentialStateStatus.ACTIVE) {
                return false
            }
            val next = current.copy(status = CredentialStateStatus.REFRESHING, leaseId = leaseId)
            if (state.compareAndSet(current, next)) return true
        }
    }

    fun commit(expectedVersion: Long, leaseId: String, newEncryptedEnvelope: String): Boolean {
        while (true) {
            val current = state.get()
            if (current.version != expectedVersion ||
                current.status != CredentialStateStatus.REFRESHING ||
                current.leaseId != leaseId
            ) {
                return false
            }
            val next = CredentialLeaseState(
                version = current.version + 1,
                status = CredentialStateStatus.ACTIVE,
                leaseId = null,
                encryptedEnvelope = newEncryptedEnvelope
            )
            if (state.compareAndSet(current, next)) return true
        }
    }

    fun release(expectedVersion: Long, leaseId: String): Boolean {
        while (true) {
            val current = state.get()
            if (current.version != expectedVersion ||
                current.status != CredentialStateStatus.REFRESHING ||
                current.leaseId != leaseId
            ) {
                return false
            }
            val next = current.copy(status = CredentialStateStatus.ACTIVE, leaseId = null)
            if (state.compareAndSet(current, next)) return true
        }
    }
}
