package com.openreef.app.openreef.wake

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.openreef.app.openreef.triggers.TriggerChannelBridge

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }
        TriggerChannelBridge.registerGlobalPollingWork(context.applicationContext)
    }
}
