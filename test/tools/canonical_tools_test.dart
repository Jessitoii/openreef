
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/triggers/trigger_native_sync.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/native_tool_adapters.dart';


class _MockAdapter implements NotificationAdapter, AppLauncherAdapter, ShareAdapter, DeviceVolumeAdapter, ContactAdapter, MapsAdapter, ClipboardAdapter, BatteryAdapter, DraftMessageAdapter, FlashlightAdapter, DndAdapter, LocationAdapter, TtsAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


void main() {
  test('canonical tools registry parity', () {
    final adapter = _MockAdapter();
    final handlers = createMvpNativeToolHandlers(
      volumeAdapter: adapter,
      clipboardAdapter: adapter,
      batteryAdapter: adapter,
      contactAdapter: adapter,
      draftMessageAdapter: adapter,
      locationAdapter: adapter,
      mapsAdapter: adapter,
      notificationAdapter: adapter,
      appLauncherAdapter: adapter,
      shareAdapter: adapter,
      memoryRetriever: _MockRetriever(),
      memoryStorage: _MockStorage(),
      settingsController: _MockSettings(),
      triggerNativeSync: _MockTriggerSync(),
      triggerSystem: _MockTriggerSystem(),
      triggerRepository: _MockTriggerRepo(),
      flashlightAdapter: adapter,
      dndAdapter: adapter,
      ttsAdapter: adapter,
    );

    final ids = handlers.map((h) => h.manifest.id).toSet();

    // The canonical set:
    expect(ids, containsAll(<String>[
      'volume_set',
      'clipboard_read',
      'clipboard_write',
      'battery_info',
      'contact_read',
      'contact_create',
      'sms_draft',
      'email_draft',
      'flashlight_toggle',
      'dnd_set',
      'location_get',
      'maps_navigate',
      'regex_eval',
      'math_eval',
      'tts_speak',
      'notify',
      'memory_search',
    ]));

    // Should NOT contain the removed tools:
    expect(ids.contains('pdf_read'), isFalse);
    expect(ids.contains('pdf_summarize'), isFalse);
  });
}

class _MockRetriever implements SemanticMemoryRetriever { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }
class _MockStorage implements MemoryStorage { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }

class _MockSettings implements SettingsController { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }
class _MockTriggerSync implements TriggerNativeSync { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }
class _MockTriggerSystem implements TriggerSystem { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }
class _MockTriggerRepo implements TriggerRepository { @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i); }
