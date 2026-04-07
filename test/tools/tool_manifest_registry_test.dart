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
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';

void main() {
  late _RecordingVolumeAdapter volumeAdapter;
  late _RecordingClipboardAdapter clipboardAdapter;
  late _RecordingBatteryAdapter batteryAdapter;
  late ToolManifestRegistry registry;

  setUp(() {
    volumeAdapter = _RecordingVolumeAdapter();
    clipboardAdapter = _RecordingClipboardAdapter();
    batteryAdapter = _RecordingBatteryAdapter();
    registry = ToolManifestRegistry(
      createMvpNativeToolHandlers(
        volumeAdapter: volumeAdapter,
        clipboardAdapter: clipboardAdapter,
        batteryAdapter: batteryAdapter,
        memoryRetriever: SemanticMemoryRetriever(
          storage: MemoryStorage(_NoopMemoryStorageBackend()),
          embedder: const _FixedSemanticEmbedder(<double>[1, 0, 0]),
        ),
      ),
    );
  });

  test('lists manifests and looks them up by id', () {
    final manifests = registry.listManifests();

    expect(manifests.length, 4);
    expect(manifests.map((manifest) => manifest.id), contains('volume_set'));
    expect(manifests.map((manifest) => manifest.id), contains('memory_search'));
    expect(registry.manifestById('battery_info')?.category, 'system');
  });

  test('rejects missing and invalid arguments', () {
    final missing = registry.validate(
      const ToolInvocation(toolId: 'volume_set'),
    );
    final invalid = registry.validate(
      const ToolInvocation(
        toolId: 'volume_set',
        arguments: <String, Object?>{'level': 'loud'},
      ),
    );

    expect(missing.isValid, isFalse);
    expect(missing.error, 'missing_argument:level');
    expect(invalid.isValid, isFalse);
    expect(invalid.error, 'invalid_argument:level');
  });

  test('rejects disabled tools before execution', () {
    final disabledRegistry = ToolManifestRegistry(<NativeToolHandler>[
      _DisabledToolHandler(),
    ]);

    final validation = disabledRegistry.validate(
      const ToolInvocation(toolId: 'disabled_tool'),
    );

    expect(validation.isValid, isFalse);
    expect(validation.error, 'disabled_tool:disabled_tool');
  });

  test('volume_set normalizes level and invokes the adapter', () async {
    final result = await registry.execute(
      const ToolInvocation(
        toolId: 'volume_set',
        arguments: <String, Object?>{'level': 0.35},
      ),
      context: NativeToolContext(clock: () => DateTime.utc(2026, 4, 4, 12)),
    );

    expect(volumeAdapter.lastLevel, 0.35);
    expect(result.content, 'Volume set to 35%.');
    expect(result.metadata['appliedLevel'], 0.35);
    expect(result.metadata['toolId'], 'volume_set');
  });

  test('clipboard_read returns an explicit empty result', () async {
    clipboardAdapter.text = '';

    final result = await registry.execute(
      const ToolInvocation(toolId: 'clipboard_read'),
    );

    expect(result.content, 'Clipboard is empty.');
    expect(result.metadata['hasContent'], isFalse);
    expect(result.metadata['text'], '');
  });

  test('clipboard_read returns text when available', () async {
    clipboardAdapter.text = 'copied value';

    final result = await registry.execute(
      const ToolInvocation(toolId: 'clipboard_read'),
    );

    expect(result.content, 'copied value');
    expect(result.metadata['hasContent'], isTrue);
    expect(result.metadata['text'], 'copied value');
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
  Future<void> initialize() async {}

  @override
  Future<void> saveEmbedding(MemoryEmbeddingRecord record) async {}

  @override
  Future<void> savePointer(MemoryPointer pointer) async {}

  @override
  Future<void> saveRecord(MemoryRecord record) async {}

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
  String? text;

  @override
  Future<String?> readClipboardText() async => text;
}

class _RecordingBatteryAdapter implements BatteryAdapter {
  BatterySnapshot snapshot = const BatterySnapshot(
    level: 56,
    state: BatteryState.unknown,
  );

  @override
  Future<BatterySnapshot> readBatteryInfo() async => snapshot;
}

class _DisabledToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'disabled_tool',
    description: 'Disabled for testing.',
    category: 'system',
    enabled: false,
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    NativeToolContext context,
  ) {
    throw UnimplementedError();
  }
}
