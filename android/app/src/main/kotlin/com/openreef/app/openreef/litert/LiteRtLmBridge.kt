package com.openreef.app.openreef.litert

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future

class LiteRtLmBridge(
    messenger: BinaryMessenger,
    private val engine: LiteRtLmEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel =
        MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel =
        EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var generationTask: Future<*>? = null

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

        runCatching { engine.loadModel(path, useNpu) }
            .onSuccess(result::success)
            .onFailure { throwable -> result.fromThrowable(throwable) }
    }

    private fun handleGenerateStream(call: MethodCall, result: MethodChannel.Result) {
        val promptArg =
            call.argument<String>("context")
                ?: return result.error(
                    ErrorCodes.INVALID_CONTEXT,
                    "Missing required argument: context",
                    null,
                )
        val maxTokens =
            call.argument<Int>("maxTokens")
                ?: return result.error(
                    ErrorCodes.INVALID_CONTEXT,
                    "Missing required argument: maxTokens",
                    null,
                )

        synchronized(this) {
            if (generationTask?.isDone == false) {
                result.error(
                    ErrorCodes.INFERENCE_FAIL,
                    "Generation is already in progress",
                    null,
                )
                return
            }
        }

        var prompt: String? = promptArg
        val context = prompt ?: ""
        prompt = null

        val task =
            executor.submit {
                runCatching {
                    engine.startInference(
                        context = context,
                        maxTokens = maxTokens,
                        onToken = { chunk ->
                            emitEvent(
                                chunk = chunk,
                                isFinished = false,
                                metrics = null,
                            )
                        },
                    )
                }.onSuccess { metrics ->
                    emitEvent(
                        chunk = "",
                        isFinished = true,
                        metrics =
                            mapOf(
                                "total_tokens" to metrics.totalTokens,
                                "tps" to metrics.tps,
                            ),
                    )
                }.onFailure { throwable ->
                    eventSink?.error(
                        throwable.toFlutterCode(),
                        throwable.message,
                        null,
                    )
                }
            }

        synchronized(this) {
            generationTask = task
        }
        result.success(null)
    }

    private fun handleStopGeneration(result: MethodChannel.Result) {
        runCatching {
            synchronized(this) {
                generationTask?.cancel(true)
                generationTask = null
            }
            engine.cancelInference()
        }.onSuccess(result::success)
            .onFailure { throwable -> result.fromThrowable(throwable) }
    }

    private fun handleUnloadModel(result: MethodChannel.Result) {
        runCatching {
            synchronized(this) {
                generationTask?.cancel(true)
                generationTask = null
            }
            engine.closeModel()
        }.onSuccess(result::success)
            .onFailure { throwable -> result.fromThrowable(throwable) }
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
            generationTask?.cancel(true)
            generationTask = null
        }
        executor.shutdownNow()
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
    fun loadModel(path: String, useNpu: Boolean): Boolean

    fun startInference(
        context: String,
        maxTokens: Int,
        onToken: (String) -> Unit,
    ): LiteRtGenerationMetrics

    fun cancelInference(): Boolean

    fun closeModel(): Boolean

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

class NpuNotSupportedException(message: String) : RuntimeException(message)

class UnavailableLiteRtLmEngine : LiteRtLmEngine {
    @Volatile
    private var isLoaded = false

    @Volatile
    private var lastStats = LiteRtInferenceStats(tps = 0.0, latencyMs = 0)

    override fun loadModel(path: String, useNpu: Boolean): Boolean {
        if (useNpu) {
            throw NpuNotSupportedException(
                "NPU path is not available until the LiteRT JNI engine is wired.",
            )
        }
        if (path.isBlank()) {
            throw IllegalArgumentException("Model path cannot be blank.")
        }
        isLoaded = true
        return true
    }

    override fun startInference(
        context: String,
        maxTokens: Int,
        onToken: (String) -> Unit,
    ): LiteRtGenerationMetrics {
        if (!isLoaded) {
            throw IllegalStateException("Model is not loaded.")
        }
        if (context.isBlank()) {
            throw IllegalArgumentException("Context cannot be blank.")
        }
        if (maxTokens <= 0) {
            throw IllegalArgumentException("maxTokens must be greater than zero.")
        }

        val metrics = LiteRtGenerationMetrics(totalTokens = 0, tps = 0.0)
        lastStats = LiteRtInferenceStats(tps = metrics.tps, latencyMs = 0)
        return metrics
    }

    override fun cancelInference(): Boolean = true

    override fun closeModel(): Boolean {
        isLoaded = false
        lastStats = LiteRtInferenceStats(tps = 0.0, latencyMs = 0)
        return true
    }

    override fun checkRamAndNpu(): LiteRtDeviceStats =
        LiteRtDeviceStats(freeRam = Runtime.getRuntime().freeMemory().toDouble(), npuReady = false)

    override fun getLastRunStats(): LiteRtInferenceStats = lastStats
}

class LiteRtLmBridgePlugin : FlutterPlugin {
    private var bridge: LiteRtLmBridge? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge = LiteRtLmBridge(binding.binaryMessenger, UnavailableLiteRtLmEngine())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge?.dispose()
        bridge = null
    }
}
