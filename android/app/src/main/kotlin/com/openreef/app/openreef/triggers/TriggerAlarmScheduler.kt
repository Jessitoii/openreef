package com.openreef.app.openreef.triggers

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import org.json.JSONObject

internal data class ScheduledTrigger(
    val triggerId: String,
    val name: String,
    val type: String,
    val hour: Int,
    val minute: Int,
    val payloadJson: String,
)

internal data class TriggerDeliveryEvent(
    val triggerId: String,
    val type: String,
    val scheduledAtEpochMs: Long,
    val deliveredAtEpochMs: Long,
    val payloadJson: String,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "triggerId" to triggerId,
            "type" to type,
            "scheduledAtEpochMs" to scheduledAtEpochMs,
            "deliveredAtEpochMs" to deliveredAtEpochMs,
            "payload" to payloadJson.toFlutterPayloadMap(),
        )

    fun toJson(): JSONObject =
        JSONObject()
            .put("triggerId", triggerId)
            .put("type", type)
            .put("scheduledAtEpochMs", scheduledAtEpochMs)
            .put("deliveredAtEpochMs", deliveredAtEpochMs)
            .put("payloadJson", payloadJson)

    companion object {
        fun fromJson(json: JSONObject): TriggerDeliveryEvent =
            TriggerDeliveryEvent(
                triggerId = json.getString("triggerId"),
                type = json.getString("type"),
                scheduledAtEpochMs = json.getLong("scheduledAtEpochMs"),
                deliveredAtEpochMs = json.getLong("deliveredAtEpochMs"),
                payloadJson = json.optString("payloadJson", "{}"),
            )
    }
}

internal object TriggerAlarmScheduler {
    const val actionExactAlarm = "com.openreef.app.openreef.triggers.EXACT_ALARM"
    const val extraTriggerId = "trigger_id"
    const val extraTriggerName = "trigger_name"
    const val extraTriggerType = "trigger_type"
    const val extraHour = "trigger_hour"
    const val extraMinute = "trigger_minute"
    const val extraScheduledAt = "scheduled_at_epoch_ms"
    const val extraPayloadJson = "payload_json"

