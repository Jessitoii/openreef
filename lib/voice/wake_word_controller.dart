import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the Android wake-word foreground service.
///
/// The implementation is intentionally lightweight so the voice layer can
/// compile cleanly before Porcupine and audio processing are wired in.
class WakeWordController {
  WakeWordController({OptionalMethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ?? const OptionalMethodChannel(methodChannelName);

  static const String methodChannelName = 'openreef/wake_word_channel';

  static const String _startMethod = 'startListening';
  static const String _stopMethod = 'stopListening';
  static const String _statusMethod = 'isListening';

  final OptionalMethodChannel _methodChannel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> startListening() async {
    if (!isSupported) {
      return false;
    }

    final started = await _methodChannel.invokeMethod<bool>(_startMethod);
    return started ?? false;
  }

  Future<bool> stopListening() async {
    if (!isSupported) {
      return false;
    }

    final stopped = await _methodChannel.invokeMethod<bool>(_stopMethod);
    return stopped ?? false;
  }

  Future<bool> isListening() async {
    if (!isSupported) {
      return false;
    }

    final listening = await _methodChannel.invokeMethod<bool>(_statusMethod);
    return listening ?? false;
  }
}
