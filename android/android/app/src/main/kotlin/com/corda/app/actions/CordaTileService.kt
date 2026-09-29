package com.corda.app.actions

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.widget.Toast
import androidx.annotation.RequiresApi
import com.corda.app.accessibility.ClipboardAccessibilityService
import com.corda.app.events.ClipboardCopiedEvent
import com.corda.app.events.CordaEventBus

/**
 * Android Quick Settings Tile for Corda.
 * Allows user to pull down status bar and tap "Corda Sync" to immediately push
 * the current system clipboard to Mac.
 */
@RequiresApi(Build.VERSION_CODES.N)
class CordaTileService : TileService() {

    companion object {
        private const val TAG = "CordaTileService"
    }

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_ACTIVE
            label = "Corda Sync"
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        Log.i(TAG, "Quick Settings Tile tapped. Syncing clipboard to Mac...")

        try {
            val manager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val clip = manager?.primaryClip
            val text = if (clip != null && clip.itemCount > 0) {
                clip.getItemAt(0)?.coerceToText(this)?.toString()
            } else null

            if (!text.isNullOrEmpty()) {
                val event = ClipboardCopiedEvent(
                    text = text,
                    timestamp = System.currentTimeMillis(),
                    isSensitive = false,
                    sourcePackage = "com.corda.quicksettings"
                )
                CordaEventBus.postClipboardEvent(event)
                Toast.makeText(this, "Clipboard synced to Mac ✨", Toast.LENGTH_SHORT).show()
            } else {
                // If null due to background restriction, launch transparent reader
                val intent = Intent(this, TransparentClipboardReaderActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
                }
                startActivity(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in TileService", e)
        }
    }
}
