package com.openreef.app.openreef.wake

import android.content.Context
import android.util.Log
import ai.picovoice.porcupine.Porcupine
import ai.picovoice.porcupine.PorcupineManager

// Owns Porcupine wake-word detection while the foreground service keeps
// microphone access active in the background.
class WakeWordService(
    private val context: Context,
    private val onWakeWordDetected: () -> Unit,
) {
    @Volatile
    private var listening = false

    private var porcupineManager: PorcupineManager? = null

    fun startListening(): Boolean {
        if (listening) {
            return true
        }

        if (PICOVOICE_ACCESS_KEY == PICOVOICE_PLACEHOLDER_KEY) {
            Log.w(TAG, "Replace PICOVOICE_ACCESS_KEY before starting Porcupine.")
            return false
        }

        return try {
            val manager = porcupineManager ?: buildPorcupineManager().also {
                porcupineManager = it
            }
            manager.start()
            listening = true
            true
        } catch (error: Exception) {
            Log.e(TAG, "Failed to start Porcupine wake-word listener.", error)
            listening = false
            false
        }
    }

    fun stopListening() {
        if (!listening) {
            return
        }

        try {
            porcupineManager?.stop()
        } catch (error: Exception) {
            Log.w(TAG, "Failed to stop Porcupine cleanly.", error)
        } finally {
            listening = false
        }
    }

    fun isListening(): Boolean = listening

    fun dispose() {
        stopListening()
        porcupineManager?.delete()
        porcupineManager = null
    }

    private fun buildPorcupineManager(): PorcupineManager =
        PorcupineManager.Builder()
            .setAccessKey(PICOVOICE_ACCESS_KEY)
            .setKeyword(Porcupine.BuiltInKeyword.PORCUPINE)
            .setSensitivity(DEFAULT_SENSITIVITY)
            .build(context) { keywordIndex ->
                if (keywordIndex >= 0) {
                    onWakeWordDetected()
                }
            }

    companion object {
        private const val TAG = "OpenReefWakeWord"
        private const val DEFAULT_SENSITIVITY = 0.7f
        private const val PICOVOICE_PLACEHOLDER_KEY =
            "PASTE_YOUR_PICOVOICE_ACCESS_KEY_HERE"

        // Paste your Picovoice access key here before enabling wake-word audio.
        private const val PICOVOICE_ACCESS_KEY = PICOVOICE_PLACEHOLDER_KEY
    }
}
