package com.example.eggplantdetector.database

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    //For inner joining the tables to avoid 1 to 1 or many to many
    tableName = "disease_treatments",
    primaryKeys = ["diseaseID", "treatmentID"],
    indices = [Index("treatmentID")],

    foreignKeys = [
        ForeignKey(
            entity = Disease::class,
            parentColumns = ["diseaseID"],
            childColumns = ["diseaseID"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = Treatment::class,
            parentColumns = ["treatmentID"],
            childColumns = ["treatmentID"],
            onDelete = ForeignKey.CASCADE
        ),
    ]
)


data class DiseaseTreatment(
    //Foreign keys
    val diseaseID: Int,
    val treatmentID: Int,
    val applicationFrequency: String, // This attribute shows how often the treatment is applied
    val effectivenessNotes: String     // Shows effectiveness of the treatment
)