package com.openreef.app.openreef.litert

import android.content.Context
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.math.max

class LiteRtLmBridge(
    messenger: BinaryMessenger,
    private val engine: LiteRtLmEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel =
        MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel =
        EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var generationJob: Job? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initModel" -> handleInitModel(call, result)
            "generateStream" -> handleGenerateStream(call, result)
            "stopGeneration" -> handleStopGeneration(result)
            "unloadModel" -> handleUnloadModel(result)
            "getDeviceStats" -> handleGetDeviceStats(result)
            "getInferenceStats" -> handleGetInferenceStats(result)
            else -> result.notImplemented()
        }
    }

    private fun handleInitModel(call: MethodCall, result: MethodChannel.Result) {
        val path =
            call.argument<String>("path")
                ?: return result.error(
                    ErrorCodes.INVALID_CONTEXT,
                    "Missing required argument: path",
                    null,
                )
        val useNpu =
            call.argument<Boolean>("useNpu")
                ?: return result.error(
                    ErrorCodes.INVALID_CONTEXT,
                    "Missing required argument: useNpu",
                    null,
                )

        scope.launch {
            runCatching { engine.loadModel(path, useNpu) }
                .onSuccess(result::success)
                .onFailure { throwable -> result.fromThrowable(throwable) }
        }
    }

    private fun handleGenerateStream(call: MethodCall, result: MethodChannel.Result) {
        val prompt =
            call.argument<String>("prompt")
                ?: call.argument<String>("context")
                ?: return result.error(
                    ErrorCodes.INVALID_CONTEXT,
                    "Missing required argument: prompt",
                    null,
                )

        synchronized(this) {
            if (generationJob?.isActive == true) {
                result.error(
                    ErrorCodes.INFERENCE_FAIL,
                    "Generation is already in progress",
                    null,
                )
                return
            }
        }

        val job =
            scope.launch {
                try {
                    val metrics =
                        engine.startInference(
                            prompt = prompt,
                            onToken = { chunk ->
                                emitEvent(
                                    chunk = chunk,
                                    isFinished = false,
                                    metrics = null,
                                )
                            },
                        )
                    emitEvent(
                        chunk = "",
                        isFinished = true,
                        metrics =
                            mapOf(
                                "total_tokens" to metrics.totalTokens,
                                "tps" to metrics.tps,
                            ),
                    )
                } catch (_: CancellationException) {
                    // stopGeneration owns explicit cancellation lifecycle.
                } catch (throwable: Throwable) {
                    eventSink?.error(
                        throwable.toFlutterCode(),
                        throwable.message,
                        null,
                    )
                } finally {
                    synchronized(this@LiteRtLmBridge) {
                        if (generationJob === this@launch) {
                            generationJob = null
                        }
                    }
                }
            }

        synchronized(this) {
            generationJob = job
        }
        result.success(null)
    }

    private fun handleStopGeneration(result: MethodChannel.Result) {
        scope.launch {
            runCatching {
                synchronized(this@LiteRtLmBridge) {
                    generationJob?.cancel()
                    generationJob = null
                }
                engine.cancelInference()
            }.onSuccess(result::success)
                .onFailure { throwable -> result.fromThrowable(throwable) }
        }
    }

    private fun handleUnloadModel(result: MethodChannel.Result) {
        scope.launch {
            runCatching {
                synchronized(this@LiteRtLmBridge) {
                    generationJob?.cancel()
                    generationJob = null
                }
                engine.closeModel()
            }.onSuccess(result::success)
                .onFailure { throwable -> result.fromThrowable(throwable) }
        }
    }

    private fun handleGetDeviceStats(result: MethodChannel.Result) {
        runCatching { engine.checkRamAndNpu() }
            .onSuccess { stats ->
                result.success(
                    mapOf(
                        "freeram" to stats.freeRam,
                        "npu_ready" to stats.npuReady,
                    ),
                )
            }.onFailure { throwable -> result.fromThrowable(throwable) }
    }

    private fun handleGetInferenceStats(result: MethodChannel.Result) {
        runCatching { engine.getLastRunStats() }
            .onSuccess { stats ->
                result.success(
                    mapOf(
                        "tps" to stats.tps,
                        "latency_ms" to stats.latencyMs,
                    ),
                )
            }.onFailure { throwable -> result.fromThrowable(throwable) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        synchronized(this) {
            generationJob?.cancel()
            generationJob = null
        }
        runBlocking {
            runCatching { engine.closeModel() }
        }
        scope.cancel()
    }

    private fun emitEvent(
        chunk: String,
        isFinished: Boolean,
        metrics: Map<String, Any?>?,
    ) {
        eventSink?.success(
            mapOf(
                "chunk" to chunk,
                "isFinished" to isFinished,
                "metrics" to metrics,
            ),
        )
    }

    private fun MethodChannel.Result.fromThrowable(throwable: Throwable) {
        error(throwable.toFlutterCode(), throwable.message, null)
    }

    private fun Throwable.toFlutterCode(): String =
        when (this) {
            is OutOfMemoryError -> ErrorCodes.OOM
            is IllegalArgumentException -> ErrorCodes.INVALID_CONTEXT
            is IllegalStateException -> ErrorCodes.MODEL_NOT_LOADED
            is LiteRtInferenceException -> ErrorCodes.INFERENCE_FAIL
            is NpuNotSupportedException -> ErrorCodes.NPU_FALLBACK
            else -> ErrorCodes.INFERENCE_FAIL
        }

    private object ErrorCodes {
        const val OOM = "ERR_OOM"
        const val INVALID_CONTEXT = "ERR_INVALID_CONTEXT"
        const val MODEL_NOT_LOADED = "ERR_MODEL_NOT_LOADED"
        const val INFERENCE_FAIL = "ERR_INFERENCE_FAIL"
        const val NPU_FALLBACK = "ERR_NPU_FALLBACK"
    }

    companion object {
        const val METHOD_CHANNEL_NAME = "openreef/litert_channel"
        const val EVENT_CHANNEL_NAME = "openreef/litert_stream"
    }
}

