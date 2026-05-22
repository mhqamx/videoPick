package com.demo.videopick.data.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class SavedLocation(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val coordinateText: String
        get() = "%.6f,%.6f".format(latitude, longitude)
}
