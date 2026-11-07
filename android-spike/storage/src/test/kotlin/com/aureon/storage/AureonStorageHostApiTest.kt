package com.aureon.storage

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
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
        database.transferJobDao().upsert(testJob())
        val result = CompletableDeferred<Result<com.aureon.storage.generated.TransferSnapshot?>>()

        api.getTransfer("operation-host-api") { result.complete(it) }
        val snapshot = result.await().getOrThrow()

        assertEquals("operation-host-api", snapshot?.operationId)
        assertEquals("uploading", snapshot?.status)
        assertEquals(400L, snapshot?.acknowledgedBytes)
        assertEquals(1000L, snapshot?.totalBytes)
        assertFalse(snapshot?.remoteVerified ?: true)
    }

    @Test
    fun hostApiReturnsNullForUnknownTransfer() = runBlocking {
        val result = CompletableDeferred<Result<com.aureon.storage.generated.TransferSnapshot?>>()
        api.getTransfer("missing-operation") { result.complete(it) }
        assertNull(result.await().getOrThrow())
    }

    @Test
    fun pauseAndResumeCommandsPersistStateTransitions() = runBlocking {
        database.transferJobDao().upsert(testJob())

        val pauseResult = CompletableDeferred<Result<Unit>>()
        api.pauseTransfer("operation-host-api") { pauseResult.complete(it) }
        pauseResult.await().getOrThrow()
        assertEquals("paused", database.transferJobDao().getById("operation-host-api")?.status)

        val resumeResult = CompletableDeferred<Result<Unit>>()
        api.resumeTransfer("operation-host-api") { resumeResult.complete(it) }
        resumeResult.await().getOrThrow()
        assertEquals("queued", database.transferJobDao().getById("operation-host-api")?.status)
    }

    @Test
    fun verifiedTransferCannotBePausedOrResumed() = runBlocking {
        database.transferJobDao().upsert(
            testJob().copy(status = "verified", remoteVerified = true, verifiedAtEpochMs = 8000L)
        )
        val result = CompletableDeferred<Result<Unit>>()
        api.pauseTransfer("operation-host-api") { result.complete(it) }
        assertTrue(result.await().isFailure)
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
