package com.openreef.app.openreef.wake

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.openreef.app.openreef.triggers.TriggerChannelBridge
import com.openreef.app.openreef.triggers.TriggerDeliveryEvent
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class AutoDreamWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val snapshotStore = TriggerPollingSnapshotStore(context)
        val triggers = TriggerRegistryStore.loadAll(context)
        if (triggers.isEmpty()) {
            return Result.success()
        }

        val now = System.currentTimeMillis()
        var changed = false

        triggers
            .filter { it.enabled && it.supportsPolling }
            .sortedBy { it.triggerId }
            .forEach { trigger ->
                val resolvedMinutes = trigger.effectivePollMinutes(context)
                if (resolvedMinutes < 15) {
                    snapshotStore.store(
                        trigger.triggerId,
                        snapshotStore.load(trigger.triggerId).copy(
                            lastCheckedAtEpochMs = now,
                            unsupportedReason = "poll_interval_unsupported_below_15_minutes",
                        ),
                    )
                    changed = true
                    return@forEach
                }

                val state = snapshotStore.load(trigger.triggerId)
                val dueAt =
                    state.lastDeliveredAtEpochMs?.plus(
                        TimeUnit.MINUTES.toMillis(resolvedMinutes.toLong()),
                    ) ?: state.lastCheckedAtEpochMs ?: now

                if (now < dueAt) {
                    snapshotStore.store(
                        trigger.triggerId,
                        state.copy(lastCheckedAtEpochMs = now, unsupportedReason = null),
                    )
                    changed = true
                    return@forEach
                }

                val event = trigger.toDeliveryEvent(nowEpochMs = now, scheduledAtEpochMs = dueAt)
                TriggerChannelBridge.enqueueEventIfMissing(
                    context = context,
                    event = event,
                )
                snapshotStore.store(
                    trigger.triggerId,
                    state.copy(
                        lastCheckedAtEpochMs = now,
                        lastDeliveredAtEpochMs = now,
                        cursor = event.deliveryId,
                        unsupportedReason = null,
                    ),
                )
                changed = true
            }

        return if (changed) Result.success() else Result.success()
    }

    companion object {
        const val UNIQUE_WORK_NAME = "openreef.trigger.polling.global"

        fun enqueue(context: Context) {
            val request =
                PeriodicWorkRequestBuilder<AutoDreamWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(
                        Constraints.Builder()
                            .setRequiresBatteryNotLow(false)
                            .build(),
                    )
                    .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }
}

internal data class PersistedTriggerSnapshot(
    val triggerId: String,
    val name: String,
    val type: String,
    val prompt: String,
    val enabled: Boolean,
    val intervalMinutes: Int?,
    val pollIntervalMinutes: Int?,
    val payloadJson: String,
) {
    val supportsPolling: Boolean
        get() = type == "interval"

    fun effectivePollMinutes(context: Context): Int {
        val triggerOverride = pollIntervalMinutes
        if (triggerOverride != null) {
            return triggerOverride
        }

        val globalMinutes =
            context
                .getSharedPreferences(TriggerRegistryStore.settingsPrefsName, Context.MODE_PRIVATE)
                .getInt(TriggerRegistryStore.globalPollMinutesKey, 15)
        return if (globalMinutes > 0) globalMinutes else 15
    }

    fun toDeliveryEvent(
        nowEpochMs: Long,
        scheduledAtEpochMs: Long,
    ): TriggerDeliveryEvent {
        return TriggerDeliveryEvent(
            triggerId = triggerId,
            type = type,
            scheduledAtEpochMs = scheduledAtEpochMs,
            deliveredAtEpochMs = nowEpochMs,
            payloadJson = payloadJson,
            deliveryId = "${triggerId}_$scheduledAtEpochMs",
            deliveryStage = "enqueued",
        )
    }
}

internal data class TriggerPollStateSnapshot(
    val lastCheckedAtEpochMs: Long? = null,
    val lastDeliveredAtEpochMs: Long? = null,
    val cursor: String? = null,
    val unsupportedReason: String? = null,
)

internal object TriggerRegistryStore {
    const val prefsName = "openreef.trigger.registry"
    const val settingsPrefsName = "openreef.settings"
    const val registryKey = "registry"
    const val globalPollMinutesKey = "global_poll_minutes"

    fun sync(context: Context, triggers: List<Map<String, Any?>>) {
        val encoded = JSONArray()
        triggers.forEach { encoded.put(JSONObject(it)) }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(registryKey, encoded.toString())
            .apply()
    }

    fun syncGlobalPollMinutes(context: Context, minutes: Int) {
        context.getSharedPreferences(settingsPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putInt(globalPollMinutesKey, minutes)
            .apply()
    }

    fun loadAll(context: Context): List<PersistedTriggerSnapshot> {
        val raw =
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(registryKey, null)
                ?: return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrElse { return emptyList() }
        return buildList {
            for (index in 0 until array.length()) {
                val json = array.optJSONObject(index) ?: continue
                add(
                    PersistedTriggerSnapshot(
                        triggerId = json.optString("id"),
                        name = json.optString("name"),
                        type = json.optString("type"),
                        prompt = json.optString("prompt"),
                        enabled = json.optBoolean("enabled", true),
                        intervalMinutes = json.optJSONObject("intervalSpec")
                            ?.optLong("everyMs")
                            ?.takeIf { it > 0 }
                            ?.div(60000)
                            ?.toInt(),
                        pollIntervalMinutes = json.opt("pollIntervalMinutes")
                            ?.takeIf { it is Number }
                            ?.let { (it as Number).toInt() },
                        payloadJson = json.optJSONObject("payload")?.toString() ?: "{}",
                    ),
                )
            }
        }
    }
}

internal class TriggerPollingSnapshotStore(context: Context) {
    private val prefs =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    fun load(triggerId: String): TriggerPollStateSnapshot {
        val raw = prefs.getString(key(triggerId), null) ?: return TriggerPollStateSnapshot()
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return TriggerPollStateSnapshot()
        return TriggerPollStateSnapshot(
            lastCheckedAtEpochMs = json.optLongOrNull("lastCheckedAtEpochMs"),
            lastDeliveredAtEpochMs = json.optLongOrNull("lastDeliveredAtEpochMs"),
            cursor = json.optStringOrNull("cursor"),
            unsupportedReason = json.optStringOrNull("unsupportedReason"),
        )
    }

    fun store(triggerId: String, state: TriggerPollStateSnapshot) {
        prefs.edit().putString(key(triggerId), state.toJson().toString()).apply()
    }

    companion object {
        const val prefsName = "openreef.trigger.poll_state"

        private fun key(triggerId: String) = "poll_state_$triggerId"
    }
}

private fun TriggerPollStateSnapshot.toJson(): JSONObject =
    JSONObject()
        .put("lastCheckedAtEpochMs", lastCheckedAtEpochMs)
        .put("lastDeliveredAtEpochMs", lastDeliveredAtEpochMs)
        .put("cursor", cursor)
        .put("unsupportedReason", unsupportedReason)

private fun JSONObject.optLongOrNull(name: String): Long? =
    if (has(name) && !isNull(name)) optLong(name) else null

private fun JSONObject.optStringOrNull(name: String): String? =
    if (has(name) && !isNull(name)) optString(name) else null
