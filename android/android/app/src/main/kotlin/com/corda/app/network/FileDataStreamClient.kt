package com.corda.app.network

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import com.corda.app.events.CordaEventBus
import com.corda.app.events.TransferProgressEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import android.content.ClipData
import android.content.ClipboardManager
import androidx.core.content.FileProvider
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.security.KeyStoreManager
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID

/**
 * High-Speed Binary Data Stream Client for Android running on Port 54322,
 * implementing 256KB chunk streaming, dual SHA-256 integrity verification,
 * and Auto-Accept to Downloads/Corda without overwriting existing files.
 */
class FileDataStreamClient(private val context: Context) {

    companion object {
        private const val TAG = "CordaDataStream"
        const val DATA_PORT = 54322
        const val CHUNK_SIZE = 262144 // 256 KB
        val MAGIC_BYTES = byteArrayOf(0x43, 0x4F, 0x52, 0x44) // "CORD"
    }

    private val scope = CoroutineScope(Dispatchers.IO)

    // MARK: - Receiver (Mac -> Android)

    /**
     * Start receiving incoming clipboard file from Mac following CLIPBOARD_FILE_ANNOUNCE.
     */
    fun startReceivingClipboardFile(metadata: JSONObject, host: String, port: Int = DATA_PORT) {
        val enriched = JSONObject(metadata.toString())
        val fileName = metadata.optString("file_name", "clipboard_file")
        val sizeBytes = metadata.optLong("size_bytes", 0L)
        val sha256 = metadata.optString("sha256", "")
        enriched.put("is_clipboard", true)
        enriched.put("total_files", 1)
        enriched.put("total_bytes", sizeBytes)
        val filesArr = org.json.JSONArray().apply {
            put(JSONObject().apply {
                put("name", fileName)
                put("relative_path", fileName)
                put("size_bytes", sizeBytes)
                put("sha256", sha256)
                put("mime_type", metadata.optString("mime_type", ""))
            })
        }
        enriched.put("files", filesArr)
        startReceiving(enriched, host, port)
    }

