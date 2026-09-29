package com.corda.app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.corda.app.MainActivity
import com.corda.app.events.CordaEventBus
import com.corda.app.events.DiscoveredDevice
import com.corda.app.events.ServiceState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.network.ControlSocketClient
import com.corda.app.security.TrustedDeviceStore

class CordaForegroundService : Service() {

    companion object {
        private const val TAG = "CordaForegroundService"
        const val CHANNEL_ID = "corda_silent_service_channel"
        const val NOTIFICATION_ID = 1001
        const val SERVICE_TYPE = "_corda._tcp."

        const val ACTION_START = "com.corda.app.action.START_SERVICE"
        const val ACTION_STOP = "com.corda.app.action.STOP_SERVICE"

        var isRunning: Boolean = false
            private set

        var instance: CordaForegroundService? = null
            private set
    }

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var isDiscovering = false

    var socketClient: ControlSocketClient? = null
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        socketClient = ControlSocketClient(applicationContext)
        Log.i(TAG, "CordaForegroundService created.")
        createNotificationChannel()
        acquireMulticastLock()
        initNsdManager()
        observeClipboardEvents()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            Log.i(TAG, "Menerima sinyal STOP. Menghentikan foreground service...")
            stopSelf()
            return START_NOT_STICKY
        }

        Log.i(TAG, "Memulai CordaForegroundService dalam mode hening (IMPORTANCE_MIN)...")
        startSilentForeground()
        startMdnsDiscovery()
        isRunning = true
        CordaEventBus.postServiceState(ServiceState(isRunning = true, statusMessage = "Aktif di latar belakang"))

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Corda Background Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Menjaga sinkronisasi clipboard hening dan koneksi lokal dengan Mac"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun startSilentForeground() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Silent, minimal notification
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Corda siaga di latar belakang")
            .setContentText("Menjembatani Mac & Android via Wi-Fi lokal")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireMulticastLock() {
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("CordaMulticastLock")?.apply {
                setReferenceCounted(true)
                acquire()
            }
            Log.d(TAG, "Wi-Fi MulticastLock diperoleh untuk mDNS broadcast.")
        } catch (e: Exception) {
            Log.w(TAG, "Gagal memperoleh MulticastLock", e)
        }
    }

    private fun initNsdManager() {
        nsdManager = getSystemService(Context.NSD_SERVICE) as? NsdManager
    }

    private fun startMdnsDiscovery() {
        if (isDiscovering || nsdManager == null) return

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                isDiscovering = true
                Log.i(TAG, "mDNS Discovery dimulai untuk tipe: $regType")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                Log.i(TAG, "Layanan mDNS ditemukan: ${service.serviceName} (${service.serviceType})")
                if (service.serviceType.contains("_corda._tcp")) {
                    resolveMdnsService(service)
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                Log.w(TAG, "Layanan mDNS terputus/hilang: ${service.serviceName}")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                isDiscovering = false
                Log.i(TAG, "mDNS Discovery dihentikan: $serviceType")
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                isDiscovering = false
                Log.e(TAG, "Gagal memulai mDNS discovery: Error code $errorCode")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "Gagal menghentikan mDNS discovery: Error code $errorCode")
            }
        }

        try {
            nsdManager?.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.e(TAG, "Exception saat memanggil discoverServices", e)
        }
    }

    private fun resolveMdnsService(serviceInfo: NsdServiceInfo) {
        val resolver = object : NsdManager.ResolveListener {
            override fun onResolveFailed(service: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "Gagal me-resolve mDNS service '${service.serviceName}': error $errorCode")
            }

            override fun onServiceResolved(service: NsdServiceInfo) {
                val host = service.host?.hostAddress ?: return
                val port = service.port
                val name = service.serviceName
                Log.i(TAG, "mDNS Mac Ter-resolve: '$name' di $host:$port")

                var fingerprint = ""
                var deviceId = name
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val attributes = service.attributes
                    fingerprint = attributes["fp"]?.let { String(it) } ?: ""
                    deviceId = attributes["dev_id"]?.let { String(it) } ?: name
                }

                val device = DiscoveredDevice(
                    id = deviceId,
                    name = name,
                    host = host,
                    port = port,
                    fingerprint = fingerprint,
                    lastSeen = System.currentTimeMillis()
                )
                CordaEventBus.postDiscoveredDevice(device)

                // If Mac is already trusted, auto-connect immediately
                if (fingerprint.isNotEmpty() && TrustedDeviceStore(applicationContext).isFingerprintTrusted(fingerprint)) {
                    Log.i(TAG, "Mac terpercaya '$name' terdeteksi via mDNS. Auto-connecting ke $host:$port...")
                    socketClient?.autoConnect(host, port)
                }
            }
        }

        try {
            nsdManager?.resolveService(serviceInfo, resolver)
        } catch (e: Exception) {
            Log.e(TAG, "Exception saat resolveService", e)
        }
    }

    private fun observeClipboardEvents() {
        serviceScope.launch {
            CordaEventBus.clipboardEvents.collect { event ->
                Log.i(TAG, "ForegroundService memancarkan teks salinan ke Mac: '${event.text.take(40)}...'")
                val hash = ClipboardAccessibilityService.computeSha256(event.text)
                socketClient?.sendClipboard(event.text, hash)
            }
        }
    }

    fun pairDevice(host: String, port: Int, pin: String, fingerprint: String, callback: (Boolean, String) -> Unit) {
        val client = socketClient ?: ControlSocketClient(applicationContext).also { socketClient = it }
        client.connectAndPair(host, port, pin, fingerprint, callback)
    }

    override fun onDestroy() {
        super.onDestroy()
        socketClient?.disconnect()
        instance = null
        isRunning = false
        CordaEventBus.postServiceState(ServiceState(isRunning = false, statusMessage = "Layanan dinonaktifkan"))

        if (isDiscovering && discoveryListener != null) {
            try {
                nsdManager?.stopServiceDiscovery(discoveryListener)
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping discovery on destroy", e)
            }
            isDiscovering = false
        }

        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing MulticastLock", e)
        }

        serviceScope.cancel()
        Log.i(TAG, "CordaForegroundService destroyed.")
    }
}
