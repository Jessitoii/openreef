import 'dart:async';

import 'package:flutter/services.dart';

class LiteRtBridge {
  LiteRtBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName),
        _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  static const String _methodChannelName = 'openreef/litert_channel';
  static const String _eventChannelName = 'openreef/litert_stream';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Future<bool> initModel({
    required String path,
    required bool useNpu,
  }) async {
    final success = await _methodChannel.invokeMethod<bool>(
      'initModel',
      <String, Object?>{
        'path': path,
        'useNpu': useNpu,
      },
    );
    return success ?? false;
  }

  Stream<LiteRtGenerationEvent> generateStream({
    required String context,
    required int maxTokens,
  }) {
    late final StreamController<LiteRtGenerationEvent> controller;
    StreamSubscription<dynamic>? subscription;

    controller = StreamController<LiteRtGenerationEvent>(
      onListen: () {
        subscription = _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            try {
              controller.add(
                LiteRtGenerationEvent.fromMap(
                  Map<Object?, Object?>.from(event as Map),
                ),
              );
            } catch (error, stackTrace) {
              controller.addError(error, stackTrace);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );

        _methodChannel
            .invokeMethod<void>(
              'generateStream',
              <String, Object?>{
                'context': context,
                'maxTokens': maxTokens,
              },
            )
            .catchError((Object error, StackTrace stackTrace) async {
          await subscription?.cancel();
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
        });
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  Future<bool> stopGeneration() async {
    final success = await _methodChannel.invokeMethod<bool>(
      'stopGeneration',
    );
    return success ?? false;
  }

  Future<bool> unloadModel() async {
    final success = await _methodChannel.invokeMethod<bool>(
      'unloadModel',
    );
    return success ?? false;
  }

  Future<LiteRtDeviceStats> getDeviceStats() async {
    final response = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getDeviceStats',
    );
    return LiteRtDeviceStats.fromMap(response ?? const <Object?, Object?>{});
  }

  Future<LiteRtInferenceStats> getInferenceStats() async {
    final response = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getInferenceStats',
    );
    return LiteRtInferenceStats.fromMap(
      response ?? const <Object?, Object?>{},
    );
  }
}

class LiteRtGenerationEvent {
  const LiteRtGenerationEvent({
    required this.chunk,
    required this.isFinished,
    this.metrics,
  });

  factory LiteRtGenerationEvent.fromMap(Map<Object?, Object?> map) {
    final rawMetrics = map['metrics'];
    return LiteRtGenerationEvent(
      chunk: map['chunk'] as String? ?? '',
      isFinished: map['isFinished'] as bool? ?? false,
      metrics: rawMetrics is Map<Object?, Object?>
          ? LiteRtGenerationMetrics.fromMap(rawMetrics)
          : null,
    );
  }

  final String chunk;
  final bool isFinished;
  final LiteRtGenerationMetrics? metrics;
}

class LiteRtGenerationMetrics {
  const LiteRtGenerationMetrics({
    required this.totalTokens,
    required this.tps,
  });

  factory LiteRtGenerationMetrics.fromMap(Map<Object?, Object?> map) {
    return LiteRtGenerationMetrics(
      totalTokens: (map['total_tokens'] as num?)?.toInt() ?? 0,
      tps: (map['tps'] as num?)?.toDouble() ?? 0,
    );
  }

  final int totalTokens;
  final double tps;
}

class LiteRtDeviceStats {
  const LiteRtDeviceStats({
    required this.freeRam,
    required this.npuReady,
  });

  factory LiteRtDeviceStats.fromMap(Map<Object?, Object?> map) {
    return LiteRtDeviceStats(
      freeRam: (map['freeram'] as num?)?.toDouble() ?? 0,
      npuReady: map['npu_ready'] as bool? ?? false,
    );
  }

  final double freeRam;
  final bool npuReady;
}

class LiteRtInferenceStats {
  const LiteRtInferenceStats({
    required this.tps,
    required this.latencyMs,
  });

  factory LiteRtInferenceStats.fromMap(Map<Object?, Object?> map) {
    return LiteRtInferenceStats(
      tps: (map['tps'] as num?)?.toDouble() ?? 0,
      latencyMs: (map['latency_ms'] as num?)?.toInt() ?? 0,
    );
  }

  final double tps;
  final int latencyMs;
}
