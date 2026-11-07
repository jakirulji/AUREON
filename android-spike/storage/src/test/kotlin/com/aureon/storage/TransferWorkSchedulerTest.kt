package com.aureon.storage

import android.content.Context
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.testing.WorkManagerTestInitHelper
import androidx.test.core.app.ApplicationProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

class SuccessfulTransferTestWorker(
    context: Context,
    parameters: WorkerParameters
) : Worker(context, parameters) {
    override fun doWork(): Result {
        observedOperationId = inputData.getString(TransferWorkScheduler.OPERATION_ID_KEY)
        completionLatch?.countDown()
        return Result.success()
    }

    companion object {
        @Volatile
        var observedOperationId: String? = null

        @Volatile
        var completionLatch: CountDownLatch? = null
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TransferWorkSchedulerTest {
    private lateinit var context: Context
    private lateinit var workManager: WorkManager

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        SuccessfulTransferTestWorker.observedOperationId = null
        SuccessfulTransferTestWorker.completionLatch = CountDownLatch(1)
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder()
                .setExecutor(Executors.newSingleThreadExecutor())
                .setTaskExecutor(Executors.newSingleThreadExecutor())
                .build()
        )
        workManager = WorkManager.getInstance(context)
    }

    @After
    fun tearDown() {
        workManager.cancelAllWork().result.get(10, TimeUnit.SECONDS)
        SuccessfulTransferTestWorker.completionLatch = null
    }

    @Test
    fun enqueuesUniqueDurableWorkWithOperationIdentityAndSafetyConstraints() {
        val scheduler = TransferWorkScheduler(workManager)
        val operation = scheduler.enqueue(
            "operation-scheduler-test",
            SuccessfulTransferTestWorker::class.java
        )
        operation.result.get(10, TimeUnit.SECONDS)

        val infos = workManager.getWorkInfosForUniqueWork(
            TransferWorkScheduler.uniqueWorkName("operation-scheduler-test")
        ).get(10, TimeUnit.SECONDS)

        assertEquals(1, infos.size)
        val info = infos.single()
        assertTrue(TransferWorkScheduler.TRANSFER_WORK_TAG in info.tags)
        assertNotNull(info.constraints)
        assertEquals(
            androidx.work.NetworkType.CONNECTED,
            info.constraints.requiredNetworkType
        )
        assertTrue(info.constraints.requiresBatteryNotLow())
        assertTrue(info.constraints.requiresStorageNotLow())

        val testDriver = WorkManagerTestInitHelper.getTestDriver(context)
        assertNotNull(testDriver)
        testDriver!!.setAllConstraintsMet(info.id)
        assertTrue(
            "Scheduled worker did not execute",
            SuccessfulTransferTestWorker.completionLatch!!.await(10, TimeUnit.SECONDS)
        )
        assertEquals(
            "operation-scheduler-test",
            SuccessfulTransferTestWorker.observedOperationId
        )
    }

    @Test
    fun rejectsBlankOperationIdsBeforeScheduling() {
        val scheduler = TransferWorkScheduler(workManager)
        val error = runCatching {
            scheduler.enqueue(" ", SuccessfulTransferTestWorker::class.java)
        }.exceptionOrNull()
        assertEquals(true, error is IllegalArgumentException)
    }
}
