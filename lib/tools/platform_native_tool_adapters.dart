import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/tool_errors.dart';

class PlatformVolumeAdapter implements DeviceVolumeAdapter {
  PlatformVolumeAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<double> setVolumeLevel(double normalizedLevel) async {
    final appliedLevel = await _methodChannel.invokeMethod<double>(
      'setVolumeLevel',
      <String, Object?>{'level': normalizedLevel},
    );
    return appliedLevel ?? normalizedLevel;
  }
}

class PlatformClipboardAdapter implements ClipboardAdapter {
  const PlatformClipboardAdapter();

  @override
  Future<String?> readClipboardText() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    return clipboardData?.text;
  }

  @override
  Future<void> writeClipboardText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}

class PlatformBatteryAdapter implements BatteryAdapter {
  PlatformBatteryAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<BatterySnapshot> readBatteryInfo() async {
    final response = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getBatteryInfo',
    );
    final map = response ?? const <Object?, Object?>{};
    return BatterySnapshot(
      level: (map['level'] as num?)?.toInt() ?? 0,
      state: _parseBatteryState(map['state'] as String?),
      isLowPowerMode: map['isLowPowerMode'] as bool? ?? false,
    );
  }

  BatteryState _parseBatteryState(String? value) {
    switch (value) {
      case 'charging':
        return BatteryState.charging;
      case 'discharging':
        return BatteryState.discharging;
      case 'full':
        return BatteryState.full;
      default:
        return BatteryState.unknown;
    }
  }
}

class PlatformContactAdapter implements ContactAdapter {
  PlatformContactAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<ContactRecord> createContact({
    required String displayName,
    String? phone,
    String? email,
  }) async {
    final map = await _invokeToolMap(
      _methodChannel,
      method: 'createContact',
      arguments: <String, Object?>{
        'displayName': displayName,
        'phone': phone,
        'email': email,
      },
    );
    return _contactFromMap(map);
  }

  @override
  Future<List<ContactRecord>> searchContacts({
    String? query,
    required int limit,
  }) async {
    final map = await _invokeToolMap(
      _methodChannel,
      method: 'queryContacts',
      arguments: <String, Object?>{'query': query, 'limit': limit},
    );
    final rawResults = map['results'];
    if (rawResults is! List) {
      return const <ContactRecord>[];
    }
    return rawResults
        .whereType<Map>()
        .map((item) => _contactFromMap(Map<Object?, Object?>.from(item)))
        .toList(growable: false);
  }

  ContactRecord _contactFromMap(Map<Object?, Object?> map) {
    return ContactRecord(
      displayName: map['displayName'] as String? ?? '',
      phoneNumbers: _stringList(map['phoneNumbers']),
      emailAddresses: _stringList(map['emailAddresses']),
    );
  }
}

class PlatformDraftMessageAdapter implements DraftMessageAdapter {
  PlatformDraftMessageAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<void> openEmailDraft({
    String? to,
    String? subject,
    String? body,
  }) async {
    await _invokeToolMap(
      _methodChannel,
      method: 'openEmailDraft',
      arguments: <String, Object?>{'to': to, 'subject': subject, 'body': body},
    );
  }

  @override
  Future<void> openSmsDraft({String? to, String? body}) async {
    await _invokeToolMap(
      _methodChannel,
      method: 'openSmsDraft',
      arguments: <String, Object?>{'to': to, 'body': body},
    );
  }
}

class PlatformFlashlightAdapter implements FlashlightAdapter {
  PlatformFlashlightAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<bool> setEnabled(bool enabled) async {
    final map = await _invokeToolMap(
      _methodChannel,
      method: 'setFlashlightEnabled',
      arguments: <String, Object?>{'enabled': enabled},
    );
    return map['enabled'] as bool? ?? enabled;
  }
}

class PlatformDndAdapter implements DndAdapter {
  PlatformDndAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<DndMode> setMode(DndMode mode) async {
    final map = await _invokeToolMap(
      _methodChannel,
      method: 'setDndMode',
      arguments: <String, Object?>{'mode': _wireMode(mode)},
    );
    return _parseMode(map['mode'] as String?);
  }

  String _wireMode(DndMode mode) => switch (mode) {
    DndMode.all => 'all',
    DndMode.priorityOnly => 'priority_only',
    DndMode.alarmsOnly => 'alarms_only',
    DndMode.none => 'none',
  };

  DndMode _parseMode(String? value) {
    switch (value) {
      case 'priority_only':
        return DndMode.priorityOnly;
      case 'alarms_only':
        return DndMode.alarmsOnly;
      case 'none':
        return DndMode.none;
      default:
        return DndMode.all;
    }
  }
}

