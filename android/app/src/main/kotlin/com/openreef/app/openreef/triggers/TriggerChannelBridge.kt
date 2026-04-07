package com.openreef.app.openreef.triggers

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray

internal object TriggerChannelBridge :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private const val prefsName = "openreef.trigger.bridge"
    private const val pendingEventsKey = "pending_events"
    private const val methodChannelName = "openreef/triggers_channel"
    private const val eventChannelName = "openreef/triggers_events"
    private const val maxPendingEvents = 20
    private const val maxPendingAgeMs = 24L * 60L * 60L * 1000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bindings = mutableListOf<ChannelBinding>()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var backgroundEngine: FlutterEngine? = null

    fun attachToFlutterEngine(
        context: Context,
        flutterEngine: FlutterEngine,
    ) {
        val applicationContext = context.applicationContext
        appContext = applicationContext
        if (bindings.any { it.engine === flutterEngine }) {
            flushPendingEvents(applicationContext)
            return
        }

        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        val eventChannel =
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        bindings.add(ChannelBinding(flutterEngine, methodChannel, eventChannel))
        flushPendingEvents(applicationContext)
    }

    fun enqueueEvent(
        context: Context,
        event: TriggerDeliveryEvent,
    ) {
        val applicationContext = context.applicationContext
        appContext = applicationContext
        persistEvent(applicationContext, event)
        flushPendingEvents(applicationContext)
        if (eventSink == null) {
            ensureBackgroundFlutterEngine(applicationContext)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("ERR_TRIGGER_CONTEXT", "Trigger bridge is not initialized.", null)
            return
        }
        TriggerAlarmScheduler.onMethodCall(context, call, result)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        appContext?.let(::flushPendingEvents)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun ensureBackgroundFlutterEngine(context: Context) {
        synchronized(this) {
            if (backgroundEngine != null) {
                return
            }

            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)

            val engine = FlutterEngine(context)
            GeneratedPluginRegistrant.registerWith(engine)
            attachToFlutterEngine(context, engine)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "main"),
            )
            backgroundEngine = engine
        }
    }

    private fun flushPendingEvents(context: Context) {
        val sink = eventSink ?: return
        val pendingEvents = readPersistedEvents(context)
        if (pendingEvents.isEmpty()) {
            return
        }

        mainHandler.post {
            pendingEvents.forEach { event ->
                sink.success(event.toMap())
            }
            context
                .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .remove(pendingEventsKey)
                .apply()
        }
    }

    private fun persistEvent(
        context: Context,
        event: TriggerDeliveryEvent,
    ) {
        val sharedPreferences = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val existingEvents = readPersistedEvents(context).toMutableList()
        existingEvents.add(event)
        val trimmedEvents =
            existingEvents
                .filterNot(::isExpired)
                .takeLast(maxPendingEvents)
        val encoded = JSONArray()
        trimmedEvents.forEach { encoded.put(it.toJson()) }
        sharedPreferences.edit().putString(pendingEventsKey, encoded.toString()).apply()
    }

    private fun readPersistedEvents(context: Context): List<TriggerDeliveryEvent> {
        val raw =
            context
                .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(pendingEventsKey, null) ?: return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrElse { return emptyList() }
        return buildList {
            for (index in 0 until array.length()) {
                val event = TriggerDeliveryEvent.fromJson(array.getJSONObject(index))
                if (!isExpired(event)) {
                    add(event)
                }
            }
        }
    }

    private fun isExpired(event: TriggerDeliveryEvent): Boolean {
        val ageMs = System.currentTimeMillis() - event.enqueuedAtEpochMs
        return ageMs > maxPendingAgeMs
    }
}

private data class ChannelBinding(
    val engine: FlutterEngine,
    val methodChannel: MethodChannel,
    val eventChannel: EventChannel,
)
