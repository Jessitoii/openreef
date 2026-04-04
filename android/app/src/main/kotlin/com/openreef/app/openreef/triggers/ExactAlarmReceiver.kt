package com.openreef.app.openreef.triggers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ExactAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != TriggerAlarmScheduler.actionExactAlarm) {
            return
        }

        val trigger = TriggerAlarmScheduler.fromIntent(intent) ?: return
        val scheduledAt =
            intent.getLongExtra(
                TriggerAlarmScheduler.extraScheduledAt,
                System.currentTimeMillis(),
            )
        val deliveredAt = System.currentTimeMillis()

        TriggerAlarmScheduler.scheduleNextOccurrence(
            context = context.applicationContext,
            trigger = trigger,
            nowEpochMs = deliveredAt,
        )
        TriggerChannelBridge.enqueueEvent(
            context = context.applicationContext,
            event =
                TriggerDeliveryEvent(
                    triggerId = trigger.triggerId,
                    type = trigger.type,
                    scheduledAtEpochMs = scheduledAt,
                    deliveredAtEpochMs = deliveredAt,
                    payloadJson = trigger.payloadJson,
                ),
        )
    }
}
