package com.corda.app.actions

import android.app.Activity
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus
import com.corda.app.services.CordaForegroundService
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A zero-animation, 1x1 pixel transparent activity that briefly runs in the foreground
 * to obtain system window focus and read the Android ClipboardManager without restriction.
 * Reads clipboard on onWindowFocusChanged(true) and finishes immediately with 0 visual disruption.
 */
class TransparentClipboardReaderActivity : Activity() {

    companion object {
        private const val TAG = "CordaTransActivity"
    }

    private val isHandled = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Make window 1x1, completely transparent and positioned offscreen
        window?.apply {
            setLayout(1, 1)
            setGravity(Gravity.TOP or Gravity.START)
            setBackgroundDrawableResource(android.R.color.transparent)
            addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            )
        }
    }

    override fun onResume() {
        super.onResume()
        // Fallback: If onWindowFocusChanged is delayed, attempt read after 50ms and close
        mainHandler.postDelayed({
            if (!isHandled.get()) {
                readAndSyncClipboard()
                finishImmediately()
            }
        }, 50L)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d(TAG, "TransparentActivity onWindowFocusChanged: hasFocus=$hasFocus")
        if (hasFocus) {
            readAndSyncClipboard()
            finishImmediately()
        }
    }

    private fun readAndSyncClipboard() {
        if (isHandled.getAndSet(true)) return

        try {
            val manager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
            if (!manager.hasPrimaryClip()) return

            val description = manager.primaryClipDescription ?: return
            val clipData = manager.primaryClip ?: return
            if (clipData.itemCount <= 0) return

            val firstItem = clipData.getItemAt(0)
            val uri = firstItem?.uri
            if (uri != null) {
                ClipboardAccessibilityService.processClipboardUri(this, uri, description, "android.system.clipboard")
                return
            }

            val isText = description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) ||
                    description.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML)
            if (!isText) return

            val textItem = firstItem?.coerceToText(this)?.toString()
            if (textItem.isNullOrEmpty()) return

            val textHash = ClipboardAccessibilityService.computeSha256(textItem).lowercase()
            if (ClipboardAccessibilityService.recentRemoteHashes.contains(textHash)) {
                return
            }

            Log.i(TAG, "Transparent reader successfully captured clipboard: ${textItem.length} chars. Broadcasting to Mac...")
            triggerHapticFeedback()

            val event = ClipboardCopiedEvent(
                text = textItem,
                timestamp = System.currentTimeMillis(),
                isSensitive = false,
                sourcePackage = "android.system.clipboard"
            )
            CordaEventBus.postClipboardEvent(event)

            // Direct TLS socket dispatch to Mac
            CordaForegroundService.instance?.socketClient?.sendClipboard(textItem, textHash)

        } catch (e: Exception) {
            Log.e(TAG, "Error in TransparentClipboardReaderActivity", e)
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

    private fun finishImmediately() {
        finish()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }
}
