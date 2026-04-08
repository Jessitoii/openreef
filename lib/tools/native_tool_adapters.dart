enum BatteryState { charging, discharging, full, unknown }

enum DndMode { all, priorityOnly, alarmsOnly, none }

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

class NotificationDispatch {
  const NotificationDispatch({
    required this.notificationId,
    required this.dispatchedAt,
  });

  final int notificationId;
  final DateTime dispatchedAt;
}

class ContactRecord {
  const ContactRecord({
    required this.displayName,
    this.phoneNumbers = const <String>[],
    this.emailAddresses = const <String>[],
  });

  final String displayName;
  final List<String> phoneNumbers;
  final List<String> emailAddresses;
}

class LocationSnapshot {
  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.provider,
    required this.timestamp,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final String provider;
  final DateTime timestamp;
  final double? accuracyMeters;
}

abstract class DeviceVolumeAdapter {
  Future<double> setVolumeLevel(double normalizedLevel);
}

abstract class ClipboardAdapter {
  Future<String?> readClipboardText();

  Future<void> writeClipboardText(String text);
}

abstract class BatteryAdapter {
  Future<BatterySnapshot> readBatteryInfo();
}

abstract class ContactAdapter {
  Future<List<ContactRecord>> searchContacts({
    String? query,
    required int limit,
  });

  Future<ContactRecord> createContact({
    required String displayName,
    String? phone,
    String? email,
  });
}

abstract class DraftMessageAdapter {
  Future<void> openSmsDraft({
    String? to,
    String? body,
  });

  Future<void> openEmailDraft({
    String? to,
    String? subject,
    String? body,
  });
}

abstract class FlashlightAdapter {
  Future<bool> setEnabled(bool enabled);
}

abstract class DndAdapter {
  Future<DndMode> setMode(DndMode mode);
}

abstract class LocationAdapter {
  Future<LocationSnapshot> getCurrentLocation({
    required bool highAccuracy,
  });
}

abstract class MapsAdapter {
  Future<void> openNavigation({
    required String query,
  });
}

abstract class TtsAdapter {
  Future<void> speak({
    required String text,
    required bool interrupt,
  });
}

abstract class NotificationAdapter {
  Future<NotificationDispatch> showNotification({
    required String title,
    required String body,
  });
}

abstract class AppLauncherAdapter {
  Future<void> openApp(String packageName);
}

abstract class ShareAdapter {
  Future<void> shareText({
    required String text,
    String? subject,
  });
}
