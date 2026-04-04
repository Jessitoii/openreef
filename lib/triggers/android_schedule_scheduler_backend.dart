import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/triggers/trigger_channels.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_system.dart';

class AndroidScheduleSchedulerBackend implements ScheduleSchedulerBackend {
  AndroidScheduleSchedulerBackend({
    OptionalMethodChannel? methodChannel,
    bool? isSupportedOverride,
  }) : _methodChannel =
           methodChannel ??
           const OptionalMethodChannel(triggerMethodChannelName),
       _isSupportedOverride = isSupportedOverride;

  static const String registerMethod = 'registerExactSchedule';
  static const String cancelMethod = 'cancelExactSchedule';
  static const String permissionMethod = 'hasExactAlarmPermission';

  final OptionalMethodChannel _methodChannel;
  final bool? _isSupportedOverride;

  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<bool> hasExactAlarmPermission() async {
    if (!isSupported) {
      return false;
    }

    final allowed = await _methodChannel.invokeMethod<bool>(permissionMethod);
    return allowed ?? false;
  }

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {
    final spec = trigger.scheduleSpec;
    if (spec == null) {
      throw StateError('schedule trigger missing scheduleSpec');
    }
    if (!isSupported) {
      return;
    }

    final hasPermission = await hasExactAlarmPermission();
    if (!hasPermission) {
      throw PlatformException(
        code: 'ERR_EXACT_ALARM_PERMISSION_DENIED',
        message: 'Android exact alarm permission is not granted.',
      );
    }

    await _methodChannel.invokeMethod<void>(registerMethod, <String, Object?>{
      'triggerId': trigger.id,
      'name': trigger.name,
      'type': trigger.type.name,
      'priority': trigger.priority.name,
      'hour': spec.hour,
      'minute': spec.minute,
      'payload': Map<String, Object?>.from(trigger.payload),
      'requiresUserAttention': trigger.requiresUserAttention,
      'isExpensive': trigger.isExpensive,
    });
  }

  @override
  Future<void> cancel(String triggerId) async {
    if (!isSupported) {
      return;
    }

    await _methodChannel.invokeMethod<void>(cancelMethod, <String, Object?>{
      'triggerId': triggerId,
    });
  }
}
