package com.example.eggplantdetector.database

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "treatments")
data class Treatment (
    @PrimaryKey(autoGenerate = true)
    val treatmentID: Int = 0,
    val treatmentName: String,
    val treatmentProcedures: String,
    val dateAdded: Long = System.currentTimeMillis(),
    var dateUpdated: Long = System.currentTimeMillis()
)