package com.corda.app.overlay

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus
import com.corda.app.services.CordaForegroundService
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * OverlayClipboardReader provides 100% invisible, instantaneous background clipboard extraction
 * by temporarily adding a 1x1 pixel view to WindowManager (TYPE_APPLICATION_OVERLAY).
 *
 * This obtains Window Focus (< 15ms) which cleanly unblocks Android 10+ (API 29–34+)
 * ClipboardManager restrictions without launching an Activity or interrupting the user.
 */
object OverlayClipboardReader {
    private const val TAG = "CordaOverlayReader"
    private val isReading = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var lastProcessedText: String? = null
    private var lastProcessedTime: Long = 0L
    private const val DEDUPLICATION_WINDOW_MS = 800L

    fun canReadOverlay(context: Context): Boolean {
        return Settings.canDrawOverlays(context)
    }

    /**
     * Reads the system clipboard using 1x1 WindowManager focus and transmits to Mac.
     */
    fun readAndEmit(context: Context, sourcePackage: String = "android.system.clipboard") {
        if (!canReadOverlay(context)) {
            Log.w(TAG, "Tidak dapat membaca clipboard via overlay: Izin SYSTEM_ALERT_WINDOW (Appear on top) belum diberikan!")
            return
        }

        if (isReading.getAndSet(true)) {
            Log.d(TAG, "Pembacaan overlay sedang berlangsung, melewati panggilan duplikat.")
            return
        }

        mainHandler.post {
            var overlayView: View? = null
            var windowManager: WindowManager? = null

            try {
                windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                if (windowManager == null) {
                    isReading.set(false)
                    return@post
                }

                val view = View(context).apply {
                    isFocusable = true
                    isFocusableInTouchMode = true
                }
                overlayView = view

                val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                // Window layout: 1x1 pixel, transparent, NOT_TOUCH_MODAL allows outside touches.
                val params = WindowManager.LayoutParams(
                    1, 1,
                    overlayType,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.START or Gravity.TOP
                    x = 0
                    y = 0
                    alpha = 0.0f
                    title = "CordaClipboardOverlay"
                }

                windowManager.addView(view, params)
                view.requestFocus()

                // Execute read after focus attachment (15ms is optimal across Android 10-14)
                mainHandler.postDelayed({
                    try {
                        readClipboardAndCleanUp(context, view, windowManager, sourcePackage)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error saat delayed read pada overlay", e)
                        safeRemoveView(windowManager, view)
                        isReading.set(false)
                    }
                }, 15L)

            } catch (e: Exception) {
                Log.e(TAG, "Gagal menambahkan 1x1 overlay view ke WindowManager", e)
                if (overlayView != null && windowManager != null) {
                    safeRemoveView(windowManager, overlayView)
                }
                isReading.set(false)
            }
        }
    }

    private fun readClipboardAndCleanUp(
        context: Context,
        view: View,
        windowManager: WindowManager,
        sourcePackage: String
    ) {
        try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            if (clipboard != null && clipboard.hasPrimaryClip()) {
                val description = clipboard.primaryClipDescription
                val clipData = clipboard.primaryClip
                if (clipData != null && clipData.itemCount > 0) {
                    val text = clipData.getItemAt(0)?.coerceToText(context)?.toString()
                    if (!text.isNullOrEmpty()) {
                        processExtractedText(context, text, sourcePackage)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Gagal mengekstrak primaryClip pada overlay window focus", e)
        } finally {
            safeRemoveView(windowManager, view)
            isReading.set(false)
        }
    }

    private fun processExtractedText(context: Context, text: String, sourcePackage: String) {
        val textHash = computeSha256(text).lowercase()
        if (ClipboardAccessibilityService.isRemoteHash(textHash)) {
            Log.d(TAG, "Teks clipboard berasal dari Mac remote hash. Mengabaikan echo.")
            ClipboardAccessibilityService.recentRemoteHashes.remove(textHash)
            return
        }

        val currentTime = System.currentTimeMillis()
        if (text == lastProcessedText && (currentTime - lastProcessedTime) < DEDUPLICATION_WINDOW_MS) {
            return
        }

        lastProcessedText = text
        lastProcessedTime = currentTime

        Log.i(TAG, "Overlay berhasil mengekstrak teks (${text.length} chars) di background! Mengirim ke Mac...")
        triggerHapticFeedback(context)

        val event = ClipboardCopiedEvent(
            text = text,
            timestamp = currentTime,
            isSensitive = false,
            sourcePackage = sourcePackage
        )
        CordaEventBus.postClipboardEvent(event)

        // Directly broadcast to Mac socket if ForegroundService is running
        CordaForegroundService.instance?.socketClient?.sendClipboard(text, textHash)
    }

    private fun safeRemoveView(windowManager: WindowManager, view: View) {
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: Exception) {
            try {
                windowManager.removeView(view)
            } catch (_: Exception) {}
        }
    }

    private fun triggerHapticFeedback(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(15, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(15)
                }
            }
        } catch (_: Exception) {}
    }

    fun computeSha256(text: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
