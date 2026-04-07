package com.openreef.app.openreef.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat
import com.openreef.app.openreef.wake.WakeWordService
import io.flutter.plugin.common.EventChannel

// Owns the long-running Android foreground service for agent wake-word activity.
class OpenReefForegroundService : Service() {
    private lateinit var wakeWordService: WakeWordService

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        ensureNotificationChannel()
        wakeWordService =
            WakeWordService(applicationContext) {
                WakeWordEventBridge.emitDetected()
            }
        wakeWordService.setSensitivity(requestedSensitivity)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LISTENING -> startListening()
            ACTION_STOP_LISTENING -> stopListening()
            else -> startForeground(NOTIFICATION_ID, buildNotification(listeningState))
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopListening(removeNotification = false)
        wakeWordService.dispose()
        listeningState = false
        serviceInstance = null
        super.onDestroy()
    }

    private fun startListening() {
        startForeground(NOTIFICATION_ID, buildNotification(true))
        listeningState = wakeWordService.startListening()
        val notification =
            buildNotification(
                listening = listeningState,
                waitingForAccessKey = !listeningState,
            )
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun stopListening(removeNotification: Boolean = true) {
        wakeWordService.stopListening()
        listeningState = false
        if (removeNotification) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
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

    private fun buildNotification(
        listening: Boolean,
        waitingForAccessKey: Boolean = false,
    ): Notification {
        val contentText =
            when {
                listening -> "Listening for the Porcupine wake word."
                waitingForAccessKey -> "Provision a Picovoice access key to enable listening."
                else -> "Wake-word listener is idle."
            }

        return Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("OpenReef wake word")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(listening)
            .build()
    }

    companion object {
        const val ACTION_START_LISTENING = "com.openreef.app.openreef.wake.START_LISTENING"
        const val ACTION_STOP_LISTENING = "com.openreef.app.openreef.wake.STOP_LISTENING"

        private const val NOTIFICATION_ID = 4101
        private const val NOTIFICATION_CHANNEL_ID = "openreef_wake_word"
        private const val NOTIFICATION_CHANNEL_NAME = "OpenReef Wake Word"
        private const val DEFAULT_SENSITIVITY = 0.7f

        @Volatile
        private var listeningState = false

        @Volatile
        private var serviceInstance: OpenReefForegroundService? = null

        @Volatile
        private var requestedSensitivity = DEFAULT_SENSITIVITY

        fun requestStart(context: Context): Boolean {
            val intent = Intent(context, OpenReefForegroundService::class.java).apply {
                action = ACTION_START_LISTENING
            }
            ContextCompat.startForegroundService(context, intent)
            return true
        }

        fun requestStop(context: Context): Boolean {
            val intent = Intent(context, OpenReefForegroundService::class.java).apply {
                action = ACTION_STOP_LISTENING
            }
            context.startService(intent)
            return true
        }

        fun isListening(): Boolean = listeningState

        fun isAvailable(context: Context): Boolean = WakeWordService.isConfigured(context)

        fun setSensitivity(value: Double?): Boolean {
            val normalized =
                (value ?: DEFAULT_SENSITIVITY.toDouble()).toFloat().coerceIn(0.3f, 0.9f)
            requestedSensitivity = normalized
            serviceInstance?.wakeWordService?.setSensitivity(normalized)
            return true
        }

        fun attachEventSink(eventSink: EventChannel.EventSink?) {
            WakeWordEventBridge.attachEventSink(eventSink)
        }
    }
}

private object WakeWordEventBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun attachEventSink(nextSink: EventChannel.EventSink?) {
        eventSink = nextSink
    }

    fun emitDetected() {
        mainHandler.post {
            eventSink?.success(mapOf("event" to "detected"))
        }
    }
}
