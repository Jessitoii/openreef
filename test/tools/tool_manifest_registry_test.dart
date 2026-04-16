import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';

void main() {
  late _RecordingVolumeAdapter volumeAdapter;
  late _RecordingClipboardAdapter clipboardAdapter;
  late _RecordingBatteryAdapter batteryAdapter;
  late _RecordingContactAdapter contactAdapter;
  late _RecordingDraftMessageAdapter draftMessageAdapter;
  late _RecordingFlashlightAdapter flashlightAdapter;
  late _RecordingDndAdapter dndAdapter;
  late _RecordingLocationAdapter locationAdapter;
  late _RecordingMapsAdapter mapsAdapter;
  late _RecordingTtsAdapter ttsAdapter;
  late ToolManifestRegistry registry;

  setUp(() {
    volumeAdapter = _RecordingVolumeAdapter();
    clipboardAdapter = _RecordingClipboardAdapter();
    batteryAdapter = _RecordingBatteryAdapter();
    contactAdapter = _RecordingContactAdapter();
    draftMessageAdapter = _RecordingDraftMessageAdapter();
    flashlightAdapter = _RecordingFlashlightAdapter();
    dndAdapter = _RecordingDndAdapter();
    locationAdapter = _RecordingLocationAdapter();
    mapsAdapter = _RecordingMapsAdapter();
    ttsAdapter = _RecordingTtsAdapter();
    registry = ToolManifestRegistry(<NativeToolHandler>[
      VolumeSetToolHandler(volumeAdapter),
      ClipboardReadToolHandler(clipboardAdapter),
      BatteryInfoToolHandler(batteryAdapter),
      ContactReadToolHandler(contactAdapter),
      ContactCreateToolHandler(contactAdapter),
      SmsDraftToolHandler(draftMessageAdapter),
      EmailDraftToolHandler(draftMessageAdapter),
      FlashlightToggleToolHandler(flashlightAdapter),
      DndSetToolHandler(dndAdapter),
      LocationGetToolHandler(locationAdapter),
      MapsNavigateToolHandler(mapsAdapter),
      RegexEvalToolHandler(),
      MathEvalToolHandler(),
      TtsSpeakToolHandler(ttsAdapter),
      MemorySearchToolHandler(
        SemanticMemoryRetriever(
          storage: MemoryStorage(_NoopMemoryStorageBackend()),
          embedder: const _FixedSemanticEmbedder(<double>[1, 0, 0]),
        ),
      ),
    ]);
  });

  test('lists manifests and looks them up by id', () {
    final manifests = registry.listManifests();

    expect(manifests.length, 15);
    expect(manifests.map((manifest) => manifest.id), contains('contact_read'));
    expect(manifests.map((manifest) => manifest.id), contains('tts_speak'));
    expect(registry.manifestById('battery_info')?.category, 'system');
  });

  test('rejects missing and invalid arguments', () {
    final missing = registry.validate(
      const ToolInvocation(toolId: 'volume_set'),
    );
    final invalid = registry.validate(
      const ToolInvocation(
        toolId: 'dnd_set',
        arguments: <String, Object?>{'mode': 'silent'},
      ),
    );

    expect(missing.isValid, isFalse);
    expect(missing.error, 'missing_argument:level');
    expect(invalid.isValid, isFalse);
    expect(invalid.error, 'argument_not_allowed:mode');
  });

  test('volume_set normalizes level and invokes the adapter', () async {
    final result = await registry.execute(
      const ToolInvocation(
        toolId: 'volume_set',
        arguments: <String, Object?>{'level': 0.35},
      ),
      context: const ToolExecutionContext(
        sessionKey: 'agent:test',
        clock: null,
      ),
    );

    expect(volumeAdapter.lastLevel, 0.35);
    expect(result.content, 'Volume set to 35%.');
    expect(result.metadata['appliedLevel'], 0.35);
  });

  test('battery_info returns the expected metadata shape', () async {
    batteryAdapter.snapshot = const BatterySnapshot(
      level: 81,
      state: BatteryState.charging,
      isLowPowerMode: true,
    );

    final result = await registry.execute(
      const ToolInvocation(toolId: 'battery_info'),
    );

    expect(result.content, 'Battery at 81% (charging).');
    expect(result.metadata, containsPair('level', 81));
    expect(result.metadata, containsPair('state', 'charging'));
    expect(result.metadata, containsPair('isLowPowerMode', true));
  });

  test('contact_read returns structured permission errors', () async {
    contactAdapter.error = const ToolExecutionException(
      ToolExecutionError(
        code: ToolErrorCode.permissionDenied,
        message: 'Contacts permission denied.',
      ),
    );

    final result = await registry.execute(
      const ToolInvocation(toolId: 'contact_read'),
    );

    expect(result.isFailure, isTrue);
    expect(result.error?.id, 'permission_denied');
  });

  test(
    'regex_eval returns invalid argument failures for bad patterns',
    () async {
      final result = await registry.execute(
        const ToolInvocation(
          toolId: 'regex_eval',
          arguments: <String, Object?>{'pattern': '(', 'input': 'broken'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.error?.id, 'invalid_arguments');
    },
  );

  test('math_eval respects precedence and parentheses', () async {
    final result = await registry.execute(
      const ToolInvocation(
        toolId: 'math_eval',
        arguments: <String, Object?>{'expression': '2 * (3 + 4.5)'},
      ),
    );

    expect(result.metadata['result'], 15.0);
  });
}

class _FixedSemanticEmbedder implements SemanticTextEmbedder {
  const _FixedSemanticEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  String get modelId => 'test-embedder';

  @override
  Future<List<double>> embedDocument(String text) async => _embedding;

  @override
  Future<List<double>> embedQuery(String text) async => _embedding;
}

class _NoopMemoryStorageBackend implements MemoryStorageBackend {
  @override
  Future<void> close() async {}

  @override
  Future<void> deletePointer(String category) async {}

  @override
  Future<void> deleteRecord(String key) async {}

  @override
  Future<MemoryEmbeddingRecord?> fetchEmbedding(String key) async => null;

  @override
  Future<MemoryPointer?> fetchPointer(String category) async => null;

  @override
  Future<List<MemoryPointer>> fetchPointers() async => const <MemoryPointer>[];

  @override
  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async => null;

  @override
  Future<MemoryRecord?> fetchRecordByNormalizedContent(
    String normalizedContent, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async => null;

  @override
  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async => const <MemoryRecord>[];

  @override
  Future<MemoryReadResult> fetchRecordsWithReport({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async =>
      const MemoryReadResult(records: <MemoryRecord>[], skippedCount: 0);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> saveEmbedding(MemoryEmbeddingRecord record) async {}

  @override
  Future<MemoryMutationResult> saveRecordSafely(
    MemoryRecord record, {
    MemoryRecord? previousRecord,
    MemoryEmbeddingRecord? preparedEmbedding,
    Future<void> Function()? rebuildIndex,
  }) async {
    return MemoryMutationResult.success(
      message: 'noop',
      store: record.store,
      affectedKey: record.key,
    );
  }

  @override
  Future<void> savePointer(MemoryPointer pointer) async {}

  @override
  Future<void> saveRecord(MemoryRecord record) async {}

  @override
  Future<MemoryMutationResult> deleteRecordSafely(
    MemoryRecord record, {
    Future<void> Function()? rebuildIndex,
  }) async {
    return MemoryMutationResult.success(
      message: 'noop',
      store: record.store,
      affectedKey: record.key,
    );
  }

  @override
  Future<void> deleteRecords({
    MemoryStoreKind? store,
    bool includeExpired = true,
    String? category,
  }) async {}

  @override
  Future<MemoryMutationResult> deleteRecordsSafely(
    List<MemoryRecord> records, {
    Future<void> Function()? rebuildIndex,
  }) async {
    return MemoryMutationResult.success(
      message: 'noop',
      store: records.isEmpty ? MemoryStoreKind.shortTerm : records.first.store,
    );
  }

  @override
  Future<List<SemanticMemoryMatch>> searchByEmbedding({
    required List<double> queryEmbedding,
    int limit = 5,
    double threshold = 0,
    MemoryStoreKind? store,
    String? category,
    bool includeExpired = false,
  }) async => const <SemanticMemoryMatch>[];
}

class _RecordingVolumeAdapter implements DeviceVolumeAdapter {
  double? lastLevel;

  @override
  Future<double> setVolumeLevel(double normalizedLevel) async {
    lastLevel = normalizedLevel;
    return normalizedLevel;
  }
}

class _RecordingClipboardAdapter implements ClipboardAdapter {
  @override
  Future<String?> readClipboardText() async => null;

  @override
  Future<void> writeClipboardText(String text) async {}
}

class _RecordingBatteryAdapter implements BatteryAdapter {
  BatterySnapshot snapshot = const BatterySnapshot(
    level: 56,
    state: BatteryState.unknown,
  );

  @override
  Future<BatterySnapshot> readBatteryInfo() async => snapshot;
}

class _RecordingContactAdapter implements ContactAdapter {
  ToolExecutionException? error;

  @override
  Future<ContactRecord> createContact({
    required String displayName,
    String? phone,
    String? email,
  }) async {
    if (error != null) {
      throw error!;
    }
    return ContactRecord(displayName: displayName);
  }

  @override
  Future<List<ContactRecord>> searchContacts({
    String? query,
    required int limit,
  }) async {
    if (error != null) {
      throw error!;
    }
    return const <ContactRecord>[ContactRecord(displayName: 'Ali Veli')];
  }
}

class _RecordingDraftMessageAdapter implements DraftMessageAdapter {
  @override
  Future<void> openEmailDraft({
    String? to,
    String? subject,
    String? body,
  }) async {}

  @override
  Future<void> openSmsDraft({String? to, String? body}) async {}
}

class _RecordingFlashlightAdapter implements FlashlightAdapter {
  @override
  Future<bool> setEnabled(bool enabled) async => enabled;
}

class _RecordingDndAdapter implements DndAdapter {
  @override
  Future<DndMode> setMode(DndMode mode) async => mode;
}

class _RecordingLocationAdapter implements LocationAdapter {
  @override
  Future<LocationSnapshot> getCurrentLocation({
    required bool highAccuracy,
  }) async {
    return LocationSnapshot(
      latitude: 41.0,
      longitude: 29.0,
      provider: 'gps',
      timestamp: DateTime.utc(2026, 4, 7),
    );
  }
}

class _RecordingMapsAdapter implements MapsAdapter {
  @override
  Future<void> openNavigation({required String query}) async {}
}

class _RecordingTtsAdapter implements TtsAdapter {
  @override
  Future<void> speak({required String text, required bool interrupt}) async {}
}
