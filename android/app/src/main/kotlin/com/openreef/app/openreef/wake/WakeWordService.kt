package com.openreef.app.openreef.wake

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

// Hosts wake word detection for always-on voice activation.
//
// This service is intentionally a stub. It owns the foreground-service shell
// needed for later Porcupine integration without implementing audio capture.
class WakeWordService : Service() {
    @Volatile
    private var listening = false

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LISTENING -> startListening()
            ACTION_STOP_LISTENING -> stopListening()
            else -> startForeground(NOTIFICATION_ID, buildNotification())
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        listening = false
        super.onDestroy()
    }

    private fun startListening() {
        listening = true
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun stopListening() {
        listening = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "OpenReef wake-word listening status."
            }
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("OpenReef wake word")
            .setContentText(
                if (listening) {
                    "Wake-word listener stub is active."
                } else {
                    "Wake-word listener stub is idle."
                },
            ).setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(listening)
            .build()

    companion object {
        const val ACTION_START_LISTENING = "com.openreef.app.openreef.wake.START_LISTENING"
        const val ACTION_STOP_LISTENING = "com.openreef.app.openreef.wake.STOP_LISTENING"

        private const val NOTIFICATION_ID = 4101
        private const val NOTIFICATION_CHANNEL_ID = "openreef_wake_word"
        private const val NOTIFICATION_CHANNEL_NAME = "OpenReef Wake Word"
    }
}
