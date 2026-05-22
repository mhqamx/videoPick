package com.demo.videopick.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.demo.videopick.data.model.SavedLocation
import com.demo.videopick.data.repository.GpxAssetImporter
import com.demo.videopick.data.repository.LocationStore
import com.demo.videopick.location.MockLocationSelection
import com.demo.videopick.service.MockLocationService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class LocationManagerViewModel(app: Application) : AndroidViewModel(app) {

    private val _locations = MutableStateFlow<List<SavedLocation>>(emptyList())
    val locations: StateFlow<List<SavedLocation>> = _locations.asStateFlow()

    private val _running = MutableStateFlow(MockLocationService.IS_RUNNING)
    val running: StateFlow<Boolean> = _running.asStateFlow()

    private val _activeId = MutableStateFlow<String?>(null)
    val activeId: StateFlow<String?> = _activeId.asStateFlow()

    init { reload() }

    fun reload() {
        _locations.value = LocationStore.all(getApplication())
        _running.value = MockLocationService.IS_RUNNING
    }

    fun upsert(location: SavedLocation) {
        LocationStore.save(getApplication(), location)
        reload()
    }

    fun delete(id: String) {
        if (_activeId.value == id) stopMock()
        LocationStore.delete(getApplication(), id)
        reload()
    }

    fun importPreset(preset: GpxAssetImporter.Preset) {
        val loc = GpxAssetImporter.load(getApplication(), preset) ?: return
        LocationStore.save(getApplication(), loc)
        reload()
    }

    fun startMock(location: SavedLocation) {
        MockLocationService.start(
            getApplication(),
            location.name,
            location.latitude,
            location.longitude,
        )
        _activeId.value = location.id
        _running.value = true
    }

    fun stopMock() {
        MockLocationService.stop(getApplication())
        _activeId.value = null
        _running.value = false
    }

    fun isMockLocationAppSelected(): Boolean {
        return MockLocationSelection.isSelected(getApplication())
    }
}
