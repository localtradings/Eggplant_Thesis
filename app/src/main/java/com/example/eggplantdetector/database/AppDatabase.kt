package com.example.eggplantdetector.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        Disease::class,
        Treatment::class,
        DiseaseTreatment::class,
        ScanSession::class,
        Scan::class
    ],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun appDao(): AppDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            // if instance is not null, returns the database
            // If instance is null, creates the database
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "eggplant_database"
                )
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}