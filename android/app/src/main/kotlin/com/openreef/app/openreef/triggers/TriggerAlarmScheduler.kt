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
    val hour: Int?,
    val minute: Int?,
    val cronExpression: String?,
    val payloadJson: String,
)

internal data class TriggerDeliveryEvent(
    val triggerId: String,
    val type: String,
    val scheduledAtEpochMs: Long,
    val deliveredAtEpochMs: Long,
    val payloadJson: String,
    val deliveryId: String = "${triggerId}_${scheduledAtEpochMs}_$deliveredAtEpochMs",
    val deliveryStage: String = "enqueued",
    val enqueuedAtEpochMs: Long = System.currentTimeMillis(),
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "triggerId" to triggerId,
            "deliveryId" to deliveryId,
            "type" to type,
            "scheduledAtEpochMs" to scheduledAtEpochMs,
            "deliveredAtEpochMs" to deliveredAtEpochMs,
            "deliveryStage" to deliveryStage,
            "enqueuedAtEpochMs" to enqueuedAtEpochMs,
            "payload" to payloadJson.toFlutterPayloadMap(),
        )

    fun toJson(): JSONObject =
        JSONObject()
            .put("triggerId", triggerId)
            .put("deliveryId", deliveryId)
            .put("type", type)
            .put("scheduledAtEpochMs", scheduledAtEpochMs)
            .put("deliveredAtEpochMs", deliveredAtEpochMs)
            .put("deliveryStage", deliveryStage)
            .put("enqueuedAtEpochMs", enqueuedAtEpochMs)
            .put("payloadJson", payloadJson)

    companion object {
        fun fromJson(json: JSONObject): TriggerDeliveryEvent =
            TriggerDeliveryEvent(
                triggerId = json.getString("triggerId"),
                deliveryId = json.optString("deliveryId", ""),
                type = json.getString("type"),
                scheduledAtEpochMs = json.getLong("scheduledAtEpochMs"),
                deliveredAtEpochMs = json.getLong("deliveredAtEpochMs"),
                deliveryStage = json.optString("deliveryStage", "enqueued"),
                enqueuedAtEpochMs =
                    json.optLong("enqueuedAtEpochMs", System.currentTimeMillis()),
                payloadJson = json.optString("payloadJson", "{}"),
            ).let {
                if (it.deliveryId.isNotBlank()) {
                    it
                } else {
                    it.copy(
                        deliveryId = "${it.triggerId}_${it.scheduledAtEpochMs}_${it.deliveredAtEpochMs}",
                    )
                }
            }
    }
}

internal object TriggerAlarmScheduler {
    const val actionExactAlarm = "com.openreef.app.openreef.triggers.EXACT_ALARM"
    const val extraTriggerId = "trigger_id"
    const val extraTriggerName = "trigger_name"
    const val extraTriggerType = "trigger_type"
    const val extraHour = "trigger_hour"
    const val extraMinute = "trigger_minute"
    const val extraCronExpression = "trigger_cron_expression"
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

        val scheduledAt =
            when {
                !trigger.cronExpression.isNullOrBlank() ->
                    nextCronOccurrence(trigger.cronExpression, nowEpochMs)
                trigger.hour != null && trigger.minute != null ->
                    nextDailyOccurrence(trigger.hour, trigger.minute, nowEpochMs)
                else -> throw IllegalArgumentException("Trigger is missing schedule fields")
            }
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
                    cronExpression = trigger.cronExpression,
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
            hour = intent.takeIf { it.hasExtra(extraHour) }?.getIntExtra(extraHour, -1),
            minute = intent.takeIf { it.hasExtra(extraMinute) }?.getIntExtra(extraMinute, -1),
            cronExpression = intent.getStringExtra(extraCronExpression),
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

    fun nextCronOccurrence(
        expression: String,
        nowEpochMs: Long = System.currentTimeMillis(),
    ): Long {
        val fields = expression.trim().split(Regex("\\s+"))
        require(fields.size == 5) { "Invalid cron expression" }
        require(fields[2] == "*") { "Unsupported cron day-of-month field" }
        require(fields[3] == "*") { "Unsupported cron month field" }

        val minuteField = CronField.parse(fields[0], 0, 59)
        val hourField = CronField.parse(fields[1], 0, 23)
        val dayOfWeekField = CronField.parse(fields[4], 0, 6)

        var candidate =
            ZonedDateTime.ofInstant(
                Instant.ofEpochMilli(nowEpochMs),
                ZoneId.systemDefault(),
            ).plusMinutes(1).withSecond(0).withNano(0)
        repeat(366 * 24 * 60) {
            val normalizedDayOfWeek = candidate.dayOfWeek.value % 7
            if (minuteField.matches(candidate.minute) &&
                hourField.matches(candidate.hour) &&
                dayOfWeekField.matches(normalizedDayOfWeek)
            ) {
                return candidate.toInstant().toEpochMilli()
            }
            candidate = candidate.plusMinutes(1)
        }
        throw IllegalStateException("Unable to resolve next cron occurrence")
    }

