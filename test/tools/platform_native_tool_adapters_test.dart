import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/platform_native_tool_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeChannel = MethodChannel('openreef/native_tools');
  const ttsChannel = MethodChannel('flutter_tts');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
  });

  test('contact adapter maps structured permission failures', () async {
    final adapter = PlatformContactAdapter(methodChannel: nativeChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          throw PlatformException(
            code: 'permission_denied',
            message: 'Contacts permission denied.',
            details: <String, Object?>{
              'code': 'permission_denied',
              'message': 'Contacts permission denied.',
              'details': <String, Object?>{'permission': 'READ_CONTACTS'},
            },
          );
        });

    expect(
      () => adapter.searchContacts(limit: 5),
      throwsA(
        isA<ToolExecutionException>().having(
          (error) => error.error.code,
          'code',
          ToolErrorCode.permissionDenied,
        ),
      ),
    );
  });

  test('location adapter parses success payloads', () async {
    final adapter = PlatformLocationAdapter(methodChannel: nativeChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          expect(call.method, 'getCurrentLocation');
          return <String, Object?>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'provider': 'gps',
            'timestamp': '2026-04-07T10:00:00.000Z',
            'accuracyMeters': 5.0,
          };
        });

    final result = await adapter.getCurrentLocation(highAccuracy: true);

    expect(result.provider, 'gps');
    expect(result.latitude, 41.0082);
    expect(result.accuracyMeters, 5.0);
  });

  test('maps adapter maps app unavailable errors', () async {
    final adapter = PlatformMapsAdapter(methodChannel: nativeChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          throw PlatformException(
            code: 'app_unavailable',
            message: 'No navigation app is available.',
            details: <String, Object?>{
              'code': 'app_unavailable',
              'message': 'No navigation app is available.',
            },
          );
        });

    expect(
      () => adapter.openNavigation(query: 'Istanbul Airport'),
      throwsA(
        isA<ToolExecutionException>().having(
          (error) => error.error.code,
          'code',
          ToolErrorCode.appUnavailable,
        ),
      ),
    );
  });

  test('tts adapter configures await completion and speak', () async {
    if (!Platform.isAndroid) {
      return;
    }

    final adapter = PlatformTtsAdapter();
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
          methods.add(call.method);
          if (call.method == 'speak') {
            return 1;
          }
          return 1;
        });

    await adapter.speak(text: 'Hello reef', interrupt: true);

    expect(methods, contains('awaitSpeakCompletion'));
    expect(methods, contains('stop'));
    expect(methods, contains('speak'));
  });
}
