package com.corda.app.network

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus
import com.corda.app.events.ServiceState
import com.corda.app.security.KeyStoreManager
import com.corda.app.security.TrustedDevice
import com.corda.app.security.TrustedDeviceStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Socket client managing the Control Channel connection (Port 54321) to the Mac,
 * executing in-band pairing and bidirectional clipboard streaming over NDJSON.
 */
class ControlSocketClient(private val context: Context) {

    companion object {
        private const val TAG = "CordaControlClient"
        private const val CONNECT_TIMEOUT_MS = 6000
        private const val MAX_BUFFER_SIZE = 10 * 1024 * 1024 // 10 MB maximum NDJSON line
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var socket: Socket? = null
    private var reader: BufferedReader? = null
    private var writer: BufferedWriter? = null
    private var readJob: Job? = null
    private var heartbeatJob: Job? = null
    private var reconnectJob: Job? = null
    private var missedPongs: Int = 0
    private var heartbeatSeq: Int = 1

    var isConnected: Boolean = false
        private set

    var connectedHost: String? = null
        private set

    var connectedPort: Int = 54321
        private set

    var lastConnectedHost: String? = null
        private set

    var lastConnectedPort: Int = 54321
        private set

    private val trustedStore = TrustedDeviceStore(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    val dataStreamClient = FileDataStreamClient(context)

    /**
     * Connect and initiate the In-Band Pairing Handshake with the Mac.
     */
    fun connectAndPair(
        host: String,
        port: Int,
        pin: String,
        targetFingerprint: String = "",
        onResult: ((Boolean, String) -> Unit)? = null
    ) {
        scope.launch {
            try {
                disconnect()

                Log.i(TAG, "Membuka koneksi pairing ke Mac di $host:$port...")
                val newSocket = Socket()
                newSocket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)

                val newReader = BufferedReader(InputStreamReader(newSocket.getInputStream(), Charsets.UTF_8))
                val newWriter = BufferedWriter(OutputStreamWriter(newSocket.getOutputStream(), Charsets.UTF_8))

                socket = newSocket
                reader = newReader
                writer = newWriter
                connectedHost = host
                connectedPort = port
                isConnected = true

                // Send PAIR_REQUEST
                val androidId = getLocalDeviceId()
                val androidName = android.os.Build.MODEL ?: "Android Device"
                val pubKey = KeyStoreManager.getPublicKeyBase64()
                val fingerprint = KeyStoreManager.getPublicKeyFingerprint()

                val pairRequest = JSONObject().apply {
                    put("type", "PAIR_REQUEST")
                    put("device_id", androidId)
                    put("device_name", androidName)
                    put("platform", "android")
                    put("public_key", pubKey)
                    put("fingerprint", fingerprint)
                    put("pin", pin)
                    put("timestamp", getIso8601Timestamp())
                }

                writeLine(pairRequest.toString())

                // Wait for PAIR_RESPONSE
                val responseLine = newReader.readLine()
                if (responseLine != null) {
                    val respJson = JSONObject(responseLine)
                    val status = respJson.optString("status")

                    if (status == "ACCEPTED") {
                        val macId = respJson.optString("device_id", "mac-device")
                        val macName = respJson.optString("device_name", "MacBook")
                        val macPubKey = respJson.optString("public_key", "")
                        val macFp = respJson.optString("fingerprint", targetFingerprint)

                        // Save Mac as Trusted Device
                        val trusted = TrustedDevice(
                            id = macId,
                            name = macName,
                            platform = "macos",
                            publicKeyString = macPubKey,
                            fingerprint = macFp,
                            pairedAt = getIso8601Timestamp()
                        )
                        trustedStore.saveTrustedDevice(trusted)

                        lastConnectedHost = host
                        lastConnectedPort = port
                        missedPongs = 0

                        Log.i(TAG, "Pairing SUKSES dengan Mac '$macName' ($macFp)!")
                        CordaEventBus.postServiceState(
                            ServiceState(isRunning = true, statusMessage = "Terhubung dengan $macName")
                        )
                        CordaEventBus.postApIsolation(false)

                        // Start continuous read loop and heartbeat
                        startReadLoop()
                        startHeartbeatLoop()

                        withContext(Dispatchers.Main) {
                            onResult?.invoke(true, "Pairing berhasil!")
                        }
                        return@launch
                    } else {
                        val reason = respJson.optString("reason", "Pairing ditolak oleh Mac.")
                        Log.w(TAG, "Pairing GAGAL: status=$status, reason=$reason")
                        disconnect()
                        withContext(Dispatchers.Main) {
                            onResult?.invoke(false, reason)
                        }
                        return@launch
                    }
                } else {
                    disconnect()
                    withContext(Dispatchers.Main) {
                        onResult?.invoke(false, "Koneksi terputus saat menunggu respon pairing.")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error saat pairing ke $host:$port", e)
                disconnect()
                withContext(Dispatchers.Main) {
                    onResult?.invoke(false, e.localizedMessage ?: "Gagal terhubung ke Mac")
                }
            }
        }
    }

    /**
     * Automatically connect to a known, previously paired Mac.
     */
    fun autoConnect(host: String, port: Int) {
        if (isConnected && connectedHost == host && connectedPort == port) {
            return
        }

        scope.launch {
            try {
                disconnect()

                Log.i(TAG, "Auto-connecting ke Mac terpercaya di $host:$port...")
                val newSocket = Socket()
                newSocket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)

                socket = newSocket
                reader = BufferedReader(InputStreamReader(newSocket.getInputStream(), Charsets.UTF_8))
                writer = BufferedWriter(OutputStreamWriter(newSocket.getOutputStream(), Charsets.UTF_8))
                connectedHost = host
                connectedPort = port
                lastConnectedHost = host
                lastConnectedPort = port
                isConnected = true
                missedPongs = 0

                // Send initial heartbeat ping to establish connection with in-band fingerprint
                val ping = JSONObject().apply {
                    put("type", "HEARTBEAT_PING")
                    put("seq", heartbeatSeq++)
                    put("fingerprint", KeyStoreManager.getPublicKeyFingerprint())
                    put("device_id", getLocalDeviceId())
                    put("device_name", android.os.Build.MODEL ?: "Android Device")
                    put("timestamp", getIso8601Timestamp())
                }
                writeLine(ping.toString())

                CordaEventBus.postServiceState(
                    ServiceState(isRunning = true, statusMessage = "Terhubung dengan Mac ($host)")
                )
                CordaEventBus.postApIsolation(false)

                startReadLoop()
                startHeartbeatLoop()
            } catch (e: Exception) {
                Log.w(TAG, "Auto-connect ke $host:$port gagal: ${e.message}")
                disconnect()
            }
        }
    }

    private fun startReadLoop() {
        readJob?.cancel()
        readJob = scope.launch {
            val r = reader ?: return@launch
            try {
                while (isActive) {
                    val line = r.readLine() ?: break
                    if (line.length > MAX_BUFFER_SIZE) {
                        Log.e(TAG, "Payload melebihi batas 10MB (${line.length} bytes). Pesan diabaikan.")
                        continue
                    }
                    if (line.isNotEmpty()) {
                        handleIncomingMessage(line)
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Read loop closed: ${e.message}")
            } finally {
                val wasConnected = isConnected
                val host = connectedHost ?: lastConnectedHost
                val port = connectedPort
                disconnect()

                if (wasConnected && host != null) {
                    Log.i(TAG, "Socket terputus tiba-tiba. Menjadwalkan silent reconnect ke $host:$port...")
                    scheduleSilentReconnect(host, port)
                }
            }
        }
    }

    private fun startHeartbeatLoop() {
        heartbeatJob?.cancel()
        missedPongs = 0
        heartbeatJob = scope.launch {
            while (isActive && isConnected) {
                kotlinx.coroutines.delay(15000L) // 15 detik
                if (!isConnected) break

                if (missedPongs >= 3) {
                    Log.w(TAG, "Heartbeat timeout! 3 PONG tidak diterima (45 detik). Menghentikan socket dan silent reconnect...")
                    CordaEventBus.postServiceState(
                        ServiceState(isRunning = true, statusMessage = "Menghubungkan ulang...")
                    )
                    val host = connectedHost ?: lastConnectedHost
                    val port = connectedPort
                    disconnect()
                    if (host != null) {
                        scheduleSilentReconnect(host, port)
                    }
                    break
                }

                missedPongs++
                val ping = JSONObject().apply {
                    put("type", "HEARTBEAT_PING")
                    put("seq", heartbeatSeq++)
                    put("fingerprint", KeyStoreManager.getPublicKeyFingerprint())
                    put("device_id", getLocalDeviceId())
                    put("timestamp", getIso8601Timestamp())
                }
                writeLine(ping.toString())
                Log.d(TAG, "Mengirim HEARTBEAT_PING seq=${heartbeatSeq - 1} (missed: $missedPongs)")
            }
        }
    }

    /**
     * Silent Auto-Reconnect with exponential backoff (1s, 2s, 5s)
     */
    fun scheduleSilentReconnect(host: String, port: Int = 54321) {
        if (isConnected) return
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            val backoffDelays = listOf(1000L, 2000L, 5000L)
            for ((attempt, delayMs) in backoffDelays.withIndex()) {
                if (isConnected) break
                Log.i(TAG, "Silent reconnect percobaan #${attempt + 1} dalam ${delayMs}ms...")
                kotlinx.coroutines.delay(delayMs)
                if (isConnected) break

                try {
                    Log.i(TAG, "Mencoba reconnect ke $host:$port...")
                    val newSocket = Socket()
                    newSocket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)

                    socket = newSocket
                    reader = BufferedReader(InputStreamReader(newSocket.getInputStream(), Charsets.UTF_8))
                    writer = BufferedWriter(OutputStreamWriter(newSocket.getOutputStream(), Charsets.UTF_8))
                    connectedHost = host
                    connectedPort = port
                    lastConnectedHost = host
                    lastConnectedPort = port
                    isConnected = true
                    missedPongs = 0

                    CordaEventBus.postServiceState(
                        ServiceState(isRunning = true, statusMessage = "Terhubung dengan Mac ($host)")
                    )
                    CordaEventBus.postApIsolation(false)

                    startReadLoop()
                    startHeartbeatLoop()
                    Log.i(TAG, "Silent reconnect berhasil!")
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "Percobaan reconnect ke $host:$port gagal: ${e.message}")
                }
            }
        }
    }

    private fun handleIncomingMessage(line: String) {
        try {
            val json = JSONObject(line)
            val type = json.optString("type")

            when (type) {
                "CLIPBOARD_PAYLOAD" -> {
                    val content = json.optString("content", "")
                    val hash = json.optString("content_hash", "")
                    if (content.isNotEmpty()) {
                        Log.i(TAG, "Menerima CLIPBOARD_PAYLOAD dari Mac (${content.length} chars, hash: ${hash.take(8)}...)")

                        // 1. Register hash in Accessibility Service to prevent infinite echo loop
                        ClipboardAccessibilityService.registerRemoteHash(hash)

                        // 2. Write to Android Clipboard on Main Thread
                        mainHandler.post {
                            try {
                                val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                                val clipData = ClipData.newPlainText("Corda", content)
                                clipboardManager?.setPrimaryClip(clipData)
                            } catch (e: Exception) {
                                Log.e(TAG, "Gagal menulis ke ClipboardManager", e)
                            }
                        }

                        // 3. Post event to CordaEventBus for Flutter UI Live Viewer
                        val event = ClipboardCopiedEvent(
                            text = content,
                            timestamp = System.currentTimeMillis(),
                            isSensitive = false,
                            sourcePackage = "com.apple.mac"
                        )
                        CordaEventBus.postClipboardEvent(event)
                    }
                }
                "HEARTBEAT_PING" -> {
                    val seq = json.optInt("seq", 0)
                    val pong = JSONObject().apply {
                        put("type", "HEARTBEAT_PONG")
                        put("seq", seq)
                        put("timestamp", getIso8601Timestamp())
                    }
                    writeLine(pong.toString())
                }
                "FILE_METADATA_HEADER" -> {
                    val host = connectedHost ?: "127.0.0.1"
                    Log.i(TAG, "Menerima FILE_METADATA_HEADER dari Mac. Memulai stream penerimaan data biner...")
                    dataStreamClient.startReceiving(json, host, FileDataStreamClient.DATA_PORT)
                }
                "HEARTBEAT_PONG" -> {
                    missedPongs = 0
                    Log.d(TAG, "Heartbeat PONG diterima dari Mac (koneksi aktif).")
                }
                else -> {
                    Log.d(TAG, "Pesan kontrol tidak dikenal: $type")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing incoming NDJSON: $line", e)
        }
    }

    /**
     * Send outgoing clipboard text to the connected Mac.
     */
    fun sendClipboard(text: String, hash: String) {
        scope.launch {
            if (!isConnected) {
                val host = connectedHost ?: lastConnectedHost
                val port = connectedPort ?: lastConnectedPort
                if (host != null && port != null) {
                    Log.i(TAG, "Socket belum terhubung saat sendClipboard. Mencoba autoConnect ke $host:$port...")
                    autoConnect(host, port)
                    var attempts = 0
                    while (!isConnected && attempts < 15) {
                        kotlinx.coroutines.delay(100L)
                        attempts++
                    }
                }
            }

            if (!isConnected) {
                Log.w(TAG, "Gagal mengirim CLIPBOARD_PAYLOAD: Tidak dapat menyambung ke Mac")
                return@launch
            }

            try {
                val payload = JSONObject().apply {
                    put("type", "CLIPBOARD_PAYLOAD")
                    put("content", text)
                    put("content_type", "text/plain")
                    put("content_hash", hash)
                    put("fingerprint", KeyStoreManager.getPublicKeyFingerprint())
                    put("device_id", getLocalDeviceId())
                    put("timestamp", getIso8601Timestamp())
                }
                writeLine(payload.toString())
                Log.i(TAG, "Berhasil mengirim CLIPBOARD_PAYLOAD ke Mac (${text.length} chars)")
            } catch (e: Exception) {
                Log.e(TAG, "Gagal mengirim CLIPBOARD_PAYLOAD", e)
            }
        }
    }

    /**
     * Send raw JSON object over Control Channel.
     */
    fun sendRawJson(json: JSONObject) {
        writeLine(json.toString())
    }

    /**
     * Send files to Mac.
     */
    fun sendFiles(files: List<java.io.File>) {
        val host = connectedHost ?: return
        dataStreamClient.sendFiles(files, host, this)
    }

    @Synchronized
    private fun writeLine(line: String) {
        try {
            val w = writer ?: return
            w.write(line)
            w.write("\n")
            w.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Error writing to socket", e)
            disconnect()
        }
    }

    fun disconnect() {
        try {
            heartbeatJob?.cancel()
            heartbeatJob = null
            readJob?.cancel()
            readJob = null
            reader?.close()
            writer?.close()
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        reader = null
        writer = null
        isConnected = false
        connectedHost = null
        missedPongs = 0
    }

    private fun getLocalDeviceId(): String {
        val prefs = context.getSharedPreferences("com.corda.app.prefs", Context.MODE_PRIVATE)
        var id = prefs.getString("local_device_uuid", null)
        if (id == null) {
            id = java.util.UUID.randomUUID().toString()
            prefs.edit().putString("local_device_uuid", id).apply()
        }
        return id
    }

    private fun getIso8601Timestamp(): String {
        val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        df.timeZone = TimeZone.getTimeZone("UTC")
        return df.format(Date())
    }

    fun computeSha256(text: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
