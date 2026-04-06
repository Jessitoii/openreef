import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class LiteRtBridge {
  LiteRtBridge();

  static const MethodChannel _deviceStatsChannel = MethodChannel(
    'openreef/device_stats',
  );

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  String? _activeModelId;
  PreferredBackend? _preferredBackend;
  int _maxTokens = 1024;
  static const List<String> _functionGemmaIdHints = <String>[
    'function',
    'mobile-actions',
  ];

  Future<bool> initModel({
    required String path,
    required bool useNpu,
  }) async {
    try {
      debugPrint('LiteRtBridge.initModel: preparing modelId=$path');
      final hasActive = FlutterGemma.hasActiveModel();
      if (!hasActive) {
        final installed = await FlutterGemma.listInstalledModels();
        if (!installed.contains(path)) {
          debugPrint('LiteRtBridge.initModel: modelId not installed');
          throw StateError('Requested model is not installed: $path');
        }
        debugPrint('LiteRtBridge.initModel: no active model, using installed model');
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

        debugPrint('LiteRtBridge.generateStream: createChat');
        _activeChat = await _activeModel!.createChat(
          supportsFunctionCalls: true,
          toolChoice: ToolChoice.auto,
        );
        debugPrint('LiteRtBridge.generateStream: addQueryChunk');
        await _activeChat!.addQueryChunk(
          Message.text(text: context, isUser: true),
        );

        debugPrint('LiteRtBridge.generateStream: start generateChatResponseAsync');
        _activeChat!.generateChatResponseAsync().listen(
          (ModelResponse response) {
            if (response is TextResponse) {
              if (response.token.trim().isNotEmpty) {
                emittedVisibleText = true;
              }
              controller.add(
                LiteRtGenerationEvent(
                  chunk: response.token,
                  isFinished: false,
                ),
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
              const LiteRtGenerationEvent(
                chunk: '',
                isFinished: true,
              ),
            );
            controller.close();
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('LiteRtBridge.generateStream: generation error $error');
            controller.addError(error, stackTrace);
            controller.close();
          },
        );
      } catch (error, stackTrace) {
        debugPrint('LiteRtBridge.generateStream: setup error $error');
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
    return true;
  }

  Future<bool> unloadModel() async {
    await _activeChat?.close();
    _activeChat = null;
    await _activeModel?.close();
    _activeModel = null;
    return true;
  }

  Future<LiteRtDeviceStats?> getDeviceStats() async {
    try {
      final result =
          await _deviceStatsChannel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceStats',
      );
      if (result == null) {
        return null;
      }
      final freeRam = (result['freeRamGb'] as num?)?.toDouble();
      final npuReady = result['npuReady'] as bool?;
      if (freeRam == null || npuReady == null) {
        return null;
      }
      return LiteRtDeviceStats(freeRam: freeRam, npuReady: npuReady);
    } on MissingPluginException {
      return null;
    }
  }

  Future<LiteRtInferenceStats> getInferenceStats() async {
    return const LiteRtInferenceStats(tps: 0, latencyMs: 0);
  }
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
  const LiteRtGenerationMetrics({
    required this.totalTokens,
    required this.tps,
  });

  final int totalTokens;
  final double tps;
}

class LiteRtDeviceStats {
  const LiteRtDeviceStats({
    required this.freeRam,
    required this.npuReady,
  });

  final double freeRam;
  final bool npuReady;
}

class LiteRtInferenceStats {
  const LiteRtInferenceStats({
    required this.tps,
    required this.latencyMs,
  });

  final double tps;
  final int latencyMs;
}
