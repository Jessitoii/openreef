import 'package:flutter/services.dart';
import 'package:openreef/tools/native_tool_adapters.dart';

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
