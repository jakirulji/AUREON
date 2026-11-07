package com.aureon.storage

import androidx.work.Constraints
import androidx.work.NetworkType

object TransferWorkPolicy {
    fun constraints(): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .setRequiresStorageNotLow(true)
            .build()
}
