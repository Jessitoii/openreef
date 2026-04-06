import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/main.dart';
import 'package:openreef/models/litert_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap initializes LiteRT with the local downloaded path', () async {
    final bridge = _FakeLiteRtBridge();

    await initializeLiteRtModelAtPath(
      bridge,
      path: '/data/user/0/com.openreef.app/files/models/gemma.task',
    );

    expect(bridge.initModelPath, '/data/user/0/com.openreef.app/files/models/gemma.task');
    expect(bridge.initModelUseNpu, isFalse);
  });
}

class _FakeLiteRtBridge extends LiteRtBridge {
  String? initModelPath;
  bool? initModelUseNpu;

  @override
  Future<LiteRtDeviceStats> getDeviceStats() async {
    return const LiteRtDeviceStats(freeRam: 6.0, npuReady: false);
  }

  @override
  Future<bool> initModel({
    required String path,
    required bool useNpu,
  }) async {
    initModelPath = path;
    initModelUseNpu = useNpu;
    return true;
  }
}