interface LiteRtLmEngine {
    suspend fun loadModel(path: String, useNpu: Boolean): Boolean

    suspend fun startInference(
        prompt: String,
        onToken: suspend (String) -> Unit,
    ): LiteRtGenerationMetrics

    suspend fun cancelInference(): Boolean

    suspend fun closeModel(): Boolean

    fun checkRamAndNpu(): LiteRtDeviceStats

    fun getLastRunStats(): LiteRtInferenceStats
}

data class LiteRtDeviceStats(
    val freeRam: Double,
    val npuReady: Boolean,
)

data class LiteRtInferenceStats(
    val tps: Double,
    val latencyMs: Int,
)

data class LiteRtGenerationMetrics(
    val totalTokens: Int,
    val tps: Double,
)

class LiteRtInferenceException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)

class NpuNotSupportedException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)

class LiteRtAndroidLmEngine(
    private val appContext: Context,
) : LiteRtLmEngine {
    private val stateMutex = Mutex()

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var conversation: Conversation? = null

    @Volatile
    private var lastStats = LiteRtInferenceStats(tps = 0.0, latencyMs = 0)

    override suspend fun loadModel(path: String, useNpu: Boolean): Boolean =
        withContext(Dispatchers.IO) {
            val modelFile = File(path)
            require(path.isNotBlank()) { "Model path cannot be blank." }
            require(modelFile.exists()) { "Model path does not exist: $path" }
            require(modelFile.isFile) { "Model path is not a file: $path" }

            stateMutex.withLock {
                closeLocked()

                val backend =
                    if (useNpu) {
                        Backend.NPU(nativeLibraryDir = appContext.applicationInfo.nativeLibraryDir)
                    } else {
                        Backend.GPU()
                    }

                val engineConfig =
                    EngineConfig(
                        modelPath = modelFile.absolutePath,
                        backend = backend,
                        cacheDir = appContext.cacheDir.absolutePath,
                    )

                val newEngine = Engine(engineConfig)
                try {
                    newEngine.initialize()
                    val newConversation = newEngine.createConversation()
                    engine = newEngine
                    conversation = newConversation
                    lastStats = LiteRtInferenceStats(tps = 0.0, latencyMs = 0)
                    true
                } catch (throwable: Throwable) {
                    runCatching { newEngine.close() }
                    if (useNpu) {
                        throw NpuNotSupportedException(
                            "Failed to initialize LiteRT-LM with NPU backend.",
                            throwable,
                        )
                    }
                    throw LiteRtInferenceException(
                        "Failed to initialize LiteRT-LM engine.",
                        throwable,
                    )
                }
            }
        }

    override suspend fun startInference(
        prompt: String,
        onToken: suspend (String) -> Unit,
    ): LiteRtGenerationMetrics {
        require(prompt.isNotBlank()) { "Prompt cannot be blank." }

        val activeConversation =
            stateMutex.withLock {
                conversation ?: throw IllegalStateException("Model is not loaded.")
            }

        return try {
            withContext(Dispatchers.IO) {
                val startedAt = System.nanoTime()
                var totalTokens = 0

                activeConversation.sendMessageAsync(prompt).collect { chunk ->
                    val text = chunk.toString()
                    if (text.isNotEmpty()) {
                        totalTokens += estimateTokenCount(text)
                        onToken(text)
                    }
                }

                val elapsedNanos = max(1L, System.nanoTime() - startedAt)
                val elapsedSeconds = elapsedNanos / 1_000_000_000.0
                val tps = if (totalTokens == 0) 0.0 else totalTokens / elapsedSeconds
                val latencyMs = (elapsedNanos / 1_000_000L).toInt()
                val metrics = LiteRtGenerationMetrics(totalTokens = totalTokens, tps = tps)

                stateMutex.withLock {
                    lastStats = LiteRtInferenceStats(tps = tps, latencyMs = latencyMs)
                }

                metrics
            }
        } catch (cancellation: CancellationException) {
            synchronized(this) {
                runBlocking {
                    runCatching { cancelInference() }
                }
            }
            throw cancellation
        } catch (throwable: Throwable) {
            throw LiteRtInferenceException("LiteRT-LM generation failed.", throwable)
        }
    }

    override suspend fun cancelInference(): Boolean =
        withContext(Dispatchers.IO) {
            stateMutex.withLock {
                val activeEngine = engine ?: return@withContext true
                closeConversationLocked()
                conversation = activeEngine.createConversation()
                true
            }
        }

    override suspend fun closeModel(): Boolean =
        withContext(Dispatchers.IO) {
            stateMutex.withLock {
                closeLocked()
                lastStats = LiteRtInferenceStats(tps = 0.0, latencyMs = 0)
                true
            }
        }

    override fun checkRamAndNpu(): LiteRtDeviceStats {
        val runtime = Runtime.getRuntime()
        val freeRam = runtime.maxMemory().toDouble() - (runtime.totalMemory() - runtime.freeMemory())
        val nativeLibraryDir = appContext.applicationInfo.nativeLibraryDir
        val npuReady = !nativeLibraryDir.isNullOrBlank() && File(nativeLibraryDir).exists()
        return LiteRtDeviceStats(freeRam = freeRam, npuReady = npuReady)
    }

    override fun getLastRunStats(): LiteRtInferenceStats = lastStats

    private fun closeLocked() {
        closeConversationLocked()
        closeEngineLocked()
    }

    private fun closeConversationLocked() {
        runCatching { conversation?.close() }
        conversation = null
    }

    private fun closeEngineLocked() {
        runCatching { engine?.close() }
        engine = null
    }

    private fun estimateTokenCount(text: String): Int {
        val pieces = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        return if (pieces.isEmpty()) 1 else pieces.size
    }
}

class LiteRtLmBridgePlugin : FlutterPlugin {
    private var bridge: LiteRtLmBridge? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge =
            LiteRtLmBridge(
                binding.binaryMessenger,
                LiteRtAndroidLmEngine(binding.applicationContext),
            )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge?.dispose()
        bridge = null
    }
}
