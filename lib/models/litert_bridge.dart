import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class LiteRtBridge {
  LiteRtBridge({
    Future<LiteRtDeviceStats?> Function()? deviceStatsProvider,
    Future<bool> Function()? memoryPressureRecovery,
  }) : _deviceStatsProvider = deviceStatsProvider,
       _memoryPressureRecovery = memoryPressureRecovery;

  static const MethodChannel _deviceStatsChannel = MethodChannel(
    'openreef/device_stats',
  );
  static const double _minimumSafeFreeRamGb = 1.2;
  static const double _minimumRecoveredFreeRamGb = 1.0;
  static const Duration _memoryPressureCooldown = Duration(seconds: 20);

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  String? _activeModelId;
  PreferredBackend? _preferredBackend;
  int _maxTokens = 1024;
  DateTime? _memoryPressureBlockedUntil;
  final Future<LiteRtDeviceStats?> Function()? _deviceStatsProvider;
  final Future<bool> Function()? _memoryPressureRecovery;
  static const List<String> _functionGemmaIdHints = <String>[
    'function',
    'mobile-actions',
  ];

  Future<bool> initModel({required String path, required bool useNpu}) async {
    try {
      debugPrint('LiteRtBridge.initModel: preparing modelId=$path');
      final hasActive = FlutterGemma.hasActiveModel();
      if (!hasActive) {
        final installed = await FlutterGemma.listInstalledModels();
        if (!installed.contains(path)) {
          debugPrint('LiteRtBridge.initModel: modelId not installed');
          throw StateError('Requested model is not installed: $path');
        }
        debugPrint(
          'LiteRtBridge.initModel: no active model, using installed model',
        );
      }

      _preferredBackend = _resolvePreferredBackend(
        modelId: path,
        useNpu: useNpu,
      );
      _activeModelId = path;
      debugPrint(
        'LiteRtBridge.initModel: getActiveModel backend=$_preferredBackend maxTokens=$_maxTokens',
      );
      _activeModel = await FlutterGemma.getActiveModel(
        preferredBackend: _preferredBackend,
        maxTokens: _maxTokens,
      );
      debugPrint('LiteRtBridge.initModel: active model ready');
      return true;
    } catch (_) {
      debugPrint('LiteRtBridge.initModel: failed');
      rethrow;
    }
  }

  PreferredBackend _resolvePreferredBackend({
    required String modelId,
    required bool useNpu,
  }) {
    if (useNpu) {
      return PreferredBackend.npu;
    }
    final lower = modelId.toLowerCase();
    for (final hint in _functionGemmaIdHints) {
      if (lower.contains(hint)) {
        debugPrint(
          'LiteRtBridge.initModel: forcing CPU backend for FunctionGemma modelId=$modelId',
        );
        return PreferredBackend.cpu;
      }
    }
    return PreferredBackend.gpu;
  }

  Stream<LiteRtGenerationEvent> generateStream({
    required String context,
    required int maxTokens,
  }) {
    if (_activeModel == null) {
      throw StateError('Model is not initialized.');
    }

    final controller = StreamController<LiteRtGenerationEvent>();
    var emittedVisibleText = false;
    var emittedToolCall = false;

    () async {
      try {
        await _guardGenerationStart();

        if (maxTokens != _maxTokens) {
          _maxTokens = maxTokens;
          debugPrint(
            'LiteRtBridge.generateStream: refresh model for maxTokens=$_maxTokens',
          );
          _activeModel = await FlutterGemma.getActiveModel(
            preferredBackend: _preferredBackend,
            maxTokens: _maxTokens,
          );
        }

        await _disposeActiveChat();
        debugPrint('LiteRtBridge.generateStream: createChat');
        _activeChat = await _activeModel!.createChat(
          supportsFunctionCalls: true,
          toolChoice: ToolChoice.auto,
        );
        debugPrint('LiteRtBridge.generateStream: addQueryChunk');
        await _activeChat!.addQueryChunk(
          Message.text(text: context, isUser: true),
        );

        debugPrint(
          'LiteRtBridge.generateStream: start generateChatResponseAsync',
        );
        _activeChat!.generateChatResponseAsync().listen(
          (ModelResponse response) {
            if (response is TextResponse) {
              if (response.token.trim().isNotEmpty) {
                emittedVisibleText = true;
              }
              controller.add(
                LiteRtGenerationEvent(chunk: response.token, isFinished: false),
              );
              return;
            }

            if (response is FunctionCallResponse) {
              emittedToolCall = true;
              debugPrint(
                'LiteRtBridge.generateStream: function call ${response.name} args=${jsonEncode(response.args)}',
              );
              controller.add(
                LiteRtGenerationEvent(
                  chunk: jsonEncode(<String, Object?>{
                    'tool_call': <String, Object?>{
                      'id': 'fg_${DateTime.now().microsecondsSinceEpoch}',
                      'tool_id': response.name,
                      'arguments': response.args,
                    },
                  }),
                  isFinished: false,
                ),
              );
              return;
            }

            if (response is ThinkingResponse) {
              debugPrint(
                'LiteRtBridge.generateStream: thinking token ${response.content}',
              );
            }
          },
          onDone: () {
            debugPrint('LiteRtBridge.generateStream: generation done');
            if (!emittedVisibleText &&
                !emittedToolCall &&
                _isFunctionGemmaModel(_activeModelId)) {
              controller.add(
                const LiteRtGenerationEvent(
                  chunk:
                      'The selected FunctionGemma model is tool-calling oriented and did not produce a visible reply for this message. Try a tool-eligible request or switch to a general chat model.',
                  isFinished: false,
                ),
              );
            }
            controller.add(
              const LiteRtGenerationEvent(chunk: '', isFinished: true),
            );
            unawaited(_disposeActiveChat());
            controller.close();
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('LiteRtBridge.generateStream: generation error $error');
            unawaited(_disposeActiveChat());
            controller.addError(error, stackTrace);
            controller.close();
          },
        );
      } catch (error, stackTrace) {
        debugPrint('LiteRtBridge.generateStream: setup error $error');
        await _disposeActiveChat();
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }();

    return controller.stream;
  }

  bool _isFunctionGemmaModel(String? modelId) {
    if (modelId == null) {
      return false;
    }
    final lower = modelId.toLowerCase();
    return _functionGemmaIdHints.any(lower.contains);
  }

  Future<bool> stopGeneration() async {
    final chat = _activeChat;
    if (chat == null) {
      return false;
    }
    await chat.stopGeneration();
    await _disposeActiveChat();
    return true;
  }

  Future<bool> unloadModel() async {
    await _disposeActiveChat();
    await _activeModel?.close();
    _activeModel = null;
    _memoryPressureBlockedUntil = null;
    return true;
  }

  Future<LiteRtDeviceStats?> getDeviceStats() async {
    try {
      final deviceStatsProvider = _deviceStatsProvider;
      final result = deviceStatsProvider != null
          ? await deviceStatsProvider()
          : await _readDeviceStatsFromChannel();
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  Future<LiteRtDeviceStats?> _readDeviceStatsFromChannel() async {
    final result = await _deviceStatsChannel
        .invokeMethod<Map<Object?, Object?>>('getDeviceStats');
    if (result == null) {
      return null;
    }
    final freeRam =
        (result['freeRamGb'] as num?)?.toDouble() ??
        (result['freeram'] as num?)?.toDouble();
    final npuReady =
        result['npuReady'] as bool? ?? result['npu_ready'] as bool?;
    if (freeRam == null || npuReady == null) {
      return null;
    }
    return LiteRtDeviceStats(freeRam: freeRam, npuReady: npuReady);
  }

  Future<void> _guardGenerationStart() async {
    final blockedUntil = _memoryPressureBlockedUntil;
    final now = DateTime.now();
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      final remaining = blockedUntil.difference(now).inSeconds + 1;
      throw LiteRtCrashShieldException(
        'Low free RAM detected. Wait about $remaining seconds before sending another message.',
      );
    }

    final stats = await getDeviceStats();
    if (stats == null) {
      return;
    }
    if (stats.freeRam >= _minimumSafeFreeRamGb) {
      _memoryPressureBlockedUntil = null;
      return;
    }

    final recovered = await _attemptMemoryPressureRecovery();
    if (recovered) {
      final recoveredStats = await getDeviceStats();
      if (recoveredStats == null) {
        _memoryPressureBlockedUntil = null;
        return;
      }
      if (recoveredStats.freeRam >= _minimumRecoveredFreeRamGb) {
        _memoryPressureBlockedUntil = null;
        return;
      }
      debugPrint(
        'LiteRtBridge._guardGenerationStart: recovery completed but free RAM is still low (${recoveredStats.freeRam.toStringAsFixed(2)} GB)',
      );
    }

    _memoryPressureBlockedUntil = now.add(_memoryPressureCooldown);
    throw LiteRtCrashShieldException(
      'OpenReef paused generation to avoid a crash. Free RAM is ${stats.freeRam.toStringAsFixed(2)} GB after recovery attempts; at least ${_minimumSafeFreeRamGb.toStringAsFixed(1)} GB is preferred.',
    );
  }

  Future<bool> _attemptMemoryPressureRecovery() async {
    debugPrint(
      'LiteRtBridge._attemptMemoryPressureRecovery: low RAM detected, attempting cleanup',
    );

    final recoveryOverride = _memoryPressureRecovery;
    if (recoveryOverride != null) {
      return recoveryOverride();
    }

    await _disposeActiveChat();

    final modelId = _activeModelId;
    if (modelId == null) {
      return false;
    }

    final currentBackend = _preferredBackend;
    final nextBackend = switch (currentBackend) {
      PreferredBackend.gpu => PreferredBackend.cpu,
      PreferredBackend.npu => PreferredBackend.gpu,
      _ => currentBackend,
    };

    try {
      await _activeModel?.close();
      _activeModel = null;
    } catch (error) {
      debugPrint(
        'LiteRtBridge._attemptMemoryPressureRecovery: failed to close model $error',
      );
    }

    try {
      _preferredBackend = nextBackend;
      debugPrint(
        'LiteRtBridge._attemptMemoryPressureRecovery: reloading modelId=$modelId backend=$_preferredBackend',
      );
      _activeModel = await FlutterGemma.getActiveModel(
        preferredBackend: _preferredBackend,
        maxTokens: _maxTokens,
      );
      return true;
    } catch (error) {
      debugPrint(
        'LiteRtBridge._attemptMemoryPressureRecovery: reload failed $error',
      );
      _preferredBackend = currentBackend;
      return false;
    }
  }

  Future<void> _disposeActiveChat() async {
    final chat = _activeChat;
    _activeChat = null;
    if (chat == null) {
      return;
    }
    try {
      await chat.close();
    } catch (error) {
      debugPrint(
        'LiteRtBridge._disposeActiveChat: failed to close chat $error',
      );
    }
  }

  Future<LiteRtInferenceStats> getInferenceStats() async {
    return const LiteRtInferenceStats(tps: 0, latencyMs: 0);
  }
}

class LiteRtCrashShieldException implements Exception {
  const LiteRtCrashShieldException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiteRtGenerationEvent {
  const LiteRtGenerationEvent({
    required this.chunk,
    required this.isFinished,
    this.metrics,
  });

  final String chunk;
  final bool isFinished;
  final LiteRtGenerationMetrics? metrics;
}

class LiteRtGenerationMetrics {
  const LiteRtGenerationMetrics({required this.totalTokens, required this.tps});

  final int totalTokens;
  final double tps;
}

class LiteRtDeviceStats {
  const LiteRtDeviceStats({required this.freeRam, required this.npuReady});

  final double freeRam;
  final bool npuReady;
}

class LiteRtInferenceStats {
  const LiteRtInferenceStats({required this.tps, required this.latencyMs});

  final double tps;
  final int latencyMs;
}
