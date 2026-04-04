import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/triggers/trigger_channels.dart';
import 'package:openreef/triggers/trigger_platform_event.dart';

/// Owns the Flutter event stream for native trigger deliveries.
class TriggerEventBridge {
  TriggerEventBridge({
    EventChannel? eventChannel,
    Stream<dynamic>? eventStream,
    bool? isSupportedOverride,
  }) : _eventChannel =
           eventChannel ?? const EventChannel(triggerEventChannelName),
       _eventStreamOverride = eventStream,
       _isSupportedOverride = isSupportedOverride {
    _eventSubscription = _platformEvents().listen(_handlePlatformEvent);
  }

  final EventChannel _eventChannel;
  final Stream<dynamic>? _eventStreamOverride;
  final bool? _isSupportedOverride;
  final StreamController<TriggerPlatformEvent> _events =
      StreamController<TriggerPlatformEvent>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  TriggerPlatformEvent? _lastEvent;

  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Stream<TriggerPlatformEvent> get events => _events.stream;

  TriggerPlatformEvent? get lastEvent => _lastEvent;

  void dispose() {
    _eventSubscription?.cancel();
    _events.close();
  }

  Stream<dynamic> _platformEvents() {
    if (!isSupported) {
      return const Stream<dynamic>.empty();
    }
    return _eventStreamOverride ?? _eventChannel.receiveBroadcastStream();
  }

  void _handlePlatformEvent(dynamic payload) {
    final event = TriggerPlatformEvent.fromPlatformPayload(payload);
    _lastEvent = event;
    _events.add(event);
  }
}
