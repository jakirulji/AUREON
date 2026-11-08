package com.aureon.storage

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.work.NetworkType
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TransferPersistenceTest {
    private lateinit var context: Context
    private lateinit var databaseName: String

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        databaseName = "aureon-test-" + System.nanoTime() + ".db"
    }

    @After
    fun tearDown() {
        context.deleteDatabase(databaseName)
    }

    @Test
    fun checkpointSurvivesDatabaseCloseAndReopen() = runBlocking {
        val first = openDatabase()
        val entity = testJob(
            operationId = "operation-persist",
            acknowledgedBytes = 512,
            totalBytes = 1024
        )
        first.transferJobDao().insert(entity)
        first.close()

        val reopened = openDatabase()
        val restored = reopened.transferJobDao().getById("operation-persist")

        assertEquals(512L, restored?.acknowledgedBytes)
        assertEquals("uploading", restored?.status)
        assertTrue(restored?.sourceReferenceEnvelope!!.contentEquals(byteArrayOf(7, 8, 9)))
        reopened.close()
    }

    @Test
    fun duplicateEnqueueCannotReplaceOrResetAnExistingCheckpoint() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-immutable", acknowledgedBytes = 600, totalBytes = 1000))

        val error = runCatching {
            repository.enqueue(testJob("operation-immutable", acknowledgedBytes = 0, totalBytes = 1000))
        }.exceptionOrNull()

        assertTrue(error is android.database.sqlite.SQLiteConstraintException)
        assertEquals(600L, repository.getTransfer("operation-immutable")?.acknowledgedBytes)
        database.close()
    }

    @Test
    fun acknowledgedProgressCannotRegress() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-monotonic", acknowledgedBytes = 500, totalBytes = 1000))

        val error = runCatching {
            repository.acknowledge("operation-monotonic", 499, 2500)
        }.exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertEquals(500L, repository.getTransfer("operation-monotonic")?.acknowledgedBytes)
        database.close()
    }

    @Test
    fun enqueueRejectsImpossibleOrPreverifiedInitialCheckpoints() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())

        val tooLarge = runCatching {
            repository.enqueue(testJob("operation-too-large", acknowledgedBytes = 1001, totalBytes = 1000))
        }.exceptionOrNull()
        val preverified = runCatching {
            repository.enqueue(
                testJob("operation-preverified", acknowledgedBytes = 1000, totalBytes = 1000)
                    .copy(remoteVerified = true, verifiedAtEpochMs = 2000)
            )
        }.exceptionOrNull()

        assertTrue(tooLarge is IllegalArgumentException)
        assertTrue(preverified is IllegalArgumentException)
        assertEquals(null, repository.getTransfer("operation-too-large"))
        assertEquals(null, repository.getTransfer("operation-preverified"))
        database.close()
    }

    @Test
    fun recoveryAfterDatabaseReopenReconcilesInFlightInsteadOfBlindlyReuploading() = runBlocking {
        val first = openDatabase()
        first.transferJobDao().insert(
            testJob("operation-uploading", acknowledgedBytes = 512, totalBytes = 1024)
        )
        first.transferJobDao().insert(
            testJob("operation-queued", acknowledgedBytes = 0, totalBytes = 2048)
                .copy(status = "queued", updatedAtEpochMs = 2000)
        )
        first.transferJobDao().insert(
            testJob("operation-auth", acknowledgedBytes = 128, totalBytes = 512)
                .copy(status = "waiting_for_auth", updatedAtEpochMs = 3000)
        )
        first.close()

        val reopened = openDatabase()
        val repository = TransferCheckpointRepository(reopened.transferJobDao())
        val plan = repository.recoveryPlan().associateBy { it.operationId }

        assertEquals(RecoveryAction.RECONCILE_PROVIDER_SESSION,
            plan["operation-uploading"]?.action)
        assertEquals(512L, plan["operation-uploading"]?.acknowledgedBytes)
        assertEquals(RecoveryAction.ENQUEUE, plan["operation-queued"]?.action)
        assertEquals(RecoveryAction.HOLD_FOR_AUTH, plan["operation-auth"]?.action)

        // Planning recovery is read-only: it never rewrites a checkpoint or starts a transfer.
        assertEquals("uploading",
            reopened.transferJobDao().getById("operation-uploading")?.status)
        assertEquals(512L,
            reopened.transferJobDao().getById("operation-uploading")?.acknowledgedBytes)
        reopened.close()
    }

    @Test
    fun sourceCleanupCannotBeOfferedBeforeRemoteVerificationAndExplicitPermission() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(
            testJob(
                operationId = "operation-cleanup",
                acknowledgedBytes = 1024,
                totalBytes = 1024,
                sourceCleanupOptIn = true,
                sourceCleanupPermissionGranted = true
            )
        )

        assertFalse(repository.canOfferSourceCleanup("operation-cleanup"))
        repository.beginFinalization("operation-cleanup", 1800)
        repository.beginVerification("operation-cleanup", 1900)
        repository.confirmRemoteVerification("operation-cleanup", 2000)
        assertTrue(repository.canOfferSourceCleanup("operation-cleanup"))
        database.close()
    }

    @Test
    fun remoteVerificationIsRejectedUntilAllBytesAreAcknowledged() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-incomplete", acknowledgedBytes = 900, totalBytes = 1000))

        val error = runCatching {
            repository.confirmRemoteVerification("operation-incomplete", 3000)
        }.exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertFalse(repository.canOfferSourceCleanup("operation-incomplete"))
        database.close()
    }

    @Test
    fun transferLifecycleRequiresUploadThenFinalizeThenVerifyInOrder() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-lifecycle", acknowledgedBytes = 0, totalBytes = 1000))

        repository.markUploading("operation-lifecycle", 1600)
        repository.acknowledge("operation-lifecycle", 1000, 1700)
        repository.beginFinalization("operation-lifecycle", 1800)
        assertEquals("finalizing", repository.getTransfer("operation-lifecycle")?.status)

        repository.beginVerification("operation-lifecycle", 1900)
        assertEquals("verifying", repository.getTransfer("operation-lifecycle")?.status)
        repository.confirmRemoteVerification("operation-lifecycle", 2000)

        val verified = repository.getTransfer("operation-lifecycle")
        assertEquals("verified", verified?.status)
        assertTrue(verified?.remoteVerified == true)
        assertEquals(2000L, verified?.verifiedAtEpochMs)
        database.close()
    }

    @Test
    fun finalizationAndVerificationCannotBeSkippedOrStartedEarly() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-order", acknowledgedBytes = 400, totalBytes = 1000))

        assertTrue(runCatching { repository.beginFinalization("operation-order", 1600) }.isFailure)
        assertTrue(runCatching { repository.beginVerification("operation-order", 1700) }.isFailure)
        assertTrue(runCatching { repository.confirmRemoteVerification("operation-order", 1800) }.isFailure)
        assertEquals("uploading", repository.getTransfer("operation-order")?.status)
        database.close()
    }

    @Test
    fun conditionWaitCanOnlyRequeueAfterTheConditionIsResolved() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-network", acknowledgedBytes = 256, totalBytes = 1000))

        repository.waitForNetwork("operation-network", 1600)
        assertEquals(RecoveryAction.HOLD_FOR_NETWORK,
            repository.recoveryPlan().single().action)
        assertTrue(runCatching { repository.markUploading("operation-network", 1700) }.isFailure)

        repository.requeue("operation-network", 1800)
        assertEquals("queued", repository.getTransfer("operation-network")?.status)
        assertEquals(256L, repository.getTransfer("operation-network")?.acknowledgedBytes)
        repository.markUploading("operation-network", 1900)
        assertEquals("uploading", repository.getTransfer("operation-network")?.status)
        database.close()
    }

    @Test
    fun pauseCanBeAppliedToWaitingTransferAndResumeReturnsItToQueue() = runBlocking {
        val database = openDatabase()
        val repository = TransferCheckpointRepository(database.transferJobDao())
        repository.enqueue(testJob("operation-pause-wait", acknowledgedBytes = 256, totalBytes = 1000))
        repository.waitForAuth("operation-pause-wait", 1600)
        repository.pause("operation-pause-wait", 1700)
        assertEquals("paused", repository.getTransfer("operation-pause-wait")?.status)
        repository.resume("operation-pause-wait", 1800)
        assertEquals("queued", repository.getTransfer("operation-pause-wait")?.status)
        database.close()
    }

    @Test
    fun transferWorkRequiresNetworkAndHealthyDeviceConditions() {
        val constraints = TransferWorkPolicy.constraints()
        assertEquals(NetworkType.CONNECTED, constraints.requiredNetworkType)
        assertTrue(constraints.requiresBatteryNotLow())
        assertTrue(constraints.requiresStorageNotLow())
    }

    private fun openDatabase(): AureonStorageDatabase =
        Room.databaseBuilder(context, AureonStorageDatabase::class.java, databaseName).build()

    private fun testJob(
        operationId: String,
        acknowledgedBytes: Long,
        totalBytes: Long,
        sourceCleanupOptIn: Boolean = false,
        sourceCleanupPermissionGranted: Boolean = false
    ) = TransferJobEntity(
        operationId = operationId,
        providerAccountId = "provider-account-test",
        sourceReferenceEnvelope = byteArrayOf(7, 8, 9),
        sourceFingerprintSha256 = ByteArray(32) { 1 },
        totalBytes = totalBytes,
        acknowledgedBytes = acknowledgedBytes,
        uploadSessionEnvelope = byteArrayOf(3, 2, 1),
        status = "uploading",
        sourceCleanupOptIn = sourceCleanupOptIn,
        sourceCleanupPermissionGranted = sourceCleanupPermissionGranted,
        remoteVerified = false,
        verifiedAtEpochMs = null,
        createdAtEpochMs = 1000,
        updatedAtEpochMs = 1500
    )
}
