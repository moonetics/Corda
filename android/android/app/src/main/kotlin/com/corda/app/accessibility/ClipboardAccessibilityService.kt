package com.corda.app.accessibility

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.corda.app.actions.TransparentClipboardReaderActivity
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus
import com.corda.app.events.OtpDetectedEvent
import com.corda.app.otp.OtpDetector
import com.corda.app.notifications.NotificationMirrorEngine
import android.net.Uri
import android.provider.OpenableColumns
import com.corda.app.services.CordaForegroundService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Collections

class ClipboardAccessibilityService : AccessibilityService(), ClipboardManager.OnPrimaryClipChangedListener {

    companion object {
        private const val TAG = "CordaClipboardAcc"
        private var lastProcessedText: String? = null
        private var lastProcessedFileHash: String? = null
        private var lastProcessedTime: Long = 0L
        private const val DEDUPLICATION_WINDOW_MS = 800L

        val recentRemoteHashes = Collections.synchronizedSet(mutableSetOf<String>())

        /**
         * Register a hash received from the remote Mac so it won't echo back.
         */
        fun registerRemoteHash(hash: String) {
            recentRemoteHashes.add(hash.lowercase())
            if (recentRemoteHashes.size > 50) {
                val first = recentRemoteHashes.firstOrNull()
                if (first != null) recentRemoteHashes.remove(first)
            }
        }

        fun isRemoteHash(hash: String): Boolean {
            return recentRemoteHashes.contains(hash.lowercase())
        }

        fun computeSha256(text: String): String {
            val md = MessageDigest.getInstance("SHA-256")
            val digest = md.digest(text.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        fun computeFileSha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { fis ->
                val buf = ByteArray(65536)
                var n: Int
                while (fis.read(buf).also { n = it } != -1) {
                    digest.update(buf, 0, n)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }

        fun triggerHapticFeedback(context: Context) {
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

        fun processClipboardUri(context: Context, uri: Uri, description: ClipDescription?, sourcePackage: String): Boolean {
            try {
                val mimeType = context.contentResolver.getType(uri)
                    ?: (if (description != null && description.mimeTypeCount > 0) description.getMimeType(0) else null)
                    ?: "application/octet-stream"

                var fileName = "clipboard_file"
                var fileSize = -1L

                try {
                    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIdx != -1) {
                                val n = cursor.getString(nameIdx)
                                if (!n.isNullOrEmpty()) fileName = n
                            }
                            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeIdx != -1) {
                                fileSize = cursor.getLong(sizeIdx)
                            }
                        }
                    }
                } catch (_: Exception) {}

                // Cap at 50MB
                if (fileSize > 52428800L) {
                    Log.w(TAG, "File di clipboard melebihi 50MB ($fileSize bytes). Dilewati.")
                    return false
                }

                val tempDir = File(context.cacheDir, "clipboard_out").apply { mkdirs() }
                val ext = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "bin"
                val safeFileName = if (fileName.contains(".")) fileName else "$fileName.$ext"
                val tempFile = File(tempDir, safeFileName)

                context.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(tempFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: return false

                val actualSize = tempFile.length()
                if (actualSize <= 0 || actualSize > 52428800L) {
                    tempFile.delete()
                    return false
                }

                val sha256 = computeFileSha256(tempFile).lowercase()
                if (recentRemoteHashes.contains(sha256)) {
                    Log.d(TAG, "File clipboard berasal dari remote sync. Mengabaikan echo.")
                    recentRemoteHashes.remove(sha256)
                    tempFile.delete()
                    return false
                }

                val currentTime = System.currentTimeMillis()
                if (sha256 == lastProcessedFileHash && (currentTime - lastProcessedTime) < DEDUPLICATION_WINDOW_MS) {
                    tempFile.delete()
                    return false
                }

                lastProcessedFileHash = sha256
                lastProcessedTime = currentTime

                triggerHapticFeedback(context)

                val isImage = mimeType.startsWith("image/")
                val label = "[File: $safeFileName]"

                try {
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        android.widget.Toast.makeText(
                            context,
                            if (isImage) "Copying image to Mac..." else "Copying file to Mac...",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                } catch (_: Exception) {}

                CordaEventBus.postClipboardEvent(
                    ClipboardCopiedEvent(
                        text = label,
                        timestamp = System.currentTimeMillis(),
                        isSensitive = false,
                        sourcePackage = sourcePackage
                    )
                )

                CordaForegroundService.instance?.socketClient?.sendClipboardFile(tempFile, mimeType, sha256)
                Log.i(TAG, "File/Gambar clipboard Android ($safeFileName, $actualSize bytes) berhasil dikirim ke Mac!")
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Gagal memproses URI clipboard", e)
                return false
            }
        }
    }

    private var clipboardManager: ClipboardManager? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var lastSelectedText: String? = null
    private var lastSelectionTime: Long = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(this)
        Log.i(TAG, "Corda ClipboardAccessibilityService connected with OnPrimaryClipChangedListener active.")
    }

    override fun onPrimaryClipChanged() {
        Log.d(TAG, "onPrimaryClipChanged terdeteksi oleh sistem.")

        // 1. Fast-Path: If text was recently selected in UI (< 3000ms), emit immediately
        val candidate = lastSelectedText
        val now = System.currentTimeMillis()
        if (!candidate.isNullOrEmpty() && (now - lastSelectionTime) < 3000L) {
            Log.i(TAG, "Fast-path: Memancarkan lastSelectedText (${candidate.length} chars) ke Mac...")
            emitClipboardText(candidate, "android.ui.fastpath")
        }

        // 2. Definitive Path: Launch zero-animation TransparentActivity which waits for onWindowFocusChanged(true)
        launchTransparentReader()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        val pkg = event.packageName?.toString() ?: ""

        // 1. Sniff text selection changes directly from UI nodes
        if (eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED) {
            captureSelectionFromEvent(event)
            return
        }

        // 2. Toast / Notification state changed ("Berhasil disalin", "Tersalin ke clipboard", or Smart OTP)
        if (eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val textList = event.text.map { it.toString() }
            val joined = textList.joinToString(" ")
            Log.d(TAG, "Notification/Toast detected: '$joined'")

            // A. Smart OTP Detection
            val parcelable = event.parcelableData
            var title: String? = null
            var notificationContent = joined
            if (parcelable is Notification) {
                title = parcelable.extras?.getString(Notification.EXTRA_TITLE)
                val textChar = parcelable.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                val bigTextChar = parcelable.extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                notificationContent = listOfNotNull(joined, textChar, bigTextChar).filter { it.isNotBlank() }.joinToString(" ")
            }

            val otpMatch = OtpDetector.detectOtp(
                text = notificationContent,
                title = title,
                packageName = pkg
            )

            if (otpMatch != null) {
                Log.i(TAG, "🔑 Smart OTP Terdeteksi di Accessibility: [${otpMatch.code}] dari '${otpMatch.serviceName}'! Mengirim ke Mac...")
                CordaEventBus.postOtpDetected(
                    OtpDetectedEvent(
                        serviceName = otpMatch.serviceName,
                        code = otpMatch.code,
                        expiresIn = otpMatch.expiresIn
                    )
                )
                CordaForegroundService.instance?.socketClient?.sendOtpDetected(
                    serviceName = otpMatch.serviceName,
                    code = otpMatch.code,
                    expiresIn = otpMatch.expiresIn
                )
                // Privacy: Do not proceed further with raw text
                return
            }

            // B. Whitelisted Notification Mirroring (Source-Side Filter)
            if (parcelable is Notification && NotificationMirrorEngine.isPackageAllowed(this, pkg)) {
                val notifTitle = title ?: ""
                val textChar = parcelable.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                val bigTextChar = parcelable.extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                val notifText = (bigTextChar ?: textChar ?: joined).trim()

                // Skip blank notifications
                if (notifTitle.isNotBlank() || notifText.isNotBlank()) {
                    if (NotificationMirrorEngine.shouldEmitNotification(pkg, notifTitle, notifText)) {
                        val appName = NotificationMirrorEngine.getAppNameForPackage(this, pkg)
                        val notificationId = "${pkg}_${System.currentTimeMillis()}"
                        Log.i(TAG, "🔔 Notifikasi Whitelist Terdeteksi: [$appName] '$notifTitle' -> Mengirim ke Mac...")
                        CordaForegroundService.instance?.socketClient?.sendNotificationMirror(
                            notificationId = notificationId,
                            packageName = pkg,
                            appName = appName,
                            title = notifTitle,
                            text = notifText
                        )
                    }
                }
            }

            // C. Toast copy confirmation detection
            val lowerJoined = joined.lowercase()
            val copyKeywords = listOf(
                "salin", "copy", "tersalin", "disalin", "clipboard", "klip",
                "papan klip", "copied", "berhasil disalin", "berhasil", "copied to clipboard"
            )
            if (copyKeywords.any { lowerJoined.contains(it) }) {
                Log.i(TAG, "Toast konfirmasi salin terdeteksi ('$lowerJoined')! Meluncurkan transparent reader...")
                launchTransparentReader()
                return
            }
        }

        // 3. In-App snackbar or window content change with copy confirmation
        if (eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED || eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (event.text.isNotEmpty()) {
                val joined = event.text.joinToString(" ").lowercase()
                if (joined.contains("berhasil disalin") || joined.contains("disalin ke") ||
                    joined.contains("tersalin ke") || joined.contains("copied to") ||
                    joined.contains("link copied") || joined.contains("tautan disalin")
                ) {
                    Log.i(TAG, "In-app snackbar copy terdeteksi ('$joined')! Meluncurkan transparent reader...")
                    launchTransparentReader()
                    return
                }
            }
        }

        // 4. Detect when user clicks "Copy" / "Salin" in context toolbar, keyboard, or in-app icon
        if (eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            if (isCopyOrCutAction(event)) {
                Log.i(TAG, "User tapped Copy/Salin button! Propagating selected text...")
                val candidateText = lastSelectedText
                if (!candidateText.isNullOrEmpty() && (System.currentTimeMillis() - lastSelectionTime) < 30000L) {
                    emitClipboardText(candidateText, pkg.ifEmpty { "android.ui.selection" })
                }
                serviceScope.launch {
                    delay(50L)
                    launchTransparentReader()
                }
                return
            }

            // Fallback for custom in-app copy icons (e.g. Seakun email/password rows)
            val source = event.source
            if (source != null) {
                val adjacent = extractAdjacentCopyText(source)
                if (!adjacent.isNullOrEmpty()) {
                    Log.i(TAG, "Teks terdeteksi di samping tombol salin: '$adjacent'. Memancarkan & meluncurkan reader...")
                    emitClipboardText(adjacent, pkg.ifEmpty { "android.ui.adjacent" })
                    serviceScope.launch {
                        delay(60L)
                        launchTransparentReader()
                    }
                    return
                }
            }
        }
    }

    private fun captureSelectionFromEvent(event: AccessibilityEvent) {
        try {
            val source = event.source
            if (source != null) {
                val fullText = source.text?.toString()
                val start = source.textSelectionStart.takeIf { it >= 0 } ?: event.fromIndex
                val end = source.textSelectionEnd.takeIf { it >= 0 } ?: event.toIndex

                if (fullText != null && start >= 0 && end > start && end <= fullText.length) {
                    lastSelectedText = fullText.substring(start, end)
                    lastSelectionTime = System.currentTimeMillis()
                    Log.d(TAG, "Cached selected text (${lastSelectedText?.length} chars): '${lastSelectedText?.take(20)}...'")
                    return
                }
            }

            // Fallback: check event text list
            if (event.text.isNotEmpty()) {
                val joined = event.text.joinToString("")
                val from = event.fromIndex
                val to = event.toIndex
                if (from >= 0 && to > from && to <= joined.length) {
                    lastSelectedText = joined.substring(from, to)
                    lastSelectionTime = System.currentTimeMillis()
                    Log.d(TAG, "Cached selected text from event text (${lastSelectedText?.length} chars)")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing selection from event", e)
        }
    }

    private fun isCopyOrCutAction(event: AccessibilityEvent): Boolean {
        try {
            val pkg = (event.packageName?.toString() ?: "").lowercase()
            val eventDesc = (event.contentDescription?.toString() ?: "").lowercase()
            val eventText = event.text.joinToString(" ").lowercase()

            val source = event.source
            val sourceText = (source?.text?.toString() ?: "").lowercase()
            val sourceDesc = (source?.contentDescription?.toString() ?: "").lowercase()
            val resId = (source?.viewIdResourceName ?: "").lowercase()

            val combined = "$eventDesc $eventText $sourceText $sourceDesc"
            val keywords = listOf("copy", "salin", "copier", "kopi", "cut", "potong", "tautan", "link", "url", "code", "kode", "clip", "klip")

            if (keywords.any { combined.contains(it) } || 
                resId.contains("copy") || resId.contains("cut") || 
                resId.contains("link") || resId.contains("tautan") || 
                resId.contains("clip") || resId.contains("share")
            ) {
                return true
            }

            // Keyboard/IME toolbar detection (Gboard, Samsung Keyboard, SwiftKey)
            val isKeyboard = pkg.contains("inputmethod") || pkg.contains("gboard") ||
                    pkg.contains("touchtype") || pkg.contains("keyboard") || pkg.contains("samsung")
            if (isKeyboard) {
                if (combined.contains("clip") || combined.contains("klip") ||
                    combined.contains("action") || resId.contains("action") || resId.contains("edit")
                ) {
                    return true
                }
            }

            return false
        } catch (_: Exception) {
            return false
        }
    }

    private fun checkAndProcessClipboard(sourcePackage: String): Boolean {
        val manager = clipboardManager ?: (getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.also {
            clipboardManager = it
        } ?: return false

        try {
            if (!manager.hasPrimaryClip()) return false

            val description = manager.primaryClipDescription ?: return false
            val clipData = manager.primaryClip ?: return false
            if (clipData.itemCount <= 0) return false

            val firstItem = clipData.getItemAt(0)

            // 1. Check for File / Image URI clip (<= 50MB)
            val uri = firstItem?.uri
            if (uri != null) {
                return processClipboardUri(this, uri, description, sourcePackage)
            }

            // 2. Universal text/plain & HTML sync
            val isText = description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) ||
                    description.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML)

            if (!isText) return false

            val textItem = firstItem?.coerceToText(this)?.toString()
            if (textItem.isNullOrEmpty()) return false

            return emitClipboardText(textItem, sourcePackage)

        } catch (e: Exception) {
            Log.e(TAG, "Error checking clipboard in AccessibilityService", e)
            return false
        }
    }

    private fun emitClipboardText(text: String, sourcePackage: String): Boolean {
        val textHash = computeSha256(text).lowercase()
        if (recentRemoteHashes.contains(textHash)) {
            Log.d(TAG, "Teks clipboard berasal dari remote sync. Mengabaikan untuk cegah echo loop.")
            recentRemoteHashes.remove(textHash)
            return false
        }

        val currentTime = System.currentTimeMillis()
        if (text == lastProcessedText && (currentTime - lastProcessedTime) < DEDUPLICATION_WINDOW_MS) {
            return false
        }

        lastProcessedText = text
        lastProcessedTime = currentTime

        Log.i(TAG, "Aksi salin terdeteksi! Teks (${text.length} chars) dari paket: $sourcePackage")
        triggerHapticFeedback()

        val event = ClipboardCopiedEvent(
            text = text,
            timestamp = currentTime,
            isSensitive = false,
            sourcePackage = sourcePackage
        )
        CordaEventBus.postClipboardEvent(event)
        return true
    }

    private fun extractAdjacentCopyText(source: AccessibilityNodeInfo): String? {
        try {
            // 1. Direct text on clicked view itself
            val selfText = source.text?.toString()?.trim()
            if (!selfText.isNullOrEmpty()) {
                val clean = cleanFieldLabel(selfText)
                if (clean.isNotEmpty()) return clean
            }

            // 2. Siblings in parent container (e.g. Email row with copy button)
            val parent = source.parent ?: return null
            for (i in 0 until parent.childCount) {
                val child = parent.getChild(i) ?: continue
                if (child == source) continue

                val text = child.text?.toString()?.trim()
                if (!text.isNullOrEmpty()) {
                    val clean = cleanFieldLabel(text)
                    if (clean.isNotEmpty()) return clean
                }

                // Search 1 level deeper in child containers
                for (j in 0 until child.childCount) {
                    val subChild = child.getChild(j) ?: continue
                    val subText = subChild.text?.toString()?.trim()
                    if (!subText.isNullOrEmpty()) {
                        val clean = cleanFieldLabel(subText)
                        if (clean.isNotEmpty()) return clean
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun cleanFieldLabel(raw: String): String {
        val lower = raw.lowercase()
        val prefixes = listOf(
            "email:", "email :", "password:", "password :", "kata sandi:",
            "sandi:", "akun:", "username:", "pin:", "kode:", "link:", "url:",
            "nomor:", "no:", "token:"
        )
        for (p in prefixes) {
            if (lower.startsWith(p)) {
                val extracted = raw.substring(p.length).trim()
                if (extracted.isNotEmpty()) return extracted
            }
        }
        if (raw.contains("@") || raw.startsWith("http://") || raw.startsWith("https://")) {
            return raw
        }
        return ""
    }

    private fun launchTransparentReader() {
        try {
            val intent = Intent(this, TransparentClipboardReaderActivity::class.java).apply {
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

            try {
                // Direct activity start from AccessibilityService (BAL-exempt)
                startActivity(intent, options.toBundle())
            } catch (_: Exception) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    this,
                    1001,
                    intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0),
                    options.toBundle()
                )
                pendingIntent.send()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gagal meluncurkan TransparentClipboardReaderActivity: ${e.message}")
        }
    }

    private fun triggerHapticFeedback() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(15, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(15)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onInterrupt() {
        Log.w(TAG, "Corda ClipboardAccessibilityService interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        clipboardManager?.removePrimaryClipChangedListener(this)
        serviceScope.cancel()
        Log.i(TAG, "Corda ClipboardAccessibilityService destroyed.")
    }
}
