package com.aureon.storage

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [TransferJobEntity::class],
    version = 1,
    exportSchema = true
)
abstract class AureonStorageDatabase : RoomDatabase() {
    abstract fun transferJobDao(): TransferJobDao

    companion object {
        @Volatile
        private var instance: AureonStorageDatabase? = null

        fun get(context: Context): AureonStorageDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AureonStorageDatabase::class.java,
                    "aureon-local.db"
                ).build().also { instance = it }
            }
    }
}