    private fun MethodCall.toScheduledTrigger(): ScheduledTrigger? {
        val triggerId = argument<String>("triggerId") ?: return null
        val cronExpression = argument<String>("cronExpression")
        val hour = argument<Int>("hour")
        val minute = argument<Int>("minute")
        if (cronExpression.isNullOrBlank() && (hour == null || minute == null)) {
            return null
        }
        val payload =
            argument<Map<String, Any?>>("payload")
                ?.let(::JSONObject)
                ?.minimizedPayloadJson()
                ?.toString() ?: "{}"

        return ScheduledTrigger(
            triggerId = triggerId,
            name = argument<String>("name") ?: triggerId,
            type = argument<String>("type") ?: "schedule",
            hour = hour,
            minute = minute,
            cronExpression = cronExpression,
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
        cronExpression: String? = null,
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
            if (cronExpression != null) {
                putExtra(extraCronExpression, cronExpression)
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

private class CronField private constructor(
    private val matcher: (Int) -> Boolean,
) {
    fun matches(value: Int): Boolean = matcher(value)

    companion object {
        fun parse(
            raw: String,
            minimum: Int,
            maximum: Int,
        ): CronField {
            val segments = raw.split(",")
            require(segments.none { it.isBlank() }) { "Invalid cron segment" }
            val predicates =
                segments.map { segment ->
                    parseSegment(segment.trim(), minimum, maximum)
                }
            return CronField { value -> predicates.any { predicate -> predicate(value) } }
        }

        private fun parseSegment(
            segment: String,
            minimum: Int,
            maximum: Int,
        ): (Int) -> Boolean {
            if (segment == "*") {
                return { true }
            }

            val stepParts = segment.split("/")
            require(stepParts.size <= 2 && stepParts[0].isNotEmpty()) { "Invalid cron step" }
            val step =
                if (stepParts.size == 2) {
                    stepParts[1].toInt().also { require(it > 0) }
                } else {
                    1
                }
            val base = stepParts[0]

            if (base == "*") {
                return { value -> (value - minimum) % step == 0 }
            }

            val rangeParts = base.split("-")
            if (rangeParts.size == 1) {
                val match = rangeParts[0].toInt()
                require(match in minimum..maximum) { "Invalid cron value" }
                return { value -> value == match }
            } else {
                require(rangeParts.size == 2) { "Invalid cron range" }
                val start = rangeParts[0].toInt()
                val end = rangeParts[1].toInt()
                require(start in minimum..maximum && end in minimum..maximum && start <= end) {
                    "Invalid cron range"
                }
                return { value -> value in start..end && (value - start) % step == 0 }
            }
        }
    }
}

private fun String.toFlutterPayloadMap(): Map<String, Any?> {
    if (isBlank()) {
        return emptyMap()
    }

    return runCatching { JSONObject(this).toFlutterMap() }.getOrElse { emptyMap() }
}

private fun JSONObject.minimizedPayloadJson(): JSONObject {
    val filtered = JSONObject()
    val iterator = keys()
    while (iterator.hasNext()) {
        val key = iterator.next()
        if (isSensitivePayloadKey(key)) {
            continue
        }
        val normalized = normalizedValue(opt(key))
        when (normalized) {
            is String -> {
                if (normalized.length <= 256) {
                    filtered.put(key, normalized)
                }
            }
            null,
            is Boolean,
            is Int,
            is Long,
            is Double -> filtered.put(key, normalized)
        }
    }
    return filtered
}

private fun isSensitivePayloadKey(key: String): Boolean {
    val lowered = key.lowercase()
    return lowered.contains("token") ||
        lowered.contains("secret") ||
        lowered.contains("password") ||
        lowered.contains("authorization") ||
        lowered.contains("auth") ||
        lowered.contains("header") ||
        lowered.contains("bearer") ||
        lowered.contains("api_key") ||
        lowered.contains("api-key")
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
