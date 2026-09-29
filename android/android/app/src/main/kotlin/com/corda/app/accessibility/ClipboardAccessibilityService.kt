package com.corda.app.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.util.Collections

class ClipboardAccessibilityService : AccessibilityService(), ClipboardManager.OnPrimaryClipChangedListener {

    companion object {
        private const val TAG = "CordaClipboardAcc"
        private var lastProcessedText: String? = null
        private var lastProcessedTime: Long = 0L
        private const val DEDUPLICATION_WINDOW_MS = 600L

        private val recentRemoteHashes = Collections.synchronizedSet(mutableSetOf<String>())

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

        fun computeSha256(text: String): String {
            val md = MessageDigest.getInstance("SHA-256")
            val digest = md.digest(text.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }
    }

    private var clipboardManager: ClipboardManager? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onServiceConnected() {
        super.onServiceConnected()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(this)
        Log.i(TAG, "Corda ClipboardAccessibilityService connected with OnPrimaryClipChangedListener active.")
    }

    override fun onPrimaryClipChanged() {
        Log.d(TAG, "onPrimaryClipChanged terdeteksi oleh sistem.")
        checkAndProcessClipboard("system_clipboard_listener")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        val pkg = event.packageName?.toString() ?: ""

        // Listen for interactions likely indicating user copy / selection actions
        if (eventType == AccessibilityEvent.TYPE_VIEW_CLICKED ||
            eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED ||
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_VIEW_TEXT_TRAVERSED_AT_MOVEMENT_GRANULARITY
        ) {
            checkAndProcessClipboard(pkg)
            
            // Asynchronous delayed checks: third-party apps (Chrome, WhatsApp, Notes)
            // write to the clipboard asynchronously after the click/selection event.
            serviceScope.launch {
                delay(120L)
                checkAndProcessClipboard(pkg)
                delay(200L)
                checkAndProcessClipboard(pkg)
            }
        }
    }

    private fun checkAndProcessClipboard(sourcePackage: String) {
        val manager = clipboardManager ?: (getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.also {
            clipboardManager = it
        } ?: return

        try {
            if (!manager.hasPrimaryClip()) return

            val description = manager.primaryClipDescription ?: return

            // Verify if mime type is plain text or html
            val isText = description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) ||
                    description.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML)

            if (!isText) return

            // Sensitive data filtering (Android 13+ / API 33+ flag EXTRA_IS_SENSITIVE)
            val isSensitive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true
            } else {
                false
            }

            if (isSensitive) {
                Log.w(TAG, "Sensitif terdeteksi (EXTRA_IS_SENSITIVE = true). Teks clipboard diabaikan demi privasi pengguna.")
                return
            }

            val clipData = manager.primaryClip ?: return
            if (clipData.itemCount <= 0) return

            val textItem = clipData.getItemAt(0)?.coerceToText(this)?.toString()
            if (textItem.isNullOrEmpty()) return

            val textHash = computeSha256(textItem).lowercase()
            if (recentRemoteHashes.contains(textHash)) {
                Log.d(TAG, "Teks clipboard berasal dari remote sync (hash cocok). Mengabaikan untuk mencegah echo loop.")
                recentRemoteHashes.remove(textHash)
                return
            }

            val currentTime = System.currentTimeMillis()
            // Deduplicate: avoid firing multiple events for the same text within window
            if (textItem == lastProcessedText && (currentTime - lastProcessedTime) < DEDUPLICATION_WINDOW_MS) {
                return
            }

            lastProcessedText = textItem
            lastProcessedTime = currentTime

            Log.i(TAG, "Aksi salin terdeteksi! Teks (${textItem.length} chars) dari paket: $sourcePackage")
            triggerHapticFeedback()
            
            // Post event to CordaEventBus for CordaForegroundService and Flutter Layer
            val event = ClipboardCopiedEvent(
                text = textItem,
                timestamp = currentTime,
                isSensitive = false,
                sourcePackage = sourcePackage
            )
            CordaEventBus.postClipboardEvent(event)

        } catch (e: Exception) {
            Log.e(TAG, "Error checking clipboard in AccessibilityService", e)
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

