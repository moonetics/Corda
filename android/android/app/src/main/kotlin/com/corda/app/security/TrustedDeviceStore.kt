package com.corda.app.security

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Model representing a verified remote device trusted for mutual authentication.
 */
data class TrustedDevice(
    val id: String,
    val name: String,
    val platform: String,
    val publicKeyString: String,
    val fingerprint: String,
    val pairedAt: String
) {
    fun toJsonObject(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("platform", platform)
        put("publicKeyString", publicKeyString)
        put("fingerprint", fingerprint)
        put("pairedAt", pairedAt)
    }

    companion object {
        fun fromJsonObject(json: JSONObject): TrustedDevice = TrustedDevice(
            id = json.getString("id"),
            name = json.getString("name"),
            platform = json.getString("platform"),
            publicKeyString = json.getString("publicKeyString"),
            fingerprint = json.getString("fingerprint"),
            pairedAt = json.optString("pairedAt", "")
        )
    }
}

/**
 * Manages persistent storage of Trusted Devices in Android SharedPreferences.
 */
class TrustedDeviceStore(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences(
        "com.corda.app.trusted_devices_prefs",
        Context.MODE_PRIVATE
    )

    private val keyDevices = "trusted_devices_json"

    /**
     * Get the list of all registered trusted devices.
     */
    fun getTrustedDevices(): List<TrustedDevice> {
        val raw = prefs.getString(keyDevices, null) ?: return emptyList()
        val list = mutableListOf<TrustedDevice>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                list.add(TrustedDevice.fromJsonObject(array.getJSONObject(i)))
            }
        } catch (_: Exception) {
            return emptyList()
        }
        return list
    }

    /**
     * Add or update a trusted device.
     */
    fun saveTrustedDevice(device: TrustedDevice) {
        val current = getTrustedDevices().toMutableList()
        current.removeAll { it.id == device.id || it.fingerprint.equals(device.fingerprint, ignoreCase = true) }
        current.add(device)
        persist(current)
    }

    /**
     * Remove a trusted device by its UUID.
     */
    fun removeTrustedDevice(id: String) {
        val current = getTrustedDevices().toMutableList()
        current.removeAll { it.id == id }
        persist(current)
    }

    /**
     * Check if a given SHA-256 fingerprint belongs to an authorized trusted device.
     */
    fun isFingerprintTrusted(fingerprint: String): Boolean {
        return getTrustedDevices().any { it.fingerprint.equals(fingerprint, ignoreCase = true) }
    }

    private fun persist(devices: List<TrustedDevice>) {
        val array = JSONArray()
        devices.forEach { array.put(it.toJsonObject()) }
        prefs.edit().putString(keyDevices, array.toString()).apply()
    }
}
