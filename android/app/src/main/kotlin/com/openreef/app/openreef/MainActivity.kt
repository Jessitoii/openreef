package com.openreef.app.openreef

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Bundle
import android.provider.ContactsContract
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.openreef.app.openreef.mcp.OpenReefSecureStore
import com.openreef.app.openreef.service.OpenReefForegroundService
import com.openreef.app.openreef.triggers.TriggerChannelBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private var nativeToolsChannel: MethodChannel? = null
    private var deviceStatsChannel: MethodChannel? = null
    private var wakeWordChannel: MethodChannel? = null
    private var wakeWordEventChannel: EventChannel? = null
    private var mcpSecretStoreChannel: MethodChannel? = null
    private var mcpOAuthBridgeChannel: MethodChannel? = null
    private var pendingOAuthCallbackUri: String? = null
    private val permissionCallbacks = mutableMapOf<Int, (Boolean) -> Unit>()
    private var nextPermissionRequestCode = 2000

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        TriggerChannelBridge.registerGlobalPollingWork(applicationContext)
        captureOAuthCallbackFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TriggerChannelBridge.attachToFlutterEngine(applicationContext, flutterEngine)
        if (nativeToolsChannel == null) {
            nativeToolsChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    NATIVE_TOOLS_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "setVolumeLevel" ->
                                handleSetVolumeLevel(call.argument<Double>("level"), result)
                            "getBatteryInfo" -> handleGetBatteryInfo(result)
                            "showNotification" ->
                                handleShowNotification(
                                    title = call.argument<String>("title"),
                                    body = call.argument<String>("body"),
                                    result = result,
                                )
                            "openApp" ->
                                handleOpenApp(
                                    packageName = call.argument<String>("packageName"),
                                    result = result,
                                )
                            "shareText" ->
                                handleShareText(
                                    text = call.argument<String>("text"),
                                    subject = call.argument<String>("subject"),
                                    result = result,
                                )
                            "queryContacts" ->
                                handleQueryContacts(
                                    query = call.argument<String>("query"),
                                    limit = call.argument<Int>("limit") ?: 5,
                                    result = result,
                                )
                            "createContact" ->
                                handleCreateContact(
                                    displayName = call.argument<String>("displayName"),
                                    phone = call.argument<String>("phone"),
                                    email = call.argument<String>("email"),
                                    result = result,
                                )
                            "openSmsDraft" ->
                                handleOpenSmsDraft(
                                    to = call.argument<String>("to"),
                                    body = call.argument<String>("body"),
                                    result = result,
                                )
                            "openEmailDraft" ->
                                handleOpenEmailDraft(
                                    to = call.argument<String>("to"),
                                    subject = call.argument<String>("subject"),
                                    body = call.argument<String>("body"),
                                    result = result,
                                )
                            "setFlashlightEnabled" ->
                                handleSetFlashlightEnabled(
                                    enabled = call.argument<Boolean>("enabled"),
                                    result = result,
                                )
                            "setDndMode" ->
                                handleSetDndMode(
                                    mode = call.argument<String>("mode"),
                                    result = result,
                                )
                            "getCurrentLocation" ->
                                handleGetCurrentLocation(
                                    highAccuracy = call.argument<Boolean>("highAccuracy") ?: false,
                                    result = result,
                                )
                            "openMapsNavigate" ->
                                handleOpenMapsNavigate(
                                    query = call.argument<String>("query"),
                                    result = result,
                                )
                            else -> result.notImplemented()
                        }
                    }
                }
        }
        if (deviceStatsChannel == null) {
            deviceStatsChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    DEVICE_STATS_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "getDeviceStats" -> handleGetDeviceStats(result)
                            else -> result.notImplemented()
                        }
                    }
                }
        }
        if (wakeWordChannel == null) {
            wakeWordChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    WAKE_WORD_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "startListening" -> result.success(handleStartWakeWord())
                            "stopListening" -> result.success(handleStopWakeWord())
                            "isListening" -> result.success(OpenReefForegroundService.isListening())
                            "isAvailable" ->
                                result.success(
                                    OpenReefForegroundService.isAvailable(applicationContext),
                                )
                            "setSensitivity" ->
                                result.success(
                                    OpenReefForegroundService.setSensitivity(
                                        call.argument<Double>("value"),
                                    ),
                                )
                            else -> result.notImplemented()
                        }
                    }
                }
        }
        if (wakeWordEventChannel == null) {
            wakeWordEventChannel =
                EventChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    WAKE_WORD_EVENT_CHANNEL_NAME,
                ).also { channel ->
                    channel.setStreamHandler(
                        object : EventChannel.StreamHandler {
                            override fun onListen(
                                arguments: Any?,
                                events: EventChannel.EventSink?,
                            ) {
                                OpenReefForegroundService.attachEventSink(events)
                            }

                            override fun onCancel(arguments: Any?) {
                                OpenReefForegroundService.attachEventSink(null)
                            }
                        },
                    )
                }
        }
        if (mcpSecretStoreChannel == null) {
            mcpSecretStoreChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    MCP_SECRET_STORE_CHANNEL_NAME,
                ).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        OpenReefSecureStore.handleMethodCall(applicationContext, call, result)
                    }
                }
        }
        if (mcpOAuthBridgeChannel == null) {
            mcpOAuthBridgeChannel =
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "openreef/mcp_oauth_bridge",
                )
        }
        dispatchPendingOAuthCallback()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOAuthCallbackFromIntent(intent)
        dispatchPendingOAuthCallback()
    }

    override fun onDestroy() {
        nativeToolsChannel?.setMethodCallHandler(null)
        nativeToolsChannel = null
        deviceStatsChannel?.setMethodCallHandler(null)
        deviceStatsChannel = null
        wakeWordChannel?.setMethodCallHandler(null)
        wakeWordChannel = null
        wakeWordEventChannel?.setStreamHandler(null)
        wakeWordEventChannel = null
        mcpSecretStoreChannel?.setMethodCallHandler(null)
        mcpSecretStoreChannel = null
        mcpOAuthBridgeChannel = null
        OpenReefForegroundService.attachEventSink(null)
        super.onDestroy()
    }

    private fun captureOAuthCallbackFromIntent(intent: Intent?) {
        val dataString = intent?.dataString ?: return
        val uri = Uri.parse(dataString)
        if (uri.scheme != "openreef" || uri.host != "oauth") {
            return
        }
        pendingOAuthCallbackUri = dataString
    }

    private fun dispatchPendingOAuthCallback() {
        val channel = mcpOAuthBridgeChannel ?: return
        val callbackUri = pendingOAuthCallbackUri ?: return
        pendingOAuthCallbackUri = null
        channel.invokeMethod(
            "oauthCallback",
            mapOf(
                "uri" to callbackUri,
                "source" to "android_intent",
            ),
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val callback = permissionCallbacks.remove(requestCode) ?: return
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        callback(granted)
    }

    private fun handleSetVolumeLevel(level: Double?, result: MethodChannel.Result) {
        if (level == null) {
            fail(result, "invalid_arguments", "Missing required argument: level.")
            return
        }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            fail(result, "operation_failed", "AudioManager unavailable.")
            return
        }

        val normalizedLevel = level.coerceIn(0.0, 1.0)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = (normalizedLevel * maxVolume).toInt().coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)

        val appliedVolume =
            if (maxVolume == 0) 0.0 else targetVolume.toDouble() / maxVolume.toDouble()
        result.success(appliedVolume)
    }

    private fun handleGetBatteryInfo(result: MethodChannel.Result) {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        if (batteryManager == null) {
            fail(result, "operation_failed", "BatteryManager unavailable.")
            return
        }

        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        val state =
            when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                BatteryManager.BATTERY_STATUS_FULL -> "full"
                BatteryManager.BATTERY_STATUS_DISCHARGING,
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "discharging"
                else -> "unknown"
            }

        result.success(
            mapOf(
                "level" to level,
                "state" to state,
                "isLowPowerMode" to false,
            ),
        )
    }

    private fun handleShowNotification(
        title: String?,
        body: String?,
        result: MethodChannel.Result,
    ) {
        if (title.isNullOrBlank() || body.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required notification title or body.")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            fail(
                result,
                "permission_required",
                "Notification permission is required to post reminders.",
            )
            return
        }
        val manager = NotificationManagerCompat.from(this)
        ensureNotificationChannel()
        val notificationId = System.currentTimeMillis().toInt()
        val notification =
            NotificationCompat
                .Builder(this, REMINDER_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title.trim())
                .setContentText(body.trim())
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
        manager.notify(notificationId, notification)
        result.success(
            mapOf(
                "notificationId" to notificationId,
                "dispatchedAt" to java.time.Instant.now().toString(),
            ),
        )
    }

    private fun handleOpenApp(
        packageName: String?,
        result: MethodChannel.Result,
    ) {
        if (packageName.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required argument: packageName.")
            return
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName.trim())
        if (launchIntent == null) {
            fail(result, "app_unavailable", "The requested package is not installed.")
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(launchIntent)
            result.success(mapOf("opened" to true))
        } catch (error: Exception) {
            fail(result, "operation_failed", "Unable to open the requested app.")
        }
    }

    private fun handleShareText(
        text: String?,
        subject: String?,
        result: MethodChannel.Result,
    ) {
        if (text.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required argument: text.")
            return
        }
        val shareIntent =
            Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                if (!subject.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                }
            }
        val chooser =
            Intent.createChooser(shareIntent, "Share with").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        launchExternalIntent(
            intent = chooser,
            unavailableMessage = "No app is available for sharing this content.",
            result = result,
        )
    }

    private fun handleQueryContacts(
        query: String?,
        limit: Int,
        result: MethodChannel.Result,
    ) {
        withPermissions(arrayOf(Manifest.permission.READ_CONTACTS), result) {
            val contacts = queryContacts(query = query, limit = limit.coerceIn(1, 20))
            result.success(mapOf("results" to contacts))
        }
    }

    private fun handleCreateContact(
        displayName: String?,
        phone: String?,
        email: String?,
        result: MethodChannel.Result,
    ) {
        if (displayName.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required argument: displayName.")
            return
        }
        withPermissions(arrayOf(Manifest.permission.WRITE_CONTACTS), result) {
            val created = createContact(displayName.trim(), phone?.trim(), email?.trim())
            if (created == null) {
                fail(result, "operation_failed", "The contact could not be created.")
            } else {
                result.success(created)
            }
        }
    }

    private fun handleOpenSmsDraft(
        to: String?,
        body: String?,
        result: MethodChannel.Result,
    ) {
        val uri =
            if (to.isNullOrBlank()) {
                Uri.parse("smsto:")
            } else {
                Uri.parse("smsto:${Uri.encode(to)}")
            }
        val intent =
            Intent(Intent.ACTION_SENDTO, uri).apply {
                putExtra("sms_body", body ?: "")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        launchExternalIntent(
            intent = intent,
            unavailableMessage = "No SMS app is available for drafting messages.",
            result = result,
        )
    }

    private fun handleOpenEmailDraft(
        to: String?,
        subject: String?,
        body: String?,
        result: MethodChannel.Result,
    ) {
        val builder = Uri.parse("mailto:").buildUpon()
        if (!to.isNullOrBlank()) {
            builder.appendQueryParameter("to", to)
        }
        if (!subject.isNullOrBlank()) {
            builder.appendQueryParameter("subject", subject)
        }
        if (!body.isNullOrBlank()) {
            builder.appendQueryParameter("body", body)
        }
        val intent =
            Intent(Intent.ACTION_SENDTO, builder.build()).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        launchExternalIntent(
            intent = intent,
            unavailableMessage = "No email app is available for drafting mail.",
            result = result,
        )
    }

    private fun handleSetFlashlightEnabled(enabled: Boolean?, result: MethodChannel.Result) {
        if (enabled == null) {
            fail(result, "invalid_arguments", "Missing required argument: enabled.")
            return
        }
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        if (cameraManager == null) {
            fail(result, "feature_unavailable", "CameraManager unavailable.")
            return
        }
        val cameraId =
            cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        if (cameraId == null) {
            fail(result, "feature_unavailable", "This device does not have a flashlight.")
            return
        }
        try {
            cameraManager.setTorchMode(cameraId, enabled)
            result.success(mapOf("enabled" to enabled))
        } catch (error: Exception) {
            fail(result, "operation_failed", "Unable to change flashlight state.")
        }
    }

    private fun handleSetDndMode(mode: String?, result: MethodChannel.Result) {
        if (mode.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required argument: mode.")
            return
        }
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (notificationManager == null) {
            fail(result, "operation_failed", "NotificationManager unavailable.")
            return
        }
        if (!notificationManager.isNotificationPolicyAccessGranted) {
            fail(
                result,
                "permission_required",
                "Notification policy access is required to change Do Not Disturb.",
            )
            return
        }
        val interruptionFilter =
            when (mode) {
                "all" -> NotificationManager.INTERRUPTION_FILTER_ALL
                "priority_only" -> NotificationManager.INTERRUPTION_FILTER_PRIORITY
                "alarms_only" -> NotificationManager.INTERRUPTION_FILTER_ALARMS
                "none" -> NotificationManager.INTERRUPTION_FILTER_NONE
                else -> {
                    fail(result, "invalid_arguments", "Unsupported DND mode: $mode.")
                    return
                }
            }
        notificationManager.setInterruptionFilter(interruptionFilter)
        result.success(mapOf("mode" to mode))
    }

    private fun handleGetCurrentLocation(
        highAccuracy: Boolean,
        result: MethodChannel.Result,
    ) {
        withPermissions(
            arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ),
            result,
        ) {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            if (locationManager == null) {
                fail(result, "operation_failed", "LocationManager unavailable.")
                return@withPermissions
            }
            val providers =
                buildList {
                    if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                        add(LocationManager.GPS_PROVIDER)
                    }
                    if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                        add(LocationManager.NETWORK_PROVIDER)
                    }
                    if (locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                        add(LocationManager.PASSIVE_PROVIDER)
                    }
                }
            if (providers.isEmpty()) {
                fail(result, "operation_failed", "Location providers are disabled.")
                return@withPermissions
            }
            val lastKnown =
                providers
                    .mapNotNull { provider ->
                        runCatching { locationManager.getLastKnownLocation(provider) }.getOrNull()
                    }.maxByOrNull { location ->
                        location.time
                    }
            if (lastKnown != null) {
                result.success(locationToMap(lastKnown))
                return@withPermissions
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val provider =
                    if (highAccuracy && providers.contains(LocationManager.GPS_PROVIDER)) {
                        LocationManager.GPS_PROVIDER
                    } else {
                        providers.first()
                    }
                val executor: Executor = mainExecutor
                locationManager.getCurrentLocation(
                    provider,
                    CancellationSignal(),
                    executor,
                ) { location ->
                    if (location == null) {
                        fail(result, "operation_failed", "No current location fix is available.")
                    } else {
                        result.success(locationToMap(location))
                    }
                }
            } else {
                fail(result, "operation_failed", "No current location fix is available.")
            }
        }
    }

    private fun handleOpenMapsNavigate(query: String?, result: MethodChannel.Result) {
        if (query.isNullOrBlank()) {
            fail(result, "invalid_arguments", "Missing required argument: query.")
            return
        }
        val intent =
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("google.navigation:q=${Uri.encode(query.trim())}"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        launchExternalIntent(
            intent = intent,
            unavailableMessage = "No navigation app is available for this destination.",
            result = result,
        )
    }

    private fun handleGetDeviceStats(result: MethodChannel.Result) {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (activityManager == null) {
            fail(result, "operation_failed", "ActivityManager unavailable.")
            return
        }
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val freeRamGb = memoryInfo.availMem.toDouble() / (1024.0 * 1024.0 * 1024.0)
        result.success(
            mapOf(
                "freeRamGb" to freeRamGb,
                "npuReady" to false,
            ),
        )
    }

    private fun handleStartWakeWord(): Boolean =
        OpenReefForegroundService.requestStart(applicationContext)

    private fun handleStopWakeWord(): Boolean =
        OpenReefForegroundService.requestStop(applicationContext)

    private fun queryContacts(
        query: String?,
        limit: Int,
    ): List<Map<String, Any?>> {
        val resolver = contentResolver
        val selection =
            if (query.isNullOrBlank()) {
                null
            } else {
                "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} LIKE ?"
            }
        val selectionArgs =
            if (query.isNullOrBlank()) {
                null
            } else {
                arrayOf("%${query.trim()}%")
            }
        val cursor =
            resolver.query(
                ContactsContract.Contacts.CONTENT_URI,
                arrayOf(
                    ContactsContract.Contacts._ID,
                    ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
                ),
                selection,
                selectionArgs,
                "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} COLLATE LOCALIZED ASC",
            ) ?: return emptyList()

        cursor.use { contactsCursor ->
            val results = mutableListOf<Map<String, Any?>>()
            val idIndex = contactsCursor.getColumnIndexOrThrow(ContactsContract.Contacts._ID)
            val nameIndex =
                contactsCursor.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
            while (contactsCursor.moveToNext() && results.size < limit) {
                val contactId = contactsCursor.getLong(idIndex)
                val displayName = contactsCursor.getString(nameIndex) ?: continue
                results.add(
                    mapOf(
                        "displayName" to displayName,
                        "phoneNumbers" to queryPhoneNumbers(contactId),
                        "emailAddresses" to queryEmailAddresses(contactId),
                    ),
                )
            }
            return results
        }
    }

    private fun createContact(
        displayName: String,
        phone: String?,
        email: String?,
    ): Map<String, Any?>? {
        val operations = arrayListOf<ContentProviderOperation>()
        operations.add(
            ContentProviderOperation
                .newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                .build(),
        )
        operations.add(
            ContentProviderOperation
                .newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
                ).withValue(
                    ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME,
                    displayName,
                ).build(),
        )
        if (!phone.isNullOrBlank()) {
            operations.add(
                ContentProviderOperation
                    .newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                    ).withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
                    .withValue(
                        ContactsContract.CommonDataKinds.Phone.TYPE,
                        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE,
                    ).build(),
            )
        }
        if (!email.isNullOrBlank()) {
            operations.add(
                ContentProviderOperation
                    .newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE,
                    ).withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, email)
                    .withValue(
                        ContactsContract.CommonDataKinds.Email.TYPE,
                        ContactsContract.CommonDataKinds.Email.TYPE_WORK,
                    ).build(),
            )
        }
        return try {
            val results =
                contentResolver.applyBatch(ContactsContract.AUTHORITY, operations)
            val rawContactUri = results.firstOrNull()?.uri ?: return null
            val rawContactId = ContentUris.parseId(rawContactUri)
            val contactId = queryContactIdForRawContact(rawContactId) ?: return null
            mapOf(
                "displayName" to displayName,
                "phoneNumbers" to listOfNotNull(phone?.takeIf { it.isNotBlank() }),
                "emailAddresses" to listOfNotNull(email?.takeIf { it.isNotBlank() }),
                "contactId" to contactId,
            )
        } catch (error: Exception) {
            null
        }
    }

    private fun queryContactIdForRawContact(rawContactId: Long): Long? {
        val cursor =
            contentResolver.query(
                ContactsContract.RawContacts.CONTENT_URI,
                arrayOf(ContactsContract.RawContacts.CONTACT_ID),
                "${ContactsContract.RawContacts._ID} = ?",
                arrayOf(rawContactId.toString()),
                null,
            ) ?: return null
        cursor.use {
            if (!it.moveToFirst()) {
                return null
            }
            return it.getLong(
                it.getColumnIndexOrThrow(ContactsContract.RawContacts.CONTACT_ID),
            )
        }
    }

    private fun queryPhoneNumbers(contactId: Long): List<String> {
        val cursor =
            contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
                arrayOf(contactId.toString()),
                null,
            ) ?: return emptyList()
        cursor.use {
            val numbers = mutableListOf<String>()
            val index = it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (it.moveToNext()) {
                val number = it.getString(index)
                if (!number.isNullOrBlank()) {
                    numbers.add(number)
                }
            }
            return numbers.distinct()
        }
    }

    private fun queryEmailAddresses(contactId: Long): List<String> {
        val cursor =
            contentResolver.query(
                ContactsContract.CommonDataKinds.Email.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Email.ADDRESS),
                "${ContactsContract.CommonDataKinds.Email.CONTACT_ID} = ?",
                arrayOf(contactId.toString()),
                null,
            ) ?: return emptyList()
        cursor.use {
            val addresses = mutableListOf<String>()
            val index =
                it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.ADDRESS)
            while (it.moveToNext()) {
                val address = it.getString(index)
                if (!address.isNullOrBlank()) {
                    addresses.add(address)
                }
            }
            return addresses.distinct()
        }
    }

    private fun locationToMap(location: Location): Map<String, Any?> {
        val formatter =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "provider" to (location.provider ?: "unknown"),
            "timestamp" to formatter.format(Date(location.time)),
            "accuracyMeters" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
        )
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channel =
            NotificationChannel(
                REMINDER_CHANNEL_ID,
                "OpenReef Reminders",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Agent-created reminders and notifications."
            }
        notificationManager.createNotificationChannel(channel)
    }

    private fun launchExternalIntent(
        intent: Intent,
        unavailableMessage: String,
        result: MethodChannel.Result,
    ) {
        val resolved = intent.resolveActivity(packageManager)
        if (resolved == null) {
            fail(result, "app_unavailable", unavailableMessage)
            return
        }
        try {
            startActivity(intent)
            result.success(mapOf("opened" to true))
        } catch (error: Exception) {
            fail(result, "operation_failed", "Unable to open the requested app.")
        }
    }

    private fun withPermissions(
        permissions: Array<String>,
        result: MethodChannel.Result,
        onGranted: () -> Unit,
    ) {
        val missing =
            permissions.filter { permission ->
                ContextCompat.checkSelfPermission(this, permission) !=
                    PackageManager.PERMISSION_GRANTED
            }
        if (missing.isEmpty()) {
            onGranted()
            return
        }
        val requestCode = nextPermissionRequestCode++
        permissionCallbacks[requestCode] = { granted ->
            if (granted) {
                onGranted()
            } else {
                fail(
                    result,
                    "permission_denied",
                    "Required Android permission was denied.",
                    mapOf("permissions" to missing),
                )
            }
        }
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), requestCode)
    }

    private fun fail(
        result: MethodChannel.Result,
        code: String,
        message: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        result.error(
            code,
            message,
            mapOf(
                "code" to code,
                "message" to message,
                "details" to details,
            ),
        )
    }

    companion object {
        private const val NATIVE_TOOLS_CHANNEL_NAME = "openreef/native_tools"
        private const val DEVICE_STATS_CHANNEL_NAME = "openreef/device_stats"
        private const val WAKE_WORD_CHANNEL_NAME = "openreef/wake_word_channel"
        private const val WAKE_WORD_EVENT_CHANNEL_NAME = "openreef/wake_word_events"
        private const val MCP_SECRET_STORE_CHANNEL_NAME = "openreef/mcp_secret_store"
        private const val REMINDER_CHANNEL_ID = "openreef_reminders"
    }
}
