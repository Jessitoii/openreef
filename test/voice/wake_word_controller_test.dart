import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/voice/wake_word_controller.dart';

const OptionalMethodChannel _wakeWordMethodChannel = OptionalMethodChannel(
  WakeWordController.methodChannelName,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_wakeWordMethodChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_wakeWordMethodChannel, null);
  });

  test('controller starts, stops, and refreshes listening state', () async {
    final settingsController = SettingsController(
      store: SettingsStore(File('${Directory.systemTemp.path}/wake_settings_1.json')),
    );
    var listening = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_wakeWordMethodChannel, (call) async {
          switch (call.method) {
            case 'isAvailable':
              return true;
            case 'setSensitivity':
              return true;
            case 'startListening':
              listening = true;
              return true;
            case 'stopListening':
              listening = false;
              return true;
            case 'isListening':
              return listening;
            default:
              return null;
          }
        });

    final controller = WakeWordController(
      settingsController: settingsController,
      isSupportedOverride: true,
      eventStream: const Stream<dynamic>.empty(),
    );
    addTearDown(controller.dispose);

    expect(await controller.startListening(), isTrue);
    expect(controller.isListening, isTrue);

    listening = false;
    expect(await controller.refreshListeningState(), isFalse);
    expect(controller.isListening, isFalse);

    expect(await controller.stopListening(), isTrue);
    expect(controller.isListening, isFalse);
  });

  test(
    'controller emits detection events from the event channel stream',
    () async {
      final settingsController = SettingsController(
        store: SettingsStore(File('${Directory.systemTemp.path}/wake_settings_2.json')),
      );
      final platformEvents = StreamController<dynamic>.broadcast();
      final controller = WakeWordController(
        settingsController: settingsController,
        isSupportedOverride: true,
        eventStream: platformEvents.stream,
      );
      addTearDown(() async {
        await platformEvents.close();
        controller.dispose();
      });

      final eventFuture = controller.events.first;
      platformEvents.add(const <String, String>{'event': 'detected'});

      final event = await eventFuture;
      expect(event.type, WakeWordEventType.detected);
      expect(controller.lastDetectedAt, isNotNull);
    },
  );

  test(
    'controller syncs listening state from wake-word setting changes',
    () async {
      final settingsController = SettingsController(
        store: SettingsStore(File('${Directory.systemTemp.path}/wake_settings_3.json')),
      );
      var startCalls = 0;
      var stopCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_wakeWordMethodChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return true;
              case 'setSensitivity':
                return true;
              case 'startListening':
                startCalls += 1;
                return true;
              case 'stopListening':
                stopCalls += 1;
                return true;
              case 'isListening':
                return startCalls > stopCalls;
              default:
                return null;
            }
          });

      final controller = WakeWordController(
        settingsController: settingsController,
        isSupportedOverride: true,
        eventStream: const Stream<dynamic>.empty(),
      );
      addTearDown(controller.dispose);

      await controller.refreshAvailability();
      expect(controller.isAvailable, isTrue);

      settingsController.updateWakeWordEnabled(true);
      await Future<void>.delayed(Duration.zero);

      expect(startCalls, greaterThanOrEqualTo(1));
      expect(controller.isListening, isTrue);

      settingsController.updateWakeWordEnabled(false);
      await Future<void>.delayed(Duration.zero);

      expect(stopCalls, greaterThanOrEqualTo(1));
      expect(controller.isListening, isFalse);
    },
  );

  test(
    'controller reports unavailable wake runtime when native key is missing',
    () async {
      final settingsController = SettingsController(
        store: SettingsStore(File('${Directory.systemTemp.path}/wake_settings_4.json')),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_wakeWordMethodChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return false;
              case 'stopListening':
                return true;
              default:
                return null;
            }
          });

      final controller = WakeWordController(
        settingsController: settingsController,
        isSupportedOverride: true,
        eventStream: const Stream<dynamic>.empty(),
      );
      addTearDown(controller.dispose);

      expect(await controller.refreshAvailability(), isFalse);
      expect(controller.isAvailable, isFalse);
      expect(await controller.startListening(), isFalse);
      expect(controller.isListening, isFalse);
    },
  );
}
