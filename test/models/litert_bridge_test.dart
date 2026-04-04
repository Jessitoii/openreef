import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/litert_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel('openreef/litert_channel');
  final LiteRtBridge bridge = LiteRtBridge(methodChannel: methodChannel);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('initModel forwards arguments and returns success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      expect(call.method, 'initModel');
      expect(
        call.arguments,
        <String, Object?>{
          'path': '/models/gemma.litertlm',
          'useNpu': true,
        },
      );
      return true;
    });

    final success = await bridge.initModel(
      path: '/models/gemma.litertlm',
      useNpu: true,
    );

    expect(success, isTrue);
  });

  test('getDeviceStats parses documented keys', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      expect(call.method, 'getDeviceStats');
      return <String, Object?>{
        'freeram': 3.5,
        'npu_ready': true,
      };
    });

    final stats = await bridge.getDeviceStats();

    expect(stats.freeRam, 3.5);
    expect(stats.npuReady, isTrue);
  });

  test('getInferenceStats parses documented keys', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      expect(call.method, 'getInferenceStats');
      return <String, Object?>{
        'tps': 22.4,
        'latency_ms': 128,
      };
    });

    final stats = await bridge.getInferenceStats();

    expect(stats.tps, 22.4);
    expect(stats.latencyMs, 128);
  });

  test('generation event parses token chunk payload', () {
    final event = LiteRtGenerationEvent.fromMap(
      <String, Object?>{
        'chunk': ' Hello',
        'isFinished': false,
        'metrics': null,
      },
    );

    expect(event.chunk, ' Hello');
    expect(event.isFinished, isFalse);
    expect(event.metrics, isNull);
  });

  test('generation event parses completion payload', () {
    final event = LiteRtGenerationEvent.fromMap(
      <String, Object?>{
        'chunk': '',
        'isFinished': true,
        'metrics': <String, Object?>{
          'total_tokens': 128,
          'tps': 22.4,
        },
      },
    );

    expect(event.chunk, isEmpty);
    expect(event.isFinished, isTrue);
    expect(event.metrics?.totalTokens, 128);
    expect(event.metrics?.tps, 22.4);
  });

  test('platform exception codes are preserved', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      throw PlatformException(
        code: 'ERR_NPU_FALLBACK',
        message: 'NPU unavailable',
      );
    });

    expect(
      () => bridge.initModel(path: '/models/gemma.litertlm', useNpu: true),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'ERR_NPU_FALLBACK',
        ),
      ),
    );
  });
}
