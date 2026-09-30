package com.corda.app.notifications

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.corda.app.services.CordaForegroundService

/**
 * Standard Android NotificationListenerService to capture alerts from all apps
 * and forward them to macOS via the Corda secure local Wi-Fi control channel.
 */
class CordaNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "CordaNotifListener"
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "CordaNotificationListenerService connected and active.")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "CordaNotificationListenerService disconnected.")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val sbn = sbn ?: return
        val pkg = sbn.packageName ?: return

        // 1. Ignore notifications from Corda itself
        if (pkg == packageName) return

        val notification = sbn.notification ?: return

        // 2. Check if package is allowed by user's Apple Continuity settings
        if (!NotificationMirrorEngine.isPackageAllowed(this, pkg)) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            ?: ""

        // If both title and text are empty, skip
        if (title.isEmpty() && text.isEmpty()) return

        // 3. Check deduplication
        if (NotificationMirrorEngine.shouldEmitNotification(pkg, title, text)) {
            val appName = NotificationMirrorEngine.getAppNameForPackage(this, pkg)
            val notifId = "${pkg}_${sbn.id}_${sbn.postTime}"

            Log.i(TAG, "Mirroring notification to Mac: [$appName] $title")
            CordaForegroundService.instance?.socketClient?.sendNotificationMirror(
                notificationId = notifId,
                packageName = pkg,
                appName = appName,
                title = title,
                text = text
            )
        }
    }
}
