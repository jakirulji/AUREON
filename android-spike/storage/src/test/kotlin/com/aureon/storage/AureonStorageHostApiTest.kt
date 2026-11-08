package com.aureon.storage

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AureonStorageHostApiTest {
    private lateinit var context: Context
    private lateinit var databaseName: String
    private lateinit var database: AureonStorageDatabase
    private lateinit var api: AureonStorageHostApiImpl

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        databaseName = "aureon-host-api-" + System.nanoTime() + ".db"
        database = Room.databaseBuilder(
            context,
            AureonStorageDatabase::class.java,
            databaseName
        ).build()
        api = AureonStorageHostApiImpl(
            repository = TransferCheckpointRepository(database.transferJobDao()),
            nowEpochMs = { 9000L }
        )
    }

    @After
    fun tearDown() {
        database.close()
        context.deleteDatabase(databaseName)
    }

    @Test
    fun hostApiReturnsOnlyTransferSnapshotMetadata() = runBlocking {
        database.transferJobDao().insert(testJob())

        val snapshot = api.getTransfer("operation-host-api")

        assertEquals("operation-host-api", snapshot?.operationId)
        assertEquals("uploading", snapshot?.status)
        assertEquals(400L, snapshot?.acknowledgedBytes)
        assertEquals(1000L, snapshot?.totalBytes)
        assertFalse(snapshot?.remoteVerified ?: true)
    }

    @Test
    fun hostApiReturnsNullForUnknownTransfer() = runBlocking {
        assertNull(api.getTransfer("missing-operation"))
    }

    @Test
    fun listTransfersReturnsRecentMetadataWithoutExposingSourceOrSessionEnvelopes() = runBlocking {
        database.transferJobDao().insert(
            testJob().copy(updatedAtEpochMs = 3000L)
        )
        database.transferJobDao().insert(
            testJob().copy(
                operationId = "operation-older",
                sourceReferenceEnvelope = byteArrayOf(99, 98, 97),
                uploadSessionEnvelope = byteArrayOf(96, 95, 94),
                updatedAtEpochMs = 2000L
            )
        )

        val snapshots = api.listTransfers()

        assertEquals(listOf("operation-host-api", "operation-older"),
            snapshots.map { it.operationId })
        assertEquals(listOf("uploading", "uploading"), snapshots.map { it.status })
        assertEquals(400L, snapshots.first().acknowledgedBytes)
    }

    @Test
    fun pauseAndResumeCommandsPersistStateTransitions() = runBlocking {
        database.transferJobDao().insert(testJob())

        api.pauseTransfer("operation-host-api")
        assertEquals("paused", database.transferJobDao().getById("operation-host-api")?.status)

        api.resumeTransfer("operation-host-api")
        assertEquals("queued", database.transferJobDao().getById("operation-host-api")?.status)
    }

    @Test
    fun verifiedTransferCannotBePausedOrResumed() = runBlocking {
        database.transferJobDao().insert(
            testJob().copy(status = "verified", remoteVerified = true, verifiedAtEpochMs = 8000L)
        )

        assertTrue(runCatching { api.pauseTransfer("operation-host-api") }.isFailure)
        assertTrue(runCatching { api.resumeTransfer("operation-host-api") }.isFailure)
    }

    private fun testJob() = TransferJobEntity(
        operationId = "operation-host-api",
        providerAccountId = "provider-account-test",
        sourceReferenceEnvelope = byteArrayOf(7, 8, 9),
        sourceFingerprintSha256 = ByteArray(32) { 1 },
        totalBytes = 1000,
        acknowledgedBytes = 400,
        uploadSessionEnvelope = byteArrayOf(3, 2, 1),
        status = "uploading",
        sourceCleanupOptIn = false,
        sourceCleanupPermissionGranted = false,
        remoteVerified = false,
        verifiedAtEpochMs = null,
        createdAtEpochMs = 1000,
        updatedAtEpochMs = 1500
    )
}
