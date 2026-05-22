package com.demo.videopick.data.repository

import android.content.Context
import com.demo.videopick.data.model.SavedLocation
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object LocationStore {
    private const val PREFS_NAME = "saved_locations_v1"
    private const val KEY = "list"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun all(context: Context): List<SavedLocation> {
        val raw = prefs(context).getString(KEY, null) ?: return emptyList()
        return try {
            Json.decodeFromString<List<SavedLocation>>(raw)
                .sortedByDescending { it.createdAt }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(context: Context, location: SavedLocation) {
        val list = all(context).toMutableList()
        val idx = list.indexOfFirst { it.id == location.id }
        if (idx >= 0) list[idx] = location else list.add(location)
        persist(context, list)
    }

    fun delete(context: Context, id: String) {
        val list = all(context).filterNot { it.id == id }
        persist(context, list)
    }

    private fun persist(context: Context, list: List<SavedLocation>) {
        prefs(context).edit().putString(KEY, Json.encodeToString(list)).apply()
    }
}