    fun onMethodCall(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "registerExactSchedule" -> registerExactSchedule(context, call, result)
            "cancelExactSchedule" -> cancelExactSchedule(context, call, result)
            "hasExactAlarmPermission" -> result.success(hasExactAlarmPermission(context))
            else -> result.notImplemented()
        }
    }

    fun hasExactAlarmPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        return alarmManager?.canScheduleExactAlarms() ?: false
    }

    fun registerExactSchedule(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!hasExactAlarmPermission(context)) {
            result.error(
                "ERR_EXACT_ALARM_PERMISSION_DENIED",
                "Exact alarm permission is not granted.",
                null,
            )
            return
        }

        val trigger =
            call.toScheduledTrigger()
                ?: return result.error(
                    "ERR_INVALID_ARGS",
                    "Missing required trigger scheduling arguments.",
                    null,
                )

        val scheduledAt = scheduleNextOccurrence(context, trigger)
        result.success(scheduledAt)
    }

    fun cancelExactSchedule(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val triggerId =
            call.argument<String>("triggerId")
                ?: return result.error(
                    "ERR_INVALID_ARGS",
                    "Missing required argument: triggerId",
                    null,
                )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val pendingIntent =
            PendingIntent.getBroadcast(
                context,
                triggerId.hashCode(),
                buildAlarmIntent(context, triggerId = triggerId),
                PendingIntent.FLAG_NO_CREATE or pendingIntentFlags(),
            )
        if (alarmManager != null && pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        result.success(true)
    }

    fun scheduleNextOccurrence(
        context: Context,
        trigger: ScheduledTrigger,
        nowEpochMs: Long = System.currentTimeMillis(),
    ): Long {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: throw IllegalStateException("AlarmManager unavailable")

        val scheduledAt = nextDailyOccurrence(trigger.hour, trigger.minute, nowEpochMs)
        val pendingIntent =
            PendingIntent.getBroadcast(
                context,
                trigger.triggerId.hashCode(),
                buildAlarmIntent(
                    context,
                    triggerId = trigger.triggerId,
                    name = trigger.name,
                    type = trigger.type,
                    hour = trigger.hour,
                    minute = trigger.minute,
                    scheduledAtEpochMs = scheduledAt,
                    payloadJson = trigger.payloadJson,
                ),
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentFlags(),
            )

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            scheduledAt,
            pendingIntent,
        )
        return scheduledAt
    }

    fun fromIntent(intent: Intent): ScheduledTrigger? {
        val triggerId = intent.getStringExtra(extraTriggerId) ?: return null
        return ScheduledTrigger(
            triggerId = triggerId,
            name = intent.getStringExtra(extraTriggerName) ?: triggerId,
            type = intent.getStringExtra(extraTriggerType) ?: "schedule",
            hour = intent.getIntExtra(extraHour, -1),
            minute = intent.getIntExtra(extraMinute, -1),
            payloadJson = intent.getStringExtra(extraPayloadJson) ?: "{}",
        )
    }

    fun nextDailyOccurrence(
        hour: Int,
        minute: Int,
        nowEpochMs: Long = System.currentTimeMillis(),
    ): Long {
        val now =
            ZonedDateTime.ofInstant(
                Instant.ofEpochMilli(nowEpochMs),
                ZoneId.systemDefault(),
            )
        var candidate =
            now.withHour(hour)
                .withMinute(minute)
                .withSecond(0)
                .withNano(0)
        if (!candidate.isAfter(now)) {
            candidate = candidate.plusDays(1)
        }
        return candidate.toInstant().toEpochMilli()
    }

    private fun MethodCall.toScheduledTrigger(): ScheduledTrigger? {
        val triggerId = argument<String>("triggerId") ?: return null
        val hour = argument<Int>("hour") ?: return null
        val minute = argument<Int>("minute") ?: return null
        val payload =
            argument<Map<String, Any?>>("payload")
                ?.let(::JSONObject)
                ?.toString() ?: "{}"

        return ScheduledTrigger(
            triggerId = triggerId,
            name = argument<String>("name") ?: triggerId,
            type = argument<String>("type") ?: "schedule",
            hour = hour,
            minute = minute,
            payloadJson = payload,
        )
    }

    private fun buildAlarmIntent(
        context: Context,
        triggerId: String,
        name: String? = null,
        type: String? = null,
        hour: Int? = null,
        minute: Int? = null,
        scheduledAtEpochMs: Long? = null,
        payloadJson: String? = null,
    ): Intent =
        Intent(context, ExactAlarmReceiver::class.java).apply {
            action = actionExactAlarm
            putExtra(extraTriggerId, triggerId)
            putExtra(extraTriggerName, name)
            putExtra(extraTriggerType, type)
            if (hour != null) {
                putExtra(extraHour, hour)
            }
            if (minute != null) {
                putExtra(extraMinute, minute)
            }
            if (scheduledAtEpochMs != null) {
                putExtra(extraScheduledAt, scheduledAtEpochMs)
            }
            putExtra(extraPayloadJson, payloadJson ?: "{}")
        }

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
}

private fun String.toFlutterPayloadMap(): Map<String, Any?> {
    if (isBlank()) {
        return emptyMap()
    }

    return runCatching { JSONObject(this).toFlutterMap() }.getOrElse { emptyMap() }
}

private fun JSONObject.toFlutterMap(): Map<String, Any?> {
    val values = mutableMapOf<String, Any?>()
    val iterator = keys()
    while (iterator.hasNext()) {
        val key = iterator.next()
        values[key] = normalizedValue(opt(key))
    }
    return values
}

private fun normalizedValue(value: Any?): Any? =
    when (value) {
        null,
        JSONObject.NULL -> null
        is Boolean,
        is Int,
        is Long,
        is Double,
        is String -> value
        is Number -> value.toDouble()
        else -> value.toString()
    }
