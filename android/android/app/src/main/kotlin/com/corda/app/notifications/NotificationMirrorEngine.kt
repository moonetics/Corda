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
    private const val KEY_ALL_APPS_ENABLED = "notification_mirroring_all_apps_enabled"
    private const val KEY_ALL_SYSTEM_ENABLED = "notification_mirroring_all_system_enabled"
    private const val KEY_BLACKLISTED_APPS_JSON = "notification_blacklisted_apps_json"
    private const val KEY_WHITELIST_JSON = "notification_whitelist_apps_json"
    private const val KEY_PREFIX_PKG = "pkg_allowed_"
    private const val KEY_PREFIX_BLACKLIST = "pkg_blacklisted_"

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
     * Check if All Applications universal forwarding is enabled.
     */
    fun isAllAppsEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_ALL_APPS_ENABLED, false)
    }

    /**
     * Update All Applications universal forwarding state.
     */
    fun setAllAppsEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_ALL_APPS_ENABLED, enabled).apply()
        Log.i(TAG, "All Applications Forwarding set to: $enabled")
    }

    /**
     * Check if Android System alerts (OS, SystemUI, low-level alerts) are included.
     * Default is false matching Apple Continuity behavior.
     */
    fun isAllSystemEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_ALL_SYSTEM_ENABLED, false)
    }

    /**
     * Update Android System alerts forwarding state.
     */
    fun setAllSystemEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_ALL_SYSTEM_ENABLED, enabled).apply()
        Log.i(TAG, "Android System Alerts set to: $enabled")
    }

    /**
     * Determine if a package belongs to Android OS core or low-level system UI.
     */
    fun isSystemApp(context: Context, packageName: String): Boolean {
        if (packageName == "android" ||
            packageName.startsWith("com.android.systemui") ||
            packageName == "com.google.android.gms" ||
            packageName.startsWith("com.android.providers.") ||
            packageName.startsWith("com.google.android.providers.")) {
            return true
        }
        return try {
            val pm = context.packageManager
            val ai = pm.getApplicationInfo(packageName, 0)
            (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 || 
            (ai.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Returns the list of blacklisted / excluded package names.
     */
    fun getBlacklistedApps(context: Context): List<String> {
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(KEY_BLACKLISTED_APPS_JSON, null) ?: return emptyList()
        val list = mutableListOf<String>()
        try {
            val arr = JSONArray(jsonStr)
            for (i in 0 until arr.length()) {
                val pkg = arr.optString(i)
                if (pkg.isNotEmpty()) {
                    list.add(pkg)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse blacklisted apps JSON: ${e.message}")
        }
        return list
    }

    /**
     * Check if a specific package is blacklisted/excluded.
     */
    fun isAppBlacklisted(context: Context, packageName: String): Boolean {
        val prefs = getPrefs(context)
        val key = KEY_PREFIX_BLACKLIST + packageName
        if (prefs.contains(key)) {
            return prefs.getBoolean(key, false)
        }
        return getBlacklistedApps(context).contains(packageName)
    }

    /**
     * Set blacklisted/excluded state for an app in All Applications mode.
     */
    fun setAppBlacklisted(context: Context, packageName: String, blacklisted: Boolean) {
        val current = getBlacklistedApps(context).toMutableList()
        if (blacklisted) {
            if (!current.contains(packageName)) current.add(packageName)
        } else {
            current.remove(packageName)
        }
        val arr = JSONArray()
        for (pkg in current) {
            arr.put(pkg)
        }
        val prefs = getPrefs(context)
        prefs.edit()
            .putString(KEY_BLACKLISTED_APPS_JSON, arr.toString())
            .putBoolean(KEY_PREFIX_BLACKLIST + packageName, blacklisted)
            .apply()
        Log.i(TAG, "Notification app '$packageName' blacklisted set to: $blacklisted")
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
     * Check if a specific package is allowed to forward notifications to macOS.
     * Respects master switch, All Applications universal mode, blacklist exclusions,
     * System Alerts toggle, and fallback custom whitelist.
     */
    fun isPackageAllowed(context: Context, packageName: String): Boolean {
        if (!isMasterEnabled(context)) return false

        // Never mirror notifications from Corda itself
        if (packageName == context.packageName) return false

        // 1. All Applications mode (Universal Continuity Mode)
        if (isAllAppsEnabled(context)) {
            // Check if user specifically excluded/blacklisted this app
            if (isAppBlacklisted(context, packageName)) {
                return false
            }

            val isSys = isSystemApp(context, packageName)
            return if (isSys) {
                // If internal OS system app, only allow if user explicitly enabled System Alerts
                isAllSystemEnabled(context)
            } else {
                // Regular user-installed app (WhatsApp, Telegram, etc.) is allowed!
                true
            }
        }

        // 2. Custom Whitelist mode
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
