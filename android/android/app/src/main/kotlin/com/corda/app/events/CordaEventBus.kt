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

data class TransferProgressEvent(
    val transferId: String,
    val fileName: String,
    val direction: String, // "incoming" or "outgoing"
    val fileIndex: Int,
    val totalFiles: Int,
    val progressPercent: Int,
    val speedMBs: Double,
    val isCompleted: Boolean
)

data class ApIsolationEvent(
    val isSuspected: Boolean
)

data class BatteryStatusEvent(
    val level: Int,
    val isCharging: Boolean,
    val powerSource: String,
    val timestamp: Long = System.currentTimeMillis()
)

data class OtpDetectedEvent(
    val serviceName: String,
    val code: String,
    val expiresIn: Int = 60,
    val timestamp: Long = System.currentTimeMillis()
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

    private val _batteryEvents = MutableSharedFlow<BatteryStatusEvent>(
        replay = 1,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val batteryEvents: SharedFlow<BatteryStatusEvent> = _batteryEvents.asSharedFlow()

    private val _otpEvents = MutableSharedFlow<OtpDetectedEvent>(
        replay = 1,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val otpEvents: SharedFlow<OtpDetectedEvent> = _otpEvents.asSharedFlow()

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

    private val _transferEvents = MutableSharedFlow<TransferProgressEvent>(
        replay = 1,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val transferEvents: SharedFlow<TransferProgressEvent> = _transferEvents.asSharedFlow()

    private val _isolationEvents = MutableSharedFlow<ApIsolationEvent>(
        replay = 1,
        extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val isolationEvents: SharedFlow<ApIsolationEvent> = _isolationEvents.asSharedFlow()

    fun postClipboardEvent(event: ClipboardCopiedEvent) {
        scope.launch {
            _clipboardEvents.emit(event)
        }
    }

    fun postBatteryStatus(event: BatteryStatusEvent) {
        scope.launch {
            _batteryEvents.emit(event)
        }
    }

    fun postOtpDetected(event: OtpDetectedEvent) {
        scope.launch {
            _otpEvents.emit(event)
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

    fun postTransferEvent(event: TransferProgressEvent) {
        scope.launch {
            _transferEvents.emit(event)
        }
    }

    fun postApIsolation(isSuspected: Boolean) {
        scope.launch {
            _isolationEvents.emit(ApIsolationEvent(isSuspected))
        }
    }
}