    /**
     * Start receiving incoming transfer from Mac following FILE_METADATA_HEADER announcement.
     */
    fun startReceiving(metadata: JSONObject, host: String, port: Int = DATA_PORT) {
        scope.launch {
            var socket: Socket? = null
            var tempFile: File? = null
            var fileOutputStream: FileOutputStream? = null
            var transferIdStr = metadata.optString("transfer_id", UUID.randomUUID().toString())
            var currentFileIdx = 0
            var totalFiles = metadata.optInt("total_files", 1)

            try {
                val transferUuid = try {
                    UUID.fromString(transferIdStr)
                } catch (_: Exception) {
                    UUID.randomUUID()
                }

                val totalBytes = metadata.optLong("total_bytes", 0L)
                val filesArray = metadata.optJSONArray("files")

                Log.i(TAG, "Membuka socket data ke Mac di $host:$port untuk transfer $transferIdStr...")
                socket = Socket().apply {
                    tcpNoDelay = true
                    sendBufferSize = 2 * 1024 * 1024
                    receiveBufferSize = 2 * 1024 * 1024
                    soTimeout = 30000
                }
                socket.connect(InetSocketAddress(host, port), 6000)

                val inputStream = BufferedInputStream(socket.getInputStream(), CHUNK_SIZE)
                val outputStream = BufferedOutputStream(socket.getOutputStream())

                // 1. Send 40-byte READY_PULL frame (msgType = 0x04)
                val readyPullHeader = buildHeader(
                    msgType = 0x04.toByte(),
                    transferUuid = transferUuid,
                    fileIndex = 0,
                    chunkIndex = 0,
                    totalChunks = 0,
                    payloadLength = 0
                )
                outputStream.write(readyPullHeader)
                outputStream.flush()
                Log.i(TAG, "Frame READY_PULL terkirim ke Mac. Siap menerima chunk data biner...")

                var currentFileIdx = 0
                var transferredBytesTotal = 0L
                val startTime = System.currentTimeMillis()
                var currentFileHasher = MessageDigest.getInstance("SHA-256")

                val headerBuffer = ByteArray(40)

                while (true) {
                    readFully(inputStream, headerBuffer)

                    // Verify magic bytes
                    if (headerBuffer[0] != MAGIC_BYTES[0] ||
                        headerBuffer[1] != MAGIC_BYTES[1] ||
                        headerBuffer[2] != MAGIC_BYTES[2] ||
                        headerBuffer[3] != MAGIC_BYTES[3]
                    ) {
                        Log.e(TAG, "Magic bytes 'CORD' tidak cocok! Stream receiver keluar.")
                        break
                    }

                    val msgType = headerBuffer[5].toInt() and 0xFF
                    val payloadLen = ByteBuffer.wrap(headerBuffer, 36, 4).order(ByteOrder.BIG_ENDIAN).int

                    if (msgType == 0x01) { // CHUNK_DATA
                        val payload = ByteArray(payloadLen)
                        readFully(inputStream, payload)

                        val chunkChecksum = ByteArray(32)
                        readFully(inputStream, chunkChecksum)

                        // Verify chunk SHA-256
                        val mdChunk = MessageDigest.getInstance("SHA-256")
                        val calculatedChunkHash = mdChunk.digest(payload)
                        if (!calculatedChunkHash.contentEquals(chunkChecksum)) {
                            Log.e(TAG, "Checksum chunk tidak valid! Corrupt chunk diabaikan.")
                            continue
                        }

                        // Lazy init temp file writer
                        if (fileOutputStream == null) {
                            tempFile = File.createTempFile("corda_rx_", ".part", context.cacheDir)
                            fileOutputStream = FileOutputStream(tempFile)
                            currentFileHasher = MessageDigest.getInstance("SHA-256")
                        }

                        fileOutputStream.write(payload)
                        currentFileHasher.update(payload)
                        transferredBytesTotal += payloadLen

                        // Calculate live speed and percent
                        val elapsedSeconds = maxOf(0.001, (System.currentTimeMillis() - startTime) / 1000.0)
                        val speedMBs = (transferredBytesTotal / (1024.0 * 1024.0)) / elapsedSeconds
                        val percent = if (totalBytes > 0) ((transferredBytesTotal * 100) / totalBytes).toInt().coerceIn(0, 100) else 0

                        val currentFileName = if (filesArray != null && currentFileIdx < filesArray.length()) {
                            filesArray.getJSONObject(currentFileIdx).optString("name", "File")
                        } else {
                            "File"
                        }

                        CordaEventBus.postTransferEvent(
                            TransferProgressEvent(
                                transferId = transferIdStr,
                                fileName = currentFileName,
                                direction = "incoming",
                                fileIndex = currentFileIdx,
                                totalFiles = totalFiles,
                                progressPercent = percent,
                                speedMBs = speedMBs,
                                isCompleted = false
                            )
                        )
                    } else if (msgType == 0x02) { // FILE_COMPLETE
                        fileOutputStream?.flush()
                        fileOutputStream?.close()
                        fileOutputStream = null

                        val finalDigest = currentFileHasher.digest()
                        val finalHex = finalDigest.joinToString("") { "%02x".format(it) }

                        val fileMeta = filesArray?.optJSONObject(currentFileIdx)
                        val expectedSha256 = fileMeta?.optString("sha256", "")?.lowercase() ?: ""
                        val fileName = fileMeta?.optString("name", "received_file") ?: "received_file"

                        if (expectedSha256.isEmpty() || finalHex.equals(expectedSha256, ignoreCase = true)) {
                            // Move from temp to Downloads/Corda/
                            val destFolder = getDownloadsCordaFolder()
                            val destFile = getUniqueDestinationFile(destFolder, fileName)
                            tempFile?.let { src ->
                                copyFile(src, destFile)
                                src.delete()
                            }
                            Log.i(TAG, "File tersimpan dengan sukses: ${destFile.absolutePath}")

                            // If this is an auto-synced clipboard file/image, inject directly into Android Clipboard!
                            if (metadata.optBoolean("is_clipboard", false)) {
                                injectFileToClipboard(destFile, finalHex, fileMeta?.optString("mime_type", ""))
                            }
                        } else {
                            Log.e(TAG, "Full-file hash mismatch! Expected: $expectedSha256, Got: $finalHex. Menghapus file sementara.")
                            tempFile?.delete()
                        }

                        tempFile = null
                        currentFileIdx++
                    } else if (msgType == 0x03) { // TRANSFER_COMPLETE
                        Log.i(TAG, "Seluruh file berhasil diterima!")
                        triggerSuccessHaptic()

                        CordaEventBus.postTransferEvent(
                            TransferProgressEvent(
                                transferId = transferIdStr,
                                fileName = "Transfer Selesai",
                                direction = "incoming",
                                fileIndex = totalFiles,
                                totalFiles = totalFiles,
                                progressPercent = 100,
                                speedMBs = 0.0,
                                isCompleted = true
                            )
                        )
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error dalam stream biner receiver: ${e.message}", e)
                CordaEventBus.postTransferEvent(
                    TransferProgressEvent(
                        transferId = transferIdStr,
                        fileName = "Transfer Terputus",
                        direction = "incoming",
                        fileIndex = currentFileIdx,
                        totalFiles = totalFiles,
                        progressPercent = 0,
                        speedMBs = 0.0,
                        isCompleted = false
                    )
                )
            } finally {
                try { fileOutputStream?.close() } catch (_: Exception) {}
                try {
                    if (tempFile?.exists() == true) {
                        tempFile?.delete()
                        Log.i(TAG, "Membersihkan berkas sementara .part: ${tempFile?.name}")
                    }
                } catch (_: Exception) {}
                try { socket?.close() } catch (_: Exception) {}
            }
        }
    }

    // MARK: - Sender (Android -> Mac)

    /**
     * Send copied clipboard file or image (<= 50MB) to Mac.
     */
    fun sendClipboardFile(
        file: File,
        mimeType: String,
        sha256: String,
        host: String,
        controlClient: ControlSocketClient
    ) {
        scope.launch {
            var socket: Socket? = null
            val transferId = UUID.randomUUID()
            try {
                if (!file.exists()) return@launch
                val fileSize = file.length()
                if (fileSize <= 0 || fileSize > 52428800L) return@launch // <= 50MB

                // 1. Announce CLIPBOARD_FILE_ANNOUNCE on Control Channel (Port 54321)
                val announce = JSONObject().apply {
                    put("type", "CLIPBOARD_FILE_ANNOUNCE")
                    put("transfer_id", transferId.toString())
                    put("file_name", file.name)
                    put("mime_type", mimeType)
                    put("size_bytes", fileSize)
                    put("sha256", sha256)
                    put("fingerprint", KeyStoreManager.getPublicKeyFingerprint())
                    put("device_id", controlClient.getLocalDeviceId())
                    put("timestamp", controlClient.getIso8601Timestamp())
                }
                controlClient.sendRawJson(announce)
                Log.i(TAG, "Mengumumkan CLIPBOARD_FILE_ANNOUNCE ke Mac untuk ${file.name} (${fileSize} bytes)...")

                // 2. Connect to Mac Port 54322 and stream binary chunks
                socket = Socket().apply {
                    tcpNoDelay = true
                    sendBufferSize = 2 * 1024 * 1024
                    receiveBufferSize = 2 * 1024 * 1024
                    soTimeout = 30000
                }
                socket.connect(InetSocketAddress(host, DATA_PORT), 6000)
                val out = BufferedOutputStream(socket.getOutputStream(), CHUNK_SIZE)

                val totalChunks = if (fileSize == 0L) 1 else Math.ceil(fileSize.toDouble() / CHUNK_SIZE).toInt()

                FileInputStream(file).use { fis ->
                    val buffer = ByteArray(CHUNK_SIZE)
                    var chunkIdx = 0

                    while (true) {
                        val bytesRead = fis.read(buffer)
                        if (bytesRead <= 0 && chunkIdx > 0) break

                        val currentPayloadLen = maxOf(0, bytesRead)
                        val payloadSlice = if (currentPayloadLen == CHUNK_SIZE) buffer else buffer.copyOf(currentPayloadLen)

                        val mdChunk = MessageDigest.getInstance("SHA-256")
                        val chunkChecksum = mdChunk.digest(payloadSlice)

                        val chunkHeader = buildHeader(
                            msgType = 0x01.toByte(), // CHUNK_DATA
                            transferUuid = transferId,
                            fileIndex = 0,
                            chunkIndex = chunkIdx,
                            totalChunks = totalChunks,
                            payloadLength = currentPayloadLen
                        )

                        out.write(chunkHeader)
                        out.write(payloadSlice)
                        out.write(chunkChecksum)
                        out.flush()

                        chunkIdx++
                        if (bytesRead <= 0) break
                    }
                }

                // 3. Send FILE_COMPLETE (msgType = 0x02)
                val fileCompleteHeader = buildHeader(
                    msgType = 0x02.toByte(),
                    transferUuid = transferId,
                    fileIndex = 0,
                    chunkIndex = 0,
                    totalChunks = totalChunks,
                    payloadLength = 0
                )
                out.write(fileCompleteHeader)
                out.flush()

                // 4. Send TRANSFER_COMPLETE (msgType = 0x03)
                val transferCompleteHeader = buildHeader(
                    msgType = 0x03.toByte(),
                    transferUuid = transferId,
                    fileIndex = 1,
                    chunkIndex = 0,
                    totalChunks = 0,
                    payloadLength = 0
                )
                out.write(transferCompleteHeader)
                out.flush()

                Log.i(TAG, "Clipboard file ${file.name} berhasil distreaming ke Mac!")

            } catch (e: Exception) {
                Log.e(TAG, "Gagal streaming clipboard file ke Mac: ${e.message}", e)
            } finally {
                try { socket?.close() } catch (_: Exception) {}
            }
        }
    }

    /**
     * Send files to Mac on Port 54322, announcing metadata first via ControlSocketClient.
     */
    fun sendFiles(
        files: List<File>,
        host: String,
        controlClient: ControlSocketClient
    ) {
        scope.launch {
            var socket: Socket? = null
            val transferId = UUID.randomUUID()
            try {
                var totalBytes = 0L
                val fileItems = mutableListOf<JSONObject>()

                for (file in files) {
                    if (!file.exists()) continue
                    val fileSize = file.length()
                    totalBytes += fileSize
                    val sha256 = computeFileSha256(file)

                    val item = JSONObject().apply {
                        put("name", file.name)
                        put("relative_path", file.name)
                        put("size_bytes", fileSize)
                        put("sha256", sha256)
                    }
                    fileItems.add(item)
                }

                if (fileItems.isEmpty()) return@launch

                // 1. Announce on Control Channel (Port 54321)
                val metadata = JSONObject().apply {
                    put("type", "FILE_METADATA_HEADER")
                    put("transfer_id", transferId.toString())
                    put("direction", "android_to_mac")
                    put("total_files", fileItems.size)
                    put("total_bytes", totalBytes)
                    put("files", org.json.JSONArray(fileItems))
                }
                // Send JSON over controlClient
                controlClient.sendRawJson(metadata)
                Log.i(TAG, "Mengumumkan FILE_METADATA_HEADER ke Mac...")

                // 2. Connect to Mac Port 54322
                socket = Socket().apply {
                    tcpNoDelay = true
                    sendBufferSize = 2 * 1024 * 1024
                    receiveBufferSize = 2 * 1024 * 1024
                    soTimeout = 30000
                }
                socket.connect(InetSocketAddress(host, DATA_PORT), 6000)
                val out = BufferedOutputStream(socket.getOutputStream(), CHUNK_SIZE)

                var transferredBytesTotal = 0L
                val startTime = System.currentTimeMillis()

                for ((fileIdx, file) in files.withIndex()) {
                    val fileSize = file.length()
                    val totalChunks = if (fileSize == 0L) 1 else Math.ceil(fileSize.toDouble() / CHUNK_SIZE).toInt()

                    FileInputStream(file).use { fis ->
                        val buffer = ByteArray(CHUNK_SIZE)
                        var chunkIdx = 0

                        while (true) {
                            val bytesRead = fis.read(buffer)
                            if (bytesRead <= 0 && chunkIdx > 0) break

                            val payloadLen = if (bytesRead > 0) bytesRead else 0
                            val chunkHeader = buildHeader(
                                msgType = 0x01.toByte(), // CHUNK_DATA
                                transferUuid = transferId,
                                fileIndex = fileIdx,
                                chunkIndex = chunkIdx,
                                totalChunks = totalChunks,
                                payloadLength = payloadLen
                            )

                            val md = MessageDigest.getInstance("SHA-256")
                            if (payloadLen > 0) {
                                md.update(buffer, 0, payloadLen)
                            }
                            val chunkHash = md.digest()

                            out.write(chunkHeader)
                            if (payloadLen > 0) {
                                out.write(buffer, 0, payloadLen)
                            }
                            out.write(chunkHash)
                            out.flush()

                            transferredBytesTotal += payloadLen
                            chunkIdx++

                            val elapsedSeconds = maxOf(0.001, (System.currentTimeMillis() - startTime) / 1000.0)
                            val speedMBs = (transferredBytesTotal / (1024.0 * 1024.0)) / elapsedSeconds
                            val percent = if (totalBytes > 0) ((transferredBytesTotal * 100) / totalBytes).toInt().coerceIn(0, 100) else 0

                            CordaEventBus.postTransferEvent(
                                TransferProgressEvent(
                                    transferId = transferId.toString(),
                                    fileName = file.name,
                                    direction = "outgoing",
                                    fileIndex = fileIdx,
                                    totalFiles = files.size,
                                    progressPercent = percent,
                                    speedMBs = speedMBs,
                                    isCompleted = false
                                )
                            )

                            if (bytesRead <= 0) break
                        }
                    }

                    // Send FILE_COMPLETE frame
                    val fileCompleteHeader = buildHeader(
                        msgType = 0x02.toByte(),
                        transferUuid = transferId,
                        fileIndex = fileIdx,
                        chunkIndex = 0,
                        totalChunks = totalChunks,
                        payloadLength = 0
                    )
                    out.write(fileCompleteHeader)
                    out.flush()
                }

                // Send TRANSFER_COMPLETE frame
                val transferCompleteHeader = buildHeader(
                    msgType = 0x03.toByte(),
                    transferUuid = transferId,
                    fileIndex = 0,
                    chunkIndex = 0,
                    totalChunks = 0,
                    payloadLength = 0
                )
                out.write(transferCompleteHeader)
                out.flush()

                triggerSuccessHaptic()
                CordaEventBus.postTransferEvent(
                    TransferProgressEvent(
                        transferId = transferId.toString(),
                        fileName = "Transfer Selesai",
                        direction = "outgoing",
                        fileIndex = files.size,
                        totalFiles = files.size,
                        progressPercent = 100,
                        speedMBs = 0.0,
                        isCompleted = true
                    )
                )
                Log.i(TAG, "Pengiriman file ke Mac selesai sukses!")
            } catch (e: Exception) {
                Log.e(TAG, "Error saat mengirim file: ${e.message}", e)
                CordaEventBus.postTransferEvent(
                    TransferProgressEvent(
                        transferId = transferId.toString(),
                        fileName = "Transfer Terputus",
                        direction = "outgoing",
                        fileIndex = 0,
                        totalFiles = files.size,
                        progressPercent = 0,
                        speedMBs = 0.0,
                        isCompleted = false
                    )
                )
            } finally {
                try { socket?.close() } catch (_: Exception) {}
            }
        }
    }

    // MARK: - Helpers

    private fun buildHeader(
        msgType: Byte,
        transferUuid: UUID,
        fileIndex: Int,
        chunkIndex: Int,
        totalChunks: Int,
        payloadLength: Int
    ): ByteArray {
        val buffer = ByteBuffer.allocate(40).order(ByteOrder.BIG_ENDIAN)
        buffer.put(MAGIC_BYTES) // 0..3
        buffer.put(0x01.toByte()) // 4: Version 1
        buffer.put(msgType) // 5: Msg Type
        buffer.putShort(0x0000.toShort()) // 6..7: Reserved

        // 8..23: 16-byte UUID
        buffer.putLong(transferUuid.mostSignificantBits)
        buffer.putLong(transferUuid.leastSignificantBits)

        buffer.putInt(fileIndex) // 24..27
        buffer.putInt(chunkIndex) // 28..31
        buffer.putInt(totalChunks) // 32..35
        buffer.putInt(payloadLength) // 36..39

        return buffer.array()
    }

    private fun readFully(inputStream: java.io.InputStream, buffer: ByteArray) {
        var offset = 0
        while (offset < buffer.size) {
            val count = inputStream.read(buffer, offset, buffer.size - offset)
            if (count < 0) {
                throw java.io.EOFException("Premature EOF in binary data stream")
            }
            offset += count
        }
    }

    private fun getDownloadsCordaFolder(): File {
        val publicDownloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val cordaDir = File(publicDownloads, "Corda")
        if (!cordaDir.exists()) {
            cordaDir.mkdirs()
        }
        return if (cordaDir.exists()) cordaDir else File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "Corda").apply { mkdirs() }
    }

    private fun getUniqueDestinationFile(folder: File, fileName: String): File {
        var targetFile = File(folder, fileName)
        if (!targetFile.exists()) return targetFile

        val dotIdx = fileName.lastIndexOf('.')
        val namePart = if (dotIdx > 0) fileName.substring(0, dotIdx) else fileName
        val extPart = if (dotIdx > 0) fileName.substring(dotIdx) else ""

        var counter = 1
        while (targetFile.exists()) {
            targetFile = File(folder, "$namePart ($counter)$extPart")
            counter++
        }
        return targetFile
    }

    private fun copyFile(src: File, dst: File) {
        FileInputStream(src).use { inStream ->
            FileOutputStream(dst).use { outStream ->
                inStream.channel.transferTo(0, inStream.channel.size(), outStream.channel)
            }
        }
    }

    private fun computeFileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { fis ->
            val buf = ByteArray(CHUNK_SIZE)
            var n: Int
            while (fis.read(buf).also { n = it } != -1) {
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun injectFileToClipboard(file: File, sha256: String, mimeTypeHint: String? = null) {
        try {
            val contentUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )

            val mimeType = if (!mimeTypeHint.isNullOrEmpty()) mimeTypeHint else getMimeType(file)
            val clipData = ClipData.newUri(context.contentResolver, file.name, contentUri)

            // Register remote hash to prevent echo loops
            ClipboardAccessibilityService.registerRemoteHash(sha256.lowercase())

            val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            clipboardManager?.setPrimaryClip(clipData)

            triggerTickHaptic()

            val isImage = mimeType.startsWith("image/")
            val label = if (isImage) "🖼️ ${file.name}" else "📁 ${file.name}"

            CordaEventBus.postClipboardEvent(
                ClipboardCopiedEvent(
                    text = label,
                    timestamp = System.currentTimeMillis(),
                    isSensitive = false,
                    sourcePackage = "com.apple.mac"
                )
            )
            Log.i(TAG, "File/Gambar berhasil diinjeksikan ke Android Clipboard: ${file.name} ($contentUri)")
        } catch (e: Exception) {
            Log.e(TAG, "Gagal menginjeksi file ke clipboard: ${e.message}", e)
        }
    }

    private fun getMimeType(file: File): String {
        val ext = file.extension.lowercase()
        return android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    private fun triggerTickHaptic() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                @Suppress("DEPRECATION")
                vibrator?.vibrate(25)
            }
        } catch (_: Exception) {}
    }

    private fun triggerSuccessHaptic() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(
                    VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                @Suppress("DEPRECATION")
                vibrator?.vibrate(50)
            }
        } catch (_: Exception) {}
    }
}
