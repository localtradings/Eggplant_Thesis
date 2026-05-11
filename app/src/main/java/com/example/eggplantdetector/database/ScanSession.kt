package com.example.eggplantdetector.database

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(tableName = "scan_sessions")
data class ScanSession (
    @PrimaryKey
    val sessionID: String = UUID.randomUUID().toString(),
    val startingTimestamp: Long = System.currentTimeMillis(),
    val endingTimestamp: Long = 0L,
    var totalLeaves: Int = 0,
)
