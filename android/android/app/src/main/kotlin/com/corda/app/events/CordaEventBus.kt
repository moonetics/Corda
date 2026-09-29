package com.corda.app.events

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

data class ClipboardCopiedEvent(
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val isSensitive: Boolean = false,
    val sourcePackage: String = ""
)

data class DiscoveredDevice(
    val id: String,
    val name: String,
    val host: String,
    val port: Int,
    val fingerprint: String = "",
    val lastSeen: Long = System.currentTimeMillis()
)

data class ServiceState(
    val isRunning: Boolean,
    val activePort: Int = 54321,
    val statusMessage: String = "Siaga"
)

/**
 * Thread-safe Reactive Event Bus linking Android native services
 * (ClipboardAccessibilityService, CordaForegroundService, and MainActivity).
 */
object CordaEventBus {
    private val scope = CoroutineScope(Dispatchers.Default)

    private val _clipboardEvents = MutableSharedFlow<ClipboardCopiedEvent>(
        replay = 1,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val clipboardEvents: SharedFlow<ClipboardCopiedEvent> = _clipboardEvents.asSharedFlow()

    private val _discoveredDevices = MutableSharedFlow<DiscoveredDevice>(
        replay = 1,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val discoveredDevices: SharedFlow<DiscoveredDevice> = _discoveredDevices.asSharedFlow()

    private val _serviceState = MutableSharedFlow<ServiceState>(
        replay = 1,
        extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val serviceState: SharedFlow<ServiceState> = _serviceState.asSharedFlow()

    fun postClipboardEvent(event: ClipboardCopiedEvent) {
        scope.launch {
            _clipboardEvents.emit(event)
        }
    }

    fun postDiscoveredDevice(device: DiscoveredDevice) {
        scope.launch {
            _discoveredDevices.emit(device)
        }
    }

    fun postServiceState(state: ServiceState) {
        scope.launch {
            _serviceState.emit(state)
        }
    }
}
