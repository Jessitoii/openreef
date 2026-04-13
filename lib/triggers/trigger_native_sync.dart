import 'package:flutter/services.dart';
import 'package:openreef/triggers/trigger_channels.dart';
import 'package:openreef/triggers/trigger_codec.dart';
import 'package:openreef/triggers/trigger_models.dart';

class TriggerNativeSync {
  TriggerNativeSync({
    MethodChannel? methodChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(triggerMethodChannelName);

  static const String syncMethod = 'syncTriggerRegistry';
  static const String registerPollingWorkMethod = 'registerGlobalPollingWork';
  static const String syncGlobalPollMinutesMethod = 'syncGlobalPollMinutes';

  final MethodChannel _methodChannel;
  final TriggerCodec _codec = const TriggerCodec();

  Future<void> syncTriggers(List<TriggerConfig> triggers) async {
    await _methodChannel.invokeMethod<void>(syncMethod, <String, Object?>{
      'triggers': triggers.map(_codec.encode).toList(growable: false),
    });
  }

  Future<void> registerGlobalPollingWork() async {
    await _methodChannel.invokeMethod<void>(registerPollingWorkMethod);
  }

  Future<void> syncGlobalPollMinutes(int minutes) async {
    await _methodChannel.invokeMethod<void>(syncGlobalPollMinutesMethod, <String, Object?>{
      'minutes': minutes,
    });
  }
}
