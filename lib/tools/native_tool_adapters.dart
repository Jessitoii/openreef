enum BatteryState { charging, discharging, full, unknown }

class BatterySnapshot {
  const BatterySnapshot({
    required this.level,
    required this.state,
    this.isLowPowerMode = false,
  });

  final int level;
  final BatteryState state;
  final bool isLowPowerMode;
}

abstract class DeviceVolumeAdapter {
  Future<double> setVolumeLevel(double normalizedLevel);
}

abstract class ClipboardAdapter {
  Future<String?> readClipboardText();
}

abstract class BatteryAdapter {
  Future<BatterySnapshot> readBatteryInfo();
}
