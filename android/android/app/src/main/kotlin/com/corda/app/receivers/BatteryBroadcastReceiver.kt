package com.corda.app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.util.Log
import com.corda.app.events.BatteryStatusEvent
import com.corda.app.events.CordaEventBus

class BatteryBroadcastReceiver(
    private val onStatusChanged: ((level: Int, isCharging: Boolean, powerSource: String) -> Unit)? = null
) : BroadcastReceiver() {

    companion object {
        private const val TAG = "BatteryReceiver"
        private const val MIN_UPDATE_INTERVAL_MS = 15000L // Throttle 15 seconds

        fun getCurrentBatteryStatus(context: Context): Triple<Int, Boolean, String> {
            val intent = context.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val batteryPct = if (level >= 0 && scale > 0) {
                ((level.toFloat() / scale.toFloat()) * 100).toInt().coerceIn(0, 100)
            } else {
                100
            }
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
            val isPlugged = plugged == BatteryManager.BATTERY_PLUGGED_AC ||
                            plugged == BatteryManager.BATTERY_PLUGGED_USB ||
                            plugged == BatteryManager.BATTERY_PLUGGED_WIRELESS
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                             status == BatteryManager.BATTERY_STATUS_FULL ||
                             isPlugged
            val powerSource = when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                else -> if (isCharging) "ac" else "battery"
            }
            return Triple(batteryPct, isCharging, powerSource)
        }
    }

    private var lastLevel = -1
    private var lastIsCharging: Boolean? = null
    private var lastPowerSource: String? = null
    private var lastUpdateTime = 0L

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BATTERY_CHANGED) return

        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return

        val batteryPct = ((level.toFloat() / scale.toFloat()) * 100).toInt().coerceIn(0, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val isPlugged = plugged == BatteryManager.BATTERY_PLUGGED_AC ||
                        plugged == BatteryManager.BATTERY_PLUGGED_USB ||
                        plugged == BatteryManager.BATTERY_PLUGGED_WIRELESS
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                         status == BatteryManager.BATTERY_STATUS_FULL ||
                         isPlugged

        val powerSource = when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> if (isCharging) "ac" else "battery"
        }

        val now = System.currentTimeMillis()
        val chargingChanged = lastIsCharging != isCharging || lastPowerSource != powerSource
        val levelChanged = lastLevel != batteryPct
        val intervalElapsed = (now - lastUpdateTime) >= MIN_UPDATE_INTERVAL_MS

        // Only trigger update if state changed (immediate for charging switch, throttled for percentage changes)
        if (lastLevel == -1 || chargingChanged || (levelChanged && intervalElapsed)) {
            lastLevel = batteryPct
            lastIsCharging = isCharging
            lastPowerSource = powerSource
            lastUpdateTime = now

            Log.i(TAG, "Battery status update: $batteryPct% | charging=$isCharging ($powerSource)")

            CordaEventBus.postBatteryStatus(
                BatteryStatusEvent(
                    level = batteryPct,
                    isCharging = isCharging,
                    powerSource = powerSource,
                    timestamp = now
                )
            )

            onStatusChanged?.invoke(batteryPct, isCharging, powerSource)
        }
    }
}
