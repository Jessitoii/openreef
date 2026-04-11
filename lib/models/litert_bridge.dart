import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/models/gemma_tool_mapper.dart';

class LiteRtBridge {
  LiteRtBridge({
    Future<LiteRtDeviceStats?> Function()? deviceStatsProvider,
    Future<bool> Function()? memoryPressureRecovery,
    GemmaToolMapper toolMapper = const GemmaToolMapper(),
  }) : _deviceStatsProvider = deviceStatsProvider,
       _memoryPressureRecovery = memoryPressureRecovery,
       _toolMapper = toolMapper;

  static const MethodChannel _deviceStatsChannel = MethodChannel(
    'openreef/device_stats',
  );
  static const double _minimumSafeFreeRamGb = 1.2;
  static const double _minimumRecoveredFreeRamGb = 1.0;
  static const Duration _memoryPressureCooldown = Duration(seconds: 20);
  static const int _defaultMaxTokens = 32768;
  static const int _gemma4E2bInitMaxTokens = 4096;
  static const int _gemma4E2bRuntimeMaxTokens = 8192;

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  String? _activeModelId;
  PreferredBackend? _preferredBackend;
  int _maxTokens = _defaultMaxTokens;
  int _initTokenBudget = _defaultMaxTokens;
  int _runtimeTargetTokenBudget = _defaultMaxTokens;
  DateTime? _memoryPressureBlockedUntil;
  final Future<LiteRtDeviceStats?> Function()? _deviceStatsProvider;
  final Future<bool> Function()? _memoryPressureRecovery;
  final GemmaToolMapper _toolMapper;
  static const List<String> _functionGemmaIdHints = <String>[
    'function',
    'mobile-actions',
  ];
  static const List<String> _gemma4E2bIdHints = <String>[
    'gemma-4-e2b',
    'gemma_4_e2b',
  ];

  Future<bool> initModel({required String path, required bool useNpu}) async {
    try {
      debugPrint('LiteRtBridge.initModel: start modelId=$path');
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

      final deviceStats = await getDeviceStats();
      final preferredBackend = _resolvePreferredBackend(
        modelId: path,
        useNpu: useNpu,
        deviceStats: deviceStats,
      );
      final budgets = _selectTokenBudgets(
        modelId: path,
        preferredBackend: preferredBackend,
        deviceStats: deviceStats,
      );
      _initTokenBudget = budgets.initTokenBudget;
      _runtimeTargetTokenBudget = budgets.runtimeTargetTokenBudget;
      _maxTokens = _initTokenBudget;
      debugPrint(
        'LiteRtBridge.initModel: selected initTokenBudget=$_initTokenBudget runtimeTargetTokenBudget=$_runtimeTargetTokenBudget',
      );

      final attempts = _buildInitAttempts(
        preferredBackend: preferredBackend,
        initTokenBudget: _initTokenBudget,
        runtimeTargetTokenBudget: _runtimeTargetTokenBudget,
      );

      for (final attempt in attempts) {
        _preferredBackend = attempt.backend;
        _maxTokens = attempt.initTokenBudget;
        _activeModelId = path;
        debugPrint(
          'LiteRtBridge.initModel: attempt backend=$_preferredBackend maxTokens=$_maxTokens note=${attempt.note}',
        );
        try {
          _activeModel = await FlutterGemma.getActiveModel(
            preferredBackend: _preferredBackend,
            maxTokens: _maxTokens,
          );
          debugPrint('LiteRtBridge.initModel: active model ready');
          debugPrint(
            'LiteRtBridge.initModel: end modelId=$path backend=$_preferredBackend maxTokens=$_maxTokens',
          );
          return true;
        } catch (error) {
          debugPrint(
            'LiteRtBridge.initModel: attempt failed backend=$_preferredBackend maxTokens=$_maxTokens error=$error',
          );
          await _activeModel?.close();
          _activeModel = null;
        }
      }

      debugPrint('LiteRtBridge.initModel: failed after all fallbacks');
      throw StateError('Model initialization failed after fallbacks.');
    } catch (error) {
      debugPrint('LiteRtBridge.initModel: failed $error');
      rethrow;
    }
  }

