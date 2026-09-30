package com.corda.app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.network.ControlSocketClient
import com.corda.app.receivers.BatteryBroadcastReceiver
import com.corda.app.security.KeyStoreManager
import com.corda.app.security.TrustedDeviceStore
import android.provider.Settings
import java.util.UUID

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
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var isDiscovering = false
    private var isAdvertising = false

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var batteryReceiver: BatteryBroadcastReceiver? = null
    private var apIsolationJob: Job? = null
    private var hasDiscoveredAnyPeer = false

    var socketClient: ControlSocketClient? = null
        private set

    private var clipboardManager: ClipboardManager? = null
    private val primaryClipListener = ClipboardManager.OnPrimaryClipChangedListener {
        Log.d(TAG, "ForegroundService onPrimaryClipChanged terdeteksi.")
        launchTransparentReader()
    }

    private fun launchTransparentReader() {
        try {
            val intent = Intent(this, com.corda.app.actions.TransparentClipboardReaderActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                android.app.ActivityOptions.makeBasic().apply {
                    setPendingIntentBackgroundActivityStartMode(
                        android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }
            } else {
                android.app.ActivityOptions.makeBasic()
            }
            val pendingIntent = android.app.PendingIntent.getActivity(
                this,
                1002,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0),
                options.toBundle()
            )
            pendingIntent.send()
        } catch (e: Exception) {
            Log.w(TAG, "Gagal meluncurkan TransparentClipboardReaderActivity via PendingIntent dari ForegroundService: ${e.message}")
            try {
                val fallbackIntent = Intent(this, com.corda.app.actions.TransparentClipboardReaderActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
                }
                startActivity(fallbackIntent)
            } catch (_: Exception) {}
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        socketClient = ControlSocketClient(applicationContext)
        Log.i(TAG, "CordaForegroundService created.")
        createNotificationChannel()
        acquireMulticastLock()
        initNsdManager()
        observeClipboardEvents()
        observeOtpEvents()
        observeTransferEvents()
        registerNetworkCallback()
        registerScreenReceiver()
        registerBatteryReceiver()

        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(primaryClipListener)
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
        startMdnsAdvertising()
        startMdnsDiscovery()
        scheduleAPIsolationCheck()
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

        // Clean, minimal and quiet foreground notification
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

    private fun startMdnsAdvertising() {
        if (isAdvertising || registrationListener != null || nsdManager == null) return

        val friendlyName = try {
            Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL
        } catch (_: Exception) {
            Build.MODEL
        } ?: "Android Device"

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "Corda-$friendlyName"
            serviceType = "_corda._tcp"
            port = 54321

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    val fp = KeyStoreManager.getPublicKeyFingerprint()
                    val devId = socketClient?.getLocalDeviceId() ?: UUID.randomUUID().toString()
                    setAttribute("name", friendlyName)
                    setAttribute("model", "Android")
                    setAttribute("dev_id", devId)
                    setAttribute("fp", fp)
                    setAttribute("v", "1")
                } catch (e: Exception) {
                    Log.w(TAG, "Gagal setAttribute mDNS", e)
                }
            }
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(service: NsdServiceInfo) {
                isAdvertising = true
                Log.i(TAG, "mDNS Service '${service.serviceName}' berhasil didaftarkan ke jaringan!")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                isAdvertising = false
                registrationListener = null
                Log.e(TAG, "Gagal mendaftarkan mDNS Service: Error code $errorCode")
            }

            override fun onServiceUnregistered(service: NsdServiceInfo) {
                isAdvertising = false
                registrationListener = null
                Log.i(TAG, "mDNS Service '${service.serviceName}' telah dihentikan (unregistered).")
            }

            override fun onUnregistrationFailed(service: NsdServiceInfo, errorCode: Int) {
                isAdvertising = false
                registrationListener = null
                Log.e(TAG, "Gagal menghentikan mDNS Service: Error code $errorCode")
            }
        }

        try {
            nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        } catch (e: Exception) {
            Log.e(TAG, "Exception saat memanggil registerService", e)
            registrationListener = null
            isAdvertising = false
        }
    }

    private fun stopMdnsAdvertising() {
        val listener = registrationListener ?: return
        if (nsdManager == null) return
        try {
            nsdManager?.unregisterService(listener)
        } catch (e: Exception) {
            Log.w(TAG, "Exception saat unregisterService", e)
        } finally {
            registrationListener = null
            isAdvertising = false
        }
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
                    val friendlyName = try {
                        Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL
                    } catch (_: Exception) {
                        Build.MODEL
                    }
                    if (service.serviceName.contains(friendlyName) || service.serviceName.contains(Build.MODEL)) {
                        Log.d(TAG, "Mengabaikan layanan mDNS milik perangkat lokal sendiri: ${service.serviceName}")
                        return
                    }
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

                hasDiscoveredAnyPeer = true
                apIsolationJob?.cancel()
                CordaEventBus.postApIsolation(false)

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
                // Filter out internal synthetic file/folder labels from remote broadcast
                if (event.text.startsWith("[File: ") || event.text.startsWith("🖼️ ") || event.text.startsWith("📁 ")) {
                    Log.d(TAG, "Mengabaikan label berkas internal dari siaran remote socket: '${event.text}'")
                    return@collect
                }
                Log.i(TAG, "ForegroundService memancarkan teks salinan ke Mac: '${event.text.take(40)}...'")
                val hash = ClipboardAccessibilityService.computeSha256(event.text)
                socketClient?.sendClipboard(event.text, hash)
            }
        }
    }

    private fun observeOtpEvents() {
        serviceScope.launch {
            CordaEventBus.otpEvents.collect { event ->
                Log.i(TAG, "ForegroundService memancarkan OTP ke Mac: [${event.code}] dari '${event.serviceName}'")
                socketClient?.sendOtpDetected(event.serviceName, event.code, event.expiresIn)
            }
        }
    }

    private fun registerBatteryReceiver() {
        try {
            batteryReceiver = BatteryBroadcastReceiver { level, isCharging, powerSource ->
                socketClient?.sendBatteryStatus(level, isCharging, powerSource)
            }
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            registerReceiver(batteryReceiver, filter)
            Log.i(TAG, "BatteryBroadcastReceiver berhasil didaftarkan.")
        } catch (e: Exception) {
            Log.e(TAG, "Gagal mendaftarkan BatteryBroadcastReceiver", e)
        }
    }

    private fun observeTransferEvents() {
        serviceScope.launch {
            CordaEventBus.transferEvents.collect { event ->
                updateTransferNotification(event.fileName, event.progressPercent, event.isCompleted)
            }
        }
    }

    private fun updateTransferNotification(fileName: String, progressPercent: Int, isCompleted: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (isCompleted) "Transfer Selesai ✨" else "Mentransfer $fileName")
            .setContentText(if (isCompleted) "$fileName tersimpan di Downloads/Corda" else "$progressPercent%")
            .setOngoing(!isCompleted)
            .setProgress(100, progressPercent, false)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        notificationManager.notify(NOTIFICATION_ID, builder.build())

        if (isCompleted) {
            serviceScope.launch {
                kotlinx.coroutines.delay(3000)
                startSilentForeground()
            }
        }
    }

    fun pairDevice(host: String, port: Int, pin: String, fingerprint: String, callback: (Boolean, String) -> Unit) {
        val client = socketClient ?: ControlSocketClient(applicationContext).also { socketClient = it }
        client.connectAndPair(host, port, pin, fingerprint, callback)
    }

    private fun scheduleAPIsolationCheck() {
        apIsolationJob?.cancel()
        apIsolationJob = serviceScope.launch {
            kotlinx.coroutines.delay(10000L) // 10 detik
            val isConnected = socketClient?.isConnected == true
            if (!isConnected && !hasDiscoveredAnyPeer) {
                Log.w(TAG, "Wi-Fi aktif namun 0 peer ditemukan dalam 10s. Mengindikasikan AP Isolation.")
                CordaEventBus.postApIsolation(true)
            } else {
                CordaEventBus.postApIsolation(false)
            }
        }
    }

    private fun registerNetworkCallback() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Log.i(TAG, "Jaringan Wi-Fi aktif. Memulai mDNS advertising, discovery dan silent auto-connect...")
                    hasDiscoveredAnyPeer = false
                    startMdnsAdvertising()
                    startMdnsDiscovery()
                    scheduleAPIsolationCheck()

                    val client = socketClient
                    if (client != null && !client.isConnected) {
                        val host = client.lastConnectedHost
                        val port = client.lastConnectedPort
                        if (host != null) {
                            client.scheduleSilentReconnect(host, port)
                        }
                    }
                }

                override fun onLost(network: Network) {
                    Log.w(TAG, "Jaringan Wi-Fi terputus.")
                    stopMdnsAdvertising()
                    apIsolationJob?.cancel()
                    CordaEventBus.postApIsolation(false)
                    socketClient?.disconnect()
                    CordaEventBus.postServiceState(ServiceState(isRunning = true, statusMessage = "Menunggu Wi-Fi..."))
                }
            }
            networkCallback?.let { connectivityManager?.registerNetworkCallback(request, it) }
        } catch (e: Exception) {
            Log.w(TAG, "Gagal mendaftarkan NetworkCallback", e)
        }
    }

    private fun registerScreenReceiver() {
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_SCREEN_ON) {
                    Log.i(TAG, "Layar menyala (ACTION_SCREEN_ON). Memicu silent reconnect & mDNS refresh...")
                    val client = socketClient
                    if (client != null && !client.isConnected) {
                        val host = client.lastConnectedHost
                        val port = client.lastConnectedPort
                        if (host != null) {
                            client.scheduleSilentReconnect(host, port)
                        } else {
                            startMdnsDiscovery()
                            scheduleAPIsolationCheck()
                        }
                    }
                }
            }
        }
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        apIsolationJob?.cancel()
        apIsolationJob = null

        try {
            networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (_: Exception) {}

        try {
            screenReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}

        if (batteryReceiver != null) {
            try {
                unregisterReceiver(batteryReceiver)
            } catch (_: Exception) {}
            batteryReceiver = null
        }

        try {
            clipboardManager?.removePrimaryClipChangedListener(primaryClipListener)
        } catch (_: Exception) {}

        socketClient?.disconnect()
        instance = null
        isRunning = false
        CordaEventBus.postServiceState(ServiceState(isRunning = false, statusMessage = "Layanan dinonaktifkan"))

        stopMdnsAdvertising()
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
