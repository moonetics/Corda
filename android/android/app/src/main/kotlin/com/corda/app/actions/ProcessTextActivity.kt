package com.corda.app.actions

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus

/**
 * Handles Android's native text selection floating menu action (android.intent.action.PROCESS_TEXT).
 * Adds "Send to Mac" directly to the floating Cut/Copy/Paste toolbar across all Android apps.
 */
class ProcessTextActivity : Activity() {

    companion object {
        private const val TAG = "CordaProcessText"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val selectedText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        if (!selectedText.isNullOrEmpty()) {
            Log.i(TAG, "ProcessText triggered! Sending ${selectedText.length} chars to Mac...")
            val event = ClipboardCopiedEvent(
                text = selectedText,
                timestamp = System.currentTimeMillis(),
                isSensitive = false,
                sourcePackage = "android.intent.action.PROCESS_TEXT"
            )
            CordaEventBus.postClipboardEvent(event)
            Toast.makeText(this, "Sent to Mac ✨", Toast.LENGTH_SHORT).show()
        }

        finish()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }
}
