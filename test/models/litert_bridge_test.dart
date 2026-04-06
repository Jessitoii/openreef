import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/litert_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final LiteRtBridge bridge = LiteRtBridge();
  const MethodChannel deviceStatsChannel = MethodChannel(
    'openreef/device_stats',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceStatsChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceStatsChannel, null);
  });

  test('getDeviceStats returns null when channel is unavailable', () async {
    final stats = await bridge.getDeviceStats();

    expect(stats, isNull);
  });

  test('getInferenceStats returns fallback defaults', () async {
    final stats = await bridge.getInferenceStats();

    expect(stats.tps, 0);
    expect(stats.latencyMs, 0);
  });

  test('generateStream throws when model not initialized', () {
    expect(
      () => bridge.generateStream(context: 'Hello', maxTokens: 16),
      throwsA(isA<StateError>()),
    );
  });
}