  PreferredBackend _resolvePreferredBackend({
    required String modelId,
    required bool useNpu,
    required LiteRtDeviceStats? deviceStats,
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
    if (_isGemma4E2bModel(lower)) {
      final gpuReady = deviceStats?.gpuReady ?? false;
      if (!gpuReady) {
        debugPrint(
          'LiteRtBridge.initModel: Gemma 4 E2B requires explicit GPU readiness; defaulting to CPU',
        );
        return PreferredBackend.cpu;
      }
    }
    return PreferredBackend.gpu;
  }

  Stream<LiteRtGenerationEvent> generateStream({
    required String context,
    required int maxTokens,
    List<ToolDefinition> selectedTools = const <ToolDefinition>[],
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

        final effectiveMaxTokens = math.min(
          maxTokens,
          _runtimeTargetTokenBudget,
        );
        if (effectiveMaxTokens != _maxTokens) {
          _maxTokens = effectiveMaxTokens;
          debugPrint(
            'LiteRtBridge.generateStream: refresh model for maxTokens=$_maxTokens',
          );
          _activeModel = await FlutterGemma.getActiveModel(
            preferredBackend: _preferredBackend,
            maxTokens: _maxTokens,
          );
        }

        final toolConfig = buildToolCallConfig(selectedTools);
        await _disposeActiveChat();
        debugPrint(
          'LiteRtBridge.generateStream: createChat tools=${toolConfig.tools.length} supportsFunctionCalls=${toolConfig.supportsFunctionCalls}',
        );
        _activeChat = await _activeModel!.createChat(
          tools: toolConfig.tools,
          supportsFunctionCalls: toolConfig.supportsFunctionCalls,
          toolChoice: toolConfig.toolChoice,
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

            if (response is ParallelFunctionCallResponse) {
              emittedToolCall = true;
              final calls = response.calls;
              debugPrint(
                'LiteRtBridge.generateStream: parallel function calls count=${calls.length}',
              );
              controller.add(
                LiteRtGenerationEvent(
                  chunk: jsonEncode(<String, Object?>{
                    'tool_calls': <Map<String, Object?>>[
                      for (var index = 0; index < calls.length; index += 1)
                        <String, Object?>{
                          'id':
                              'fg_${DateTime.now().microsecondsSinceEpoch}_$index',
                          'tool_id': calls[index].name,
                          'arguments': calls[index].args,
                        },
                    ],
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

  LiteRtToolCallConfig buildToolCallConfig(List<ToolDefinition> selectedTools) {
    final tools = _toolMapper.mapAll(selectedTools);
    return LiteRtToolCallConfig(
      tools: tools,
      supportsFunctionCalls: tools.isNotEmpty,
      toolChoice: tools.isEmpty ? ToolChoice.none : ToolChoice.auto,
    );
  }

  bool _isFunctionGemmaModel(String? modelId) {
    if (modelId == null) {
      return false;
    }
    final lower = modelId.toLowerCase();
    return _functionGemmaIdHints.any(lower.contains);
  }

  bool _isGemma4E2bModel(String modelId) {
    final lower = modelId.toLowerCase();
    return _gemma4E2bIdHints.any(lower.contains);
  }

  _TokenBudgets _selectTokenBudgets({
    required String modelId,
    required PreferredBackend preferredBackend,
    required LiteRtDeviceStats? deviceStats,
  }) {
    final modelCaps = _resolveModelTokenCaps(modelId);
    final deviceCaps = _resolveDeviceTokenCaps(
      deviceStats: deviceStats,
      preferredBackend: preferredBackend,
      modelId: modelId,
    );
    final initBudget = math.min(
      modelCaps.initTokenBudget,
      deviceCaps.initTokenBudget,
    );
    final runtimeTarget = math.min(
      modelCaps.runtimeTargetTokenBudget,
      deviceCaps.runtimeTargetTokenBudget,
    );
    return _TokenBudgets(
      initTokenBudget: math.min(initBudget, runtimeTarget),
      runtimeTargetTokenBudget: runtimeTarget,
    );
  }

  _TokenBudgets _resolveModelTokenCaps(String modelId) {
    if (_isGemma4E2bModel(modelId)) {
      return const _TokenBudgets(
        initTokenBudget: _gemma4E2bInitMaxTokens,
        runtimeTargetTokenBudget: _gemma4E2bRuntimeMaxTokens,
      );
    }
    if (_isFunctionGemmaModel(modelId)) {
      return const _TokenBudgets(
        initTokenBudget: 2048,
        runtimeTargetTokenBudget: 4096,
      );
    }
    return const _TokenBudgets(
      initTokenBudget: 8192,
      runtimeTargetTokenBudget: _defaultMaxTokens,
    );
  }

  _TokenBudgets _resolveDeviceTokenCaps({
    required LiteRtDeviceStats? deviceStats,
    required PreferredBackend preferredBackend,
    required String modelId,
  }) {
    final lowRam = deviceStats?.lowRam ?? false;
    final freeRam = deviceStats?.freeRam;
    final totalRam = deviceStats?.totalRamGb;

    var initCap = 8192;
    var runtimeCap = 16384;

    if (lowRam) {
      initCap = 2048;
      runtimeCap = 4096;
    } else if (freeRam != null) {
      if (freeRam < 1.5) {
        initCap = 2048;
        runtimeCap = 4096;
      } else if (freeRam < 3) {
        initCap = 4096;
        runtimeCap = 8192;
      } else if (freeRam < 5) {
        initCap = 8192;
        runtimeCap = 12288;
      } else if (freeRam < 7) {
        initCap = 12288;
        runtimeCap = 16384;
      } else {
        initCap = 16384;
        runtimeCap = 32768;
      }
    }

    if (totalRam != null) {
      if (totalRam < 4) {
        initCap = math.min(initCap, 2048);
        runtimeCap = math.min(runtimeCap, 4096);
      } else if (totalRam < 6) {
        initCap = math.min(initCap, 4096);
        runtimeCap = math.min(runtimeCap, 8192);
      } else if (totalRam < 8) {
        initCap = math.min(initCap, 8192);
        runtimeCap = math.min(runtimeCap, 12288);
      }
    }

    if (preferredBackend == PreferredBackend.gpu &&
        _isGemma4E2bModel(modelId)) {
      initCap = math.min(initCap, _gemma4E2bInitMaxTokens);
      runtimeCap = math.min(runtimeCap, _gemma4E2bRuntimeMaxTokens);
    }

    if (preferredBackend == PreferredBackend.cpu) {
      initCap = math.min(initCap, 8192);
      runtimeCap = math.min(runtimeCap, 16384);
    }

    return _TokenBudgets(
      initTokenBudget: initCap,
      runtimeTargetTokenBudget: runtimeCap,
    );
  }

  List<_InitAttempt> _buildInitAttempts({
    required PreferredBackend preferredBackend,
    required int initTokenBudget,
    required int runtimeTargetTokenBudget,
  }) {
    final tiers = <int>[1024, 2048, 4096, 8192, 12288, 16384, 32768];
    int normalizeTier(int value) {
      return tiers.where((tier) => tier <= value).fold(1024, math.max);
    }

    final startBudget = normalizeTier(initTokenBudget);
    final safeBudget = normalizeTier(runtimeTargetTokenBudget);
    final budgets = <int>{};
    for (final tier in tiers) {
      if (tier <= startBudget && tier <= safeBudget) {
        budgets.add(tier);
      }
    }
    final sortedBudgets = budgets.toList()..sort((a, b) => b.compareTo(a));

    final attempts = <_InitAttempt>[];
    for (final budget in sortedBudgets) {
      attempts.add(
        _InitAttempt(
          backend: preferredBackend,
          initTokenBudget: budget,
          note: 'initial-backend',
        ),
      );
    }

    if (preferredBackend != PreferredBackend.cpu) {
      for (final budget in sortedBudgets) {
        attempts.add(
          _InitAttempt(
            backend: PreferredBackend.cpu,
            initTokenBudget: budget,
            note: 'fallback-cpu',
          ),
        );
      }
    }

    return attempts;
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
    final totalRam =
        (result['totalRamGb'] as num?)?.toDouble() ??
        (result['totalram'] as num?)?.toDouble();
    final npuReady =
        result['npuReady'] as bool? ?? result['npu_ready'] as bool?;
    final gpuReady =
        result['gpuReady'] as bool? ?? result['gpu_ready'] as bool?;
    final lowRam = result['lowRam'] as bool? ?? result['low_ram'] as bool?;
    if (freeRam == null || npuReady == null) {
      return null;
    }
    return LiteRtDeviceStats(
      freeRam: freeRam,
      npuReady: npuReady,
      gpuReady: gpuReady,
      totalRamGb: totalRam,
      lowRam: lowRam,
    );
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
    var nextBackend = switch (currentBackend) {
      PreferredBackend.gpu => PreferredBackend.cpu,
      PreferredBackend.npu => PreferredBackend.gpu,
      _ => currentBackend,
    };
    if (nextBackend == PreferredBackend.gpu) {
      final stats = await getDeviceStats();
      final gpuReady = stats?.gpuReady ?? false;
      if (!gpuReady && _isGemma4E2bModel(modelId)) {
        debugPrint(
          'LiteRtBridge._attemptMemoryPressureRecovery: GPU not explicitly ready for Gemma 4 E2B, staying on CPU',
        );
        nextBackend = PreferredBackend.cpu;
      }
    }

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

class _TokenBudgets {
  const _TokenBudgets({
    required this.initTokenBudget,
    required this.runtimeTargetTokenBudget,
  });

  final int initTokenBudget;
  final int runtimeTargetTokenBudget;
}

class _InitAttempt {
  const _InitAttempt({
    required this.backend,
    required this.initTokenBudget,
    required this.note,
  });

  final PreferredBackend backend;
  final int initTokenBudget;
  final String note;
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

class LiteRtToolCallConfig {
  const LiteRtToolCallConfig({
    required this.tools,
    required this.supportsFunctionCalls,
    required this.toolChoice,
  });

  final List<Tool> tools;
  final bool supportsFunctionCalls;
  final ToolChoice toolChoice;
}

class LiteRtGenerationMetrics {
  const LiteRtGenerationMetrics({required this.totalTokens, required this.tps});

  final int totalTokens;
  final double tps;
}

class LiteRtDeviceStats {
  const LiteRtDeviceStats({
    required this.freeRam,
    required this.npuReady,
    this.gpuReady,
    this.totalRamGb,
    this.lowRam,
  });

  final double freeRam;
  final bool npuReady;
  final bool? gpuReady;
  final double? totalRamGb;
  final bool? lowRam;
}

class LiteRtInferenceStats {
  const LiteRtInferenceStats({required this.tps, required this.latencyMs});

  final double tps;
  final int latencyMs;
}
