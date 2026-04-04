import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Coordinates nightly background memory consolidation scheduling.
///
/// This stub only exposes scheduling hooks so the Android WorkManager
/// integration can be wired without touching agent or memory logic.
class AutoDreamWorker {
  AutoDreamWorker({OptionalMethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ?? const OptionalMethodChannel(methodChannelName);

  static const String workName = 'openreef.auto_dream.nightly';
  static const String methodChannelName = 'openreef/background_channel';

  static const String _scheduleMethod = 'scheduleNightlyAutoDream';
  static const String _cancelMethod = 'cancelNightlyAutoDream';

  final OptionalMethodChannel _methodChannel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> scheduleNightly() async {
    if (!isSupported) {
      return false;
    }

    final scheduled = await _methodChannel.invokeMethod<bool>(
      _scheduleMethod,
      <String, Object?>{'workName': workName},
    );
    return scheduled ?? false;
  }

  Future<bool> cancelNightly() async {
    if (!isSupported) {
      return false;
    }

    final cancelled = await _methodChannel.invokeMethod<bool>(
      _cancelMethod,
      <String, Object?>{'workName': workName},
    );
    return cancelled ?? false;
  }
}
