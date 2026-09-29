package com.corda.app

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.text.TextUtils
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.CordaEventBus
import com.corda.app.services.CordaForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.corda.app/channel"
        private const val CLIPBOARD_EVENT_CHANNEL = "com.corda.app/clipboard_events"
        private const val DISCOVERY_EVENT_CHANNEL = "com.corda.app/discovery_events"
        private const val TRANSFER_EVENT_CHANNEL = "com.corda.app/transfer_events"
        private const val ISOLATION_EVENT_CHANNEL = "com.corda.app/isolation_events"
    }

    private var clipboardJob: Job? = null
    private var discoveryJob: Job? = null
    private var transferJob: Job? = null
    private var isolationJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    val status = mapOf(
                        "accessibility" to isAccessibilityServiceEnabled(this, ClipboardAccessibilityService::class.java),
                        "batteryIgnored" to isBatteryOptimizationIgnored(this),
                        "notification" to areNotificationsEnabled(this)
                    )
                    result.success(status)
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "openBatterySettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }
                "startForegroundService" -> {
                    startCordaService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopCordaService()
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(CordaForegroundService.isRunning)
                }
                "triggerHaptic" -> {
                    triggerMicroHaptic()
                    result.success(true)
                }
                "pairDevice" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 54321
                    val pin = call.argument<String>("pin") ?: ""
                    val fingerprint = call.argument<String>("fingerprint") ?: ""

                    if (host.isEmpty() || pin.isEmpty()) {
                        result.error("INVALID_ARGS", "Host dan PIN wajib diisi", null)
                        return@setMethodCallHandler
                    }

                    val service = CordaForegroundService.instance
                    if (service != null) {
                        service.pairDevice(host, port, pin, fingerprint) { success, message ->
                            if (success) triggerMicroHaptic()
                            result.success(mapOf("success" to success, "message" to message))
                        }
                    } else {
                        startCordaService()
                        val client = com.corda.app.network.ControlSocketClient(this)
                        client.connectAndPair(host, port, pin, fingerprint) { success, message ->
                            if (success) triggerMicroHaptic()
                            result.success(mapOf("success" to success, "message" to message))
                        }
                    }
                }
                "sendFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val file = java.io.File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "Berkas tidak ditemukan: $filePath", null)
                        return@setMethodCallHandler
                    }
                    val service = CordaForegroundService.instance
                    val socketClient = service?.socketClient
                    if (socketClient != null && socketClient.isConnected) {
                        socketClient.sendFiles(listOf(file))
                        result.success(true)
                    } else {
                        result.error("NOT_CONNECTED", "Belum terhubung dengan Mac.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Clipboard EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    clipboardJob?.cancel()
                    clipboardJob = CoroutineScope(Dispatchers.Main).launch {
                        CordaEventBus.clipboardEvents.collect { event ->
                            events?.success(
                                mapOf(
                                    "text" to event.text,
                                    "timestamp" to event.timestamp,
                                    "isSensitive" to event.isSensitive,
                                    "sourcePackage" to event.sourcePackage
                                )
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    clipboardJob?.cancel()
                    clipboardJob = null
                }
            }
        )

        // Discovery EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DISCOVERY_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    discoveryJob?.cancel()
                    discoveryJob = CoroutineScope(Dispatchers.Main).launch {
                        CordaEventBus.discoveredDevices.collect { device ->
                            events?.success(
                                mapOf(
                                    "id" to device.id,
                                    "name" to device.name,
                                    "host" to device.host,
                                    "port" to device.port,
                                    "fingerprint" to device.fingerprint,
                                    "lastSeen" to device.lastSeen
                                )
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    discoveryJob?.cancel()
                    discoveryJob = null
                }
            }
        )

        // Transfer EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSFER_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    transferJob?.cancel()
                    transferJob = CoroutineScope(Dispatchers.Main).launch {
                        CordaEventBus.transferEvents.collect { event ->
                            events?.success(
                                mapOf(
                                    "transferId" to event.transferId,
                                    "fileName" to event.fileName,
                                    "direction" to event.direction,
                                    "fileIndex" to event.fileIndex,
                                    "totalFiles" to event.totalFiles,
                                    "progressPercent" to event.progressPercent,
                                    "speedMBs" to event.speedMBs,
                                    "isCompleted" to event.isCompleted
                                )
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    transferJob?.cancel()
                    transferJob = null
                }
            }
        )

        // Isolation EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ISOLATION_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    isolationJob?.cancel()
                    isolationJob = CoroutineScope(Dispatchers.Main).launch {
                        CordaEventBus.isolationEvents.collect { event ->
                            events?.success(event.isSuspected)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    isolationJob?.cancel()
                    isolationJob = null
                }
            }
        )
    }

    private fun startCordaService() {
        val intent = Intent(this, CordaForegroundService::class.java).apply {
            action = CordaForegroundService.ACTION_START
        }
        ContextCompat.startForegroundService(this, intent)
    }

    private fun stopCordaService() {
        val intent = Intent(this, CordaForegroundService::class.java).apply {
            action = CordaForegroundService.ACTION_STOP
        }
        startService(intent)
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            } catch (e: Exception) {
                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(fallbackIntent)
            }
        }
    }

    private fun isAccessibilityServiceEnabled(context: Context, service: Class<out AccessibilityService>): Boolean {
        val expectedComponentName = ComponentName(context, service)
        val enabledServicesSetting = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)

        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            val enabledComponent = ComponentName.unflattenFromString(componentNameString)
            if (enabledComponent != null && enabledComponent == expectedComponentName) {
                return true
            }
        }
        return false
    }

    private fun isBatteryOptimizationIgnored(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            return powerManager?.isIgnoringBatteryOptimizations(context.packageName) == true
        }
        return true
    }

    private fun areNotificationsEnabled(context: Context): Boolean {
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun triggerMicroHaptic() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                val vibrator = vibratorManager?.defaultVibrator
                vibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                @Suppress("DEPRECATION")
                vibrator?.vibrate(20)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        clipboardJob?.cancel()
        discoveryJob?.cancel()
        transferJob?.cancel()
        isolationJob?.cancel()
    }
}