class PlatformLocationAdapter implements LocationAdapter {
  PlatformLocationAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<LocationSnapshot> getCurrentLocation({
    required bool highAccuracy,
  }) async {
    final map = await _invokeToolMap(
      _methodChannel,
      method: 'getCurrentLocation',
      arguments: <String, Object?>{'highAccuracy': highAccuracy},
    );
    return LocationSnapshot(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      provider: map['provider'] as String? ?? 'unknown',
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now().toUtc(),
      accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
    );
  }
}

class PlatformMapsAdapter implements MapsAdapter {
  PlatformMapsAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<void> openNavigation({required String query}) async {
    await _invokeToolMap(
      _methodChannel,
      method: 'openMapsNavigate',
      arguments: <String, Object?>{'query': query},
    );
  }
}

class PlatformTtsAdapter implements TtsAdapter {
  PlatformTtsAdapter({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;

  @override
  Future<void> speak({required String text, required bool interrupt}) async {
    if (!Platform.isAndroid) {
      throw const ToolExecutionException(
        ToolExecutionError(
          code: ToolErrorCode.unsupported,
          message: 'Text-to-speech is only supported on Android in this pass.',
        ),
      );
    }

    try {
      if (!_initialized) {
        await _tts.awaitSpeakCompletion(true);
        _initialized = true;
      }
      if (interrupt) {
        await _tts.stop();
      }
      final result = await _tts.speak(text);
      if (result is int && result == 1) {
        return;
      }
      if (result == null) {
        return;
      }
      throw ToolExecutionException(
        ToolExecutionError(
          code: ToolErrorCode.operationFailed,
          message: 'The TTS engine did not accept the utterance.',
          innerError: <String, Object?>{'result': result.toString()},
        ),
      );
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }
}

class PlatformNotificationAdapter implements NotificationAdapter {
  PlatformNotificationAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<NotificationDispatch> showNotification({
    required String title,
    required String body,
  }) async {
    final response = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'showNotification',
      <String, Object?>{'title': title, 'body': body},
    );
    final map = response ?? const <Object?, Object?>{};
    return NotificationDispatch(
      notificationId: (map['notificationId'] as num?)?.toInt() ?? 0,
      dispatchedAt:
          DateTime.tryParse(map['dispatchedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class PlatformAppLauncherAdapter implements AppLauncherAdapter {
  PlatformAppLauncherAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<void> openApp(String packageName) {
    return _methodChannel.invokeMethod<void>('openApp', <String, Object?>{
      'packageName': packageName,
    });
  }
}

class PlatformShareAdapter implements ShareAdapter {
  PlatformShareAdapter({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/native_tools';

  final MethodChannel _methodChannel;

  @override
  Future<void> shareText({required String text, String? subject}) {
    return _methodChannel.invokeMethod<void>('shareText', <String, Object?>{
      'text': text,
      'subject': subject,
    });
  }
}

Future<Map<Object?, Object?>> _invokeToolMap(
  MethodChannel channel, {
  required String method,
  Map<String, Object?>? arguments,
}) async {
  try {
    final response = await channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    return response ?? const <Object?, Object?>{};
  } on PlatformException catch (error) {
    throw _mapPlatformException(error);
  }
}

ToolExecutionException _mapPlatformException(PlatformException error) {
  final details = error.details;
  if (details is Map) {
    final map = Map<Object?, Object?>.from(details);
    final code = _parseErrorCode(map['code'] as String? ?? error.code);
    final message =
        map['message'] as String? ?? error.message ?? 'Native tool failed.';
    final rawDetails = map['details'];
    return ToolExecutionException(
      ToolExecutionError(
        code: code,
        message: message,
        innerError: rawDetails is Map
            ? Map<String, Object?>.from(
                rawDetails.map((key, value) => MapEntry(key.toString(), value)),
              )
            : const <String, Object?>{},
      ),
    );
  }

  return ToolExecutionException(
    ToolExecutionError(
      code: _parseErrorCode(error.code),
      message: error.message ?? 'Native tool failed.',
    ),
  );
}

ToolErrorCode _parseErrorCode(String value) {
  switch (value) {
    case 'permission_denied':
      return ToolErrorCode.permissionDenied;
    case 'permission_required':
      return ToolErrorCode.permissionRequired;
    case 'feature_unavailable':
      return ToolErrorCode.featureUnavailable;
    case 'app_unavailable':
      return ToolErrorCode.appUnavailable;
    case 'invalid_arguments':
      return ToolErrorCode.invalidArguments;
    case 'unsupported':
      return ToolErrorCode.unsupported;
    default:
      return ToolErrorCode.operationFailed;
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
