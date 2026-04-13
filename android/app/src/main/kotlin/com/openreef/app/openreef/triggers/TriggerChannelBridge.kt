package com.openreef.app.openreef.triggers

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import com.openreef.app.openreef.wake.AutoDreamWorker
import com.openreef.app.openreef.wake.TriggerRegistryStore

internal object TriggerChannelBridge :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private const val prefsName = "openreef.trigger.bridge"
    private const val pendingEventsKey = "pending_events"
    private const val acknowledgedEventsKey = "acknowledged_events"
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

    fun attachToFlutterEngine(
        context: Context,
        flutterEngine: io.flutter.embedding.engine.FlutterEngine,
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
        persistEvent(applicationContext, event.copy(deliveryStage = "enqueued"))
        flushPendingEvents(applicationContext)
    }

    fun enqueueEventIfMissing(
        context: Context,
        event: TriggerDeliveryEvent,
    ): Boolean {
        val applicationContext = context.applicationContext
        appContext = applicationContext
        val queued = readPersistedEvents(applicationContext)
        if (queued.any { it.deliveryId == event.deliveryId }) {
            flushPendingEvents(applicationContext)
            return false
        }
        persistEvent(applicationContext, event.copy(deliveryStage = "enqueued"))
        flushPendingEvents(applicationContext)
        return true
    }

    fun syncTriggerRegistry(
        context: Context,
        triggers: List<Map<String, Any?>>,
    ) {
        TriggerRegistryStore.sync(context.applicationContext, triggers)
    }

    fun registerGlobalPollingWork(context: Context) {
        AutoDreamWorker.enqueue(context.applicationContext)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("ERR_TRIGGER_CONTEXT", "Trigger bridge is not initialized.", null)
            return
        }
        when (call.method) {
            "syncTriggerRegistry" -> {
                val triggers = call.argument<List<Map<String, Any?>>>("triggers").orEmpty()
                syncTriggerRegistry(context, triggers)
                result.success(true)
            }
            "syncGlobalPollMinutes" -> {
                val minutes = call.argument<Int>("minutes") ?: 15
                TriggerRegistryStore.syncGlobalPollMinutes(context, minutes)
                result.success(true)
            }
            "registerGlobalPollingWork" -> {
                registerGlobalPollingWork(context)
                result.success(true)
            }
            else -> TriggerAlarmScheduler.onMethodCall(context, call, result)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        appContext?.let(::flushPendingEvents)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun flushPendingEvents(context: Context) {
        val sink = eventSink ?: return
        val pendingEvents = readPersistedEvents(context)
        if (pendingEvents.isEmpty()) {
            return
        }

        mainHandler.post {
            val deliveredIds = mutableListOf<String>()
            pendingEvents.forEach { event ->
                sink.success(event.copy(deliveryStage = "handed_off_to_flutter").toMap())
                deliveredIds.add(event.deliveryId)
            }
            if (deliveredIds.isNotEmpty()) {
                markDelivered(context, deliveredIds)
            }
        }
    }

    private fun persistEvent(
        context: Context,
        event: TriggerDeliveryEvent,
    ) {
        val sharedPreferences = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val existingEvents = readPersistedEvents(context).toMutableList()
        existingEvents.removeAll { it.deliveryId == event.deliveryId }
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

    private fun markDelivered(
        context: Context,
        deliveredIds: List<String>,
    ) {
        val sharedPreferences = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val remainingEvents =
            readPersistedEvents(context)
                .filterNot { it.deliveryId in deliveredIds }
        val encoded = JSONArray()
        remainingEvents.forEach {
            encoded.put(it.copy(deliveryStage = "handed_off_to_flutter").toJson())
        }
        sharedPreferences.edit()
            .putString(pendingEventsKey, encoded.toString())
            .putString(acknowledgedEventsKey, JSONArray(deliveredIds).toString())
            .apply()
    }

    private fun isExpired(event: TriggerDeliveryEvent): Boolean {
        val ageMs = System.currentTimeMillis() - event.enqueuedAtEpochMs
        return ageMs > maxPendingAgeMs
    }
}

private data class ChannelBinding(
    val engine: io.flutter.embedding.engine.FlutterEngine,
    val methodChannel: MethodChannel,
    val eventChannel: EventChannel,
)
