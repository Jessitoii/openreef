import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/main.dart';
import 'package:openreef/models/litert_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel('openreef/litert_channel');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('bootstrap initializes LiteRT with the local downloaded path', () async {
    final bridge = LiteRtBridge(methodChannel: methodChannel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
          if (call.method == 'getDeviceStats') {
            return <String, Object?>{'freeram': 6.0, 'npu_ready': false};
          }

          expect(call.method, 'initModel');
          expect(call.arguments, <String, Object?>{
            'path': '/data/user/0/com.openreef.app/files/models/gemma.task',
            'useNpu': false,
          });
          return true;
        });

    await initializeLiteRtModelAtPath(
      bridge,
      path: '/data/user/0/com.openreef.app/files/models/gemma.task',
    );
  });
}
