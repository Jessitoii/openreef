package com.openreef.app.openreef

import android.content.Context
import android.media.AudioManager
import android.app.ActivityManager
import android.os.BatteryManager
import com.openreef.app.openreef.litert.LiteRtLmBridge
import com.openreef.app.openreef.litert.LiteRtAndroidLmEngine
import com.openreef.app.openreef.service.OpenReefForegroundService
import com.openreef.app.openreef.triggers.TriggerChannelBridge
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var liteRtBridge: LiteRtLmBridge? = null
    private var nativeToolsChannel: MethodChannel? = null
    private var deviceStatsChannel: MethodChannel? = null
    private var wakeWordChannel: MethodChannel? = null
    private var wakeWordEventChannel: EventChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TriggerChannelBridge.attachToFlutterEngine(applicationContext, flutterEngine)
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
        if (deviceStatsChannel == null) {
            deviceStatsChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    DEVICE_STATS_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "getDeviceStats" -> handleGetDeviceStats(result)
                            else -> result.notImplemented()
                        }
                    }
                }
        }
        if (wakeWordChannel == null) {
            wakeWordChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    WAKE_WORD_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "startListening" -> result.success(handleStartWakeWord())
                            "stopListening" -> result.success(handleStopWakeWord())
                            "isListening" -> result.success(OpenReefForegroundService.isListening())
                            else -> result.notImplemented()
                        }
                    }
                }
        }
        if (wakeWordEventChannel == null) {
            wakeWordEventChannel =
                EventChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    WAKE_WORD_EVENT_CHANNEL_NAME,
                ).also { channel ->
                    channel.setStreamHandler(
                        object : EventChannel.StreamHandler {
                            override fun onListen(
                                arguments: Any?,
                                events: EventChannel.EventSink?,
                            ) {
                                OpenReefForegroundService.attachEventSink(events)
                            }

                            override fun onCancel(arguments: Any?) {
                                OpenReefForegroundService.attachEventSink(null)
                            }
                        },
                    )
                }
        }
    }

    override fun onDestroy() {
        nativeToolsChannel?.setMethodCallHandler(null)
        nativeToolsChannel = null
        deviceStatsChannel?.setMethodCallHandler(null)
        deviceStatsChannel = null
        wakeWordChannel?.setMethodCallHandler(null)
        wakeWordChannel = null
        wakeWordEventChannel?.setStreamHandler(null)
        wakeWordEventChannel = null
        OpenReefForegroundService.attachEventSink(null)
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

    private fun handleGetDeviceStats(result: MethodChannel.Result) {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (activityManager == null) {
            result.error("ERR_DEVICE_STATS", "ActivityManager unavailable", null)
            return
        }
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val freeRamGb = memoryInfo.availMem.toDouble() / (1024.0 * 1024.0 * 1024.0)
        result.success(
            mapOf(
                "freeRamGb" to freeRamGb,
                "npuReady" to false,
            ),
        )
    }

    private fun handleStartWakeWord(): Boolean =
        OpenReefForegroundService.requestStart(applicationContext)

    private fun handleStopWakeWord(): Boolean =
        OpenReefForegroundService.requestStop(applicationContext)

    companion object {
        private const val NATIVE_TOOLS_CHANNEL_NAME = "openreef/native_tools"
        private const val DEVICE_STATS_CHANNEL_NAME = "openreef/device_stats"
        private const val WAKE_WORD_CHANNEL_NAME = "openreef/wake_word_channel"
        private const val WAKE_WORD_EVENT_CHANNEL_NAME = "openreef/wake_word_events"
    }
}
