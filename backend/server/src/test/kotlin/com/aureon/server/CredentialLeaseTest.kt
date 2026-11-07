package com.aureon.server

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CredentialLeaseTest {
    @Test
    fun onlyOneConcurrentWorkerCanAcquireRefreshLease() {
        val model = InMemoryCredentialLeaseModel()
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)

        try {
            val first = pool.submit<Boolean> {
                start.await()
                model.acquire(1, "worker-a")
            }
            val second = pool.submit<Boolean> {
                start.await()
                model.acquire(1, "worker-b")
            }
            start.countDown()

            val acquired = listOf(
                first.get(5, TimeUnit.SECONDS),
                second.get(5, TimeUnit.SECONDS)
            )
            assertEquals(1, acquired.count { it })
            assertEquals(CredentialStateStatus.REFRESHING, model.snapshot().status)
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun staleWorkerCannotCommitRotatedCredential() {
        val model = InMemoryCredentialLeaseModel()
        assertTrue(model.acquire(1, "worker-a"))
        assertFalse(model.commit(1, "worker-b", "stale-envelope"))
        assertTrue(model.commit(1, "worker-a", "rotated-envelope"))

        val finalState = model.snapshot()
        assertEquals(2, finalState.version)
        assertEquals(CredentialStateStatus.ACTIVE, finalState.status)
        assertEquals(null, finalState.leaseId)
        assertEquals("rotated-envelope", finalState.encryptedEnvelope)
    }

    @Test
    fun failedRefreshCanReleaseOnlyItsOwnLease() {
        val model = InMemoryCredentialLeaseModel()
        assertTrue(model.acquire(1, "worker-a"))
        assertFalse(model.release(1, "worker-b"))
        assertTrue(model.release(1, "worker-a"))
        assertEquals(CredentialStateStatus.ACTIVE, model.snapshot().status)
    }
}
