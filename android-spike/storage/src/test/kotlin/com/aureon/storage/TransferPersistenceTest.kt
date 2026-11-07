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
@Config(sdk = [37])
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
        first.transferJobDao().upsert(entity)
        first.close()

        val reopened = openDatabase()
        val restored = reopened.transferJobDao().getById("operation-persist")

        assertEquals(512L, restored?.acknowledgedBytes)
        assertEquals("uploading", restored?.status)
        assertTrue(restored?.sourceReferenceEnvelope!!.contentEquals(byteArrayOf(7, 8, 9)))
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
