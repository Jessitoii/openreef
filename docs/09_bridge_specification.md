# 09  Bridge Specification (Flutter <-> JNI/LiteRT-LM)

The bridge between Dart (Flutter) and Kotlin (LiteRT-LM / JNI) is the most performance-critical and fragile layer of OpenReef. This document outlines the exact `MethodChannel` and `EventChannel` contracts to guarantee type safety and clear exception mapping.

## Channel Definitions
- **MethodChannel:** `openreef/litert_channel` (for commands)
- **EventChannel:** `openreef/litert_stream` (for token streaming)

## Method Mapping Table

| Dart Method (Invoke) | Kotlin Handler Function | Parameters (Dart Maps) | Return / Output |
| :--- | :--- | :--- | :--- |
| `initModel` | `loadModel(path: String, useNpu: Boolean)` | `{"path": String, "useNpu": bool}` | `bool` (success) |
| `generateStream` | `startInference(context: String)` | `{"context": String, "maxTokens": int}` | `null` (Starts EventChannel stream) |
| `stopGeneration` | `cancelInference()` | `{}` | `bool` (success) |
| `unloadModel` | `closeModel()` | `{}` | `bool` (success) |
| `getDeviceStats` | `checkRamAndNpu()` | `{}` | `{"freeram": double, "npu_ready": bool}` |
| `getInferenceStats` | `getLastRunStats()` | `{}` | `{"tps": double, "latency_ms": int}` |

## Token Streaming Event Payload (EventChannel)
Tokens are emitted from Kotlin to Dart on every generated chunk.
```json
// JSON Payload representation sent over EventChannel
{
  "chunk": " Hello",
  "isFinished": false,
  "metrics": null
}
// On completion
{
  "chunk": "",
  "isFinished": true,
  "metrics": {"total_tokens": 128, "tps": 22.4}
}
```

## Exception & Error Mapping

Exceptions thrown natively in Kotlin/C++ must be predictably handled and wrapped into Dart `PlatformException`.

| Kotlin/C++ Exception | Dart `PlatformException.code` | Dart Treatment / Agent Action |
| :--- | :--- | :--- |
| `OutOfMemoryError` | `ERR_OOM` | Trigger `CircuitBreaker`, prompt user to select smaller model. |
| `IllegalArgumentException` | `ERR_INVALID_CONTEXT` | Context budget exceeded. Trigger `FullCompact` forcefully. |
| `IllegalStateException` | `ERR_MODEL_NOT_LOADED` | Wait and retry `initModel` under the hood. |
| `LiteRtInferenceException` | `ERR_INFERENCE_FAIL` | Log failure, increment `_consecutiveErrors` in AgentLoop. |
| `NpuNotSupportedException` | `ERR_NPU_FALLBACK` | Log warning, silently fallback to `useNpu = false` (GPU/CPU). |

## Memory Management Rules (JNI)
1. **Model Persistence**: The `LiteRtLMEngine` must remain held in memory between turns unless explicitly `unloadModel` is called (to preserve KV cache).
2. **Context Cleanup**: Clear prompt strings immediately on JNI boundary cross to avoid string duplication piling up in JVM RAM.
