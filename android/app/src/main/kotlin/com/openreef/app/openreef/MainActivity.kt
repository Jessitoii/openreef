package com.openreef.app.openreef

import android.content.Context
import android.media.AudioManager
import android.os.BatteryManager
import com.openreef.app.openreef.litert.LiteRtLmBridge
import com.openreef.app.openreef.litert.LiteRtAndroidLmEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var liteRtBridge: LiteRtLmBridge? = null
    private var nativeToolsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (liteRtBridge == null) {
            liteRtBridge =
                LiteRtLmBridge(
                    messenger = flutterEngine.dartExecutor.binaryMessenger,
                    engine = LiteRtAndroidLmEngine(applicationContext),
                )
        }
        if (nativeToolsChannel == null) {
            nativeToolsChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    NATIVE_TOOLS_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "setVolumeLevel" ->
                                handleSetVolumeLevel(call.argument<Double>("level"), result)
                            "getBatteryInfo" -> handleGetBatteryInfo(result)
                            else -> result.notImplemented()
                        }
                    }
                }
        }
    }

    override fun onDestroy() {
        nativeToolsChannel?.setMethodCallHandler(null)
        nativeToolsChannel = null
        liteRtBridge?.dispose()
        liteRtBridge = null
        super.onDestroy()
    }

    private fun handleSetVolumeLevel(level: Double?, result: MethodChannel.Result) {
        if (level == null) {
            result.error("ERR_INVALID_ARGS", "Missing required argument: level", null)
            return
        }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            result.error("ERR_AUDIO_UNAVAILABLE", "AudioManager unavailable", null)
            return
        }

        val normalizedLevel = level.coerceIn(0.0, 1.0)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = (normalizedLevel * maxVolume).toInt().coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)

        val appliedVolume =
            if (maxVolume == 0) 0.0 else targetVolume.toDouble() / maxVolume.toDouble()
        result.success(appliedVolume)
    }

    private fun handleGetBatteryInfo(result: MethodChannel.Result) {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        if (batteryManager == null) {
            result.error("ERR_BATTERY_UNAVAILABLE", "BatteryManager unavailable", null)
            return
        }

        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        val state =
            when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                BatteryManager.BATTERY_STATUS_FULL -> "full"
                BatteryManager.BATTERY_STATUS_DISCHARGING,
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "discharging"
                else -> "unknown"
            }

        result.success(
            mapOf(
                "level" to level,
                "state" to state,
                "isLowPowerMode" to false,
            ),
        )
    }

    companion object {
        private const val NATIVE_TOOLS_CHANNEL_NAME = "openreef/native_tools"
    }
}
