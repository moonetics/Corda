package com.corda.app.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus

class ClipboardAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "CordaClipboardAcc"
        private var lastProcessedText: String? = null
        private var lastProcessedTime: Long = 0L
        private const val DEDUPLICATION_WINDOW_MS = 600L
    }

    private var clipboardManager: ClipboardManager? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        Log.i(TAG, "Corda ClipboardAccessibilityService connected successfully (Event-Driven Mode).")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        // Listen for interactions likely indicating user copy / selection actions
        if (eventType == AccessibilityEvent.TYPE_VIEW_CLICKED ||
            eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED ||
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED
        ) {
            checkAndProcessClipboard(event.packageName?.toString() ?: "")
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

            val currentTime = System.currentTimeMillis()
            // Deduplicate: avoid firing multiple events for the same text within window
            if (textItem == lastProcessedText && (currentTime - lastProcessedTime) < DEDUPLICATION_WINDOW_MS) {
                return
            }

            lastProcessedText = textItem
            lastProcessedTime = currentTime

            Log.i(TAG, "Aksi salin terdeteksi! Teks (${textItem.length} chars) dari paket: $sourcePackage")
            
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

    override fun onInterrupt() {
        Log.w(TAG, "Corda ClipboardAccessibilityService interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "Corda ClipboardAccessibilityService destroyed.")
    }
}
