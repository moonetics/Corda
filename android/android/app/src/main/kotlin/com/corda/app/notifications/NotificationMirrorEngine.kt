package com.corda.app.notifications

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.LinkedHashMap

data class NotificationAppInfo(
    val packageName: String,
    val appName: String,
    val isEnabled: Boolean = true
)

/**
 * Engine for managing notification whitelist and source-side filtering in Corda.
 * Supports universal user-selected apps (empty by default).
 * Ensures notifications are only captured and sent over the local TLS channel
 * for user-approved apps, preserving smartphone battery and Wi-Fi socket bandwidth.
 */
object NotificationMirrorEngine {
    private const val TAG = "NotificationMirror"
    private const val PREFS_NAME = "corda_notification_whitelist_prefs"
    private const val KEY_MASTER_ENABLED = "notification_mirroring_master_enabled"
    private const val KEY_WHITELIST_JSON = "notification_whitelist_apps_json"
    private const val KEY_PREFIX_PKG = "pkg_allowed_"

    // Deduplication LRU cache: maps notification signature to last emission timestamp
    private val deduplicationCache = object : LinkedHashMap<String, Long>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean {
            return size > 50
        }
    }
    private const val DEDUPLICATION_WINDOW_MS = 5000L

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Check if master notification mirroring toggle is enabled.
     */
    fun isMasterEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_MASTER_ENABLED, true)
    }

    /**
     * Update master notification mirroring toggle.
     */
    fun setMasterEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_MASTER_ENABLED, enabled).apply()
        Log.i(TAG, "Master Notification Mirroring set to: $enabled")
    }

    /**
     * Returns the list of whitelisted apps configured by the user.
     * Empty by default until user adds apps.
     */
    fun getWhitelistedApps(context: Context): List<Map<String, Any>> {
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(KEY_WHITELIST_JSON, null) ?: return emptyList()
        val list = mutableListOf<Map<String, Any>>()
        try {
            val jsonArray = JSONArray(jsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val pkg = obj.optString("packageName")
                if (pkg.isNotEmpty()) {
                    val appName = obj.optString("appName", pkg)
                    val key = KEY_PREFIX_PKG + pkg
                    val isEnabled = if (prefs.contains(key)) prefs.getBoolean(key, true) else obj.optBoolean("isEnabled", true)
                    list.add(
                        mapOf(
                            "packageName" to pkg,
                            "appName" to appName,
                            "isEnabled" to isEnabled
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse whitelist JSON: ${e.message}")
        }
        return list
    }

    /**
     * Add a package to the user's whitelist.
     */
    fun addWhitelistedApp(context: Context, packageName: String, appName: String) {
        val current = getWhitelistedApps(context).toMutableList()
        if (current.none { it["packageName"] == packageName }) {
            current.add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "isEnabled" to true
                )
            )
            saveWhitelistedApps(context, current)
            setPackageAllowed(context, packageName, true)
            Log.i(TAG, "Added app to whitelist: $packageName ($appName)")
        }
    }

    /**
     * Remove a package from the user's whitelist.
     */
    fun removeWhitelistedApp(context: Context, packageName: String) {
        val current = getWhitelistedApps(context).filter { it["packageName"] != packageName }
        saveWhitelistedApps(context, current)
        val prefs = getPrefs(context)
        prefs.edit().remove(KEY_PREFIX_PKG + packageName).apply()
        Log.i(TAG, "Removed app from whitelist: $packageName")
    }

    private fun saveWhitelistedApps(context: Context, list: List<Map<String, Any>>) {
        val jsonArray = JSONArray()
        for (item in list) {
            val obj = JSONObject()
            obj.put("packageName", item["packageName"])
            obj.put("appName", item["appName"])
            obj.put("isEnabled", item["isEnabled"])
            jsonArray.put(obj)
        }
        getPrefs(context).edit().putString(KEY_WHITELIST_JSON, jsonArray.toString()).apply()
    }

    /**
     * Check if a specific package is whitelisted and mirroring is enabled.
     */
    fun isPackageAllowed(context: Context, packageName: String): Boolean {
        if (!isMasterEnabled(context)) return false
        val apps = getWhitelistedApps(context)
        val app = apps.firstOrNull { it["packageName"] == packageName } ?: return false
        val key = KEY_PREFIX_PKG + packageName
        val prefs = getPrefs(context)
        return if (prefs.contains(key)) prefs.getBoolean(key, true) else (app["isEnabled"] as? Boolean ?: true)
    }

    /**
     * Set allowed state for a specific package.
     */
    fun setPackageAllowed(context: Context, packageName: String, allowed: Boolean) {
        val prefs = getPrefs(context)
        prefs.edit().putBoolean(KEY_PREFIX_PKG + packageName, allowed).apply()
        Log.i(TAG, "Notification package '$packageName' allowed set to: $allowed")
    }

    /**
     * Get display application label for a package.
     */
    fun getAppNameForPackage(context: Context, packageName: String): String {
        val apps = getWhitelistedApps(context)
        val match = apps.firstOrNull { it["packageName"] == packageName }
        if (match != null) {
            val name = match["appName"] as? String
            if (!name.isNullOrBlank()) return name
        }
        return try {
            val pm = context.packageManager
            val ai = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(ai).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    /**
     * Check if notification should be emitted or skipped due to 5-second deduplication.
     */
    @Synchronized
    fun shouldEmitNotification(packageName: String, title: String, text: String): Boolean {
        val hash = computeHash("$packageName|$title|$text")
        val now = System.currentTimeMillis()
        val lastTime = deduplicationCache[hash]

        if (lastTime != null && (now - lastTime) < DEDUPLICATION_WINDOW_MS) {
            return false
        }

        deduplicationCache[hash] = now
        return true
    }

    private fun computeHash(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
