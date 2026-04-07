package com.openreef.app.openreef.mcp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

internal object OpenReefSecureStore {
    private const val prefsName = "openreef.mcp.secure_store"
    private const val keyAlias = "openreef_mcp_master_key"
    private const val transformation = "AES/GCM/NoPadding"
    private const val ivLengthBytes = 12
    private const val tagLengthBits = 128

    fun handleMethodCall(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "writeSecret" -> {
                    val key =
                        call.argument<String>("key")
                            ?: return result.error(
                                "ERR_INVALID_ARGS",
                                "Missing required argument: key",
                                null,
                            )
                    val value =
                        call.argument<String>("value")
                            ?: return result.error(
                                "ERR_INVALID_ARGS",
                                "Missing required argument: value",
                                null,
                            )
                    writeSecret(context, key, value)
                    result.success(null)
                }
                "readSecret" -> {
                    val key =
                        call.argument<String>("key")
                            ?: return result.error(
                                "ERR_INVALID_ARGS",
                                "Missing required argument: key",
                                null,
                            )
                    result.success(readSecret(context, key))
                }
                "deleteSecret" -> {
                    val key =
                        call.argument<String>("key")
                            ?: return result.error(
                                "ERR_INVALID_ARGS",
                                "Missing required argument: key",
                                null,
                            )
                    deleteSecret(context, key)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("ERR_SECURE_STORE", error.message, null)
        }
    }

    private fun writeSecret(
        context: Context,
        key: String,
        value: String,
    ) {
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val ciphertext = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val payload =
            JSONObject()
                .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                .toString()
        context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(key, payload)
            .apply()
    }

    private fun readSecret(
        context: Context,
        key: String,
    ): String? {
        val raw =
            context
                .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(key, null) ?: return null
        val payload = JSONObject(raw)
        val iv = Base64.decode(payload.getString("iv"), Base64.NO_WRAP)
        if (iv.size != ivLengthBytes) {
            throw IllegalStateException("Invalid secure-store IV size.")
        }
        val ciphertext = Base64.decode(payload.getString("ciphertext"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance(transformation)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(tagLengthBits, iv),
        )
        val plaintext = cipher.doFinal(ciphertext)
        return String(plaintext, StandardCharsets.UTF_8)
    }

    private fun deleteSecret(
        context: Context,
        key: String,
    ) {
        context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .remove(key)
            .apply()
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null)
        if (existing is SecretKey) {
            return existing
        }

        val keyGenerator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec =
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }
}
