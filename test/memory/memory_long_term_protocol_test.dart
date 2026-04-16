import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/ui/memory_management_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String path;

  Future<MemoryStorage> openStorage() async {
    final backend = SqliteMemoryStorageBackend(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    final storage = MemoryStorage(backend);
    await storage.initialize();
    return storage;
  }

  MemoryEmbeddingRecord embeddingFor(MemoryRecord record) {
    return MemoryEmbeddingRecord(
      memoryKey: record.key,
      modelId: 'test-model',
      embedding: const <double>[0.1, 0.2, 0.3, 0.4],
      normalizedContent: record.content.toLowerCase(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'openreef-memory-protocol-',
    );
    path = '${directory.path}${Platform.pathSeparator}memory.sqlite';
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('long-term create rolls back when index rebuild fails', () async {
    final storage = await openStorage();
    final record = MemoryRecord(
      store: MemoryStoreKind.longTerm,
      key: 'lt-create',
      content: 'Semantic memory',
      category: 'prefs',
      importance: 5,
      createdAt: DateTime.now().toUtc(),
    );

    final result = await storage.saveRecordSafely(
      record,
      preparedEmbedding: embeddingFor(record),
      rebuildIndex: () async => throw Exception('index failed'),
    );

    expect(result.status, MemoryMutationStatus.failedRolledBack);
    expect(
      await storage.readRecord('lt-create', store: MemoryStoreKind.longTerm),
      isNull,
    );
    await storage.close();
  });

  test(
    'long-term edit without key change rolls back on index rebuild failure',
    () async {
      final storage = await openStorage();
      final original = MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'lt-edit',
        content: 'Original content',
        category: 'prefs',
        importance: 3,
        createdAt: DateTime.now().toUtc(),
      );
      await storage.saveRecordSafely(
        original,
        preparedEmbedding: embeddingFor(original),
        rebuildIndex: () async {},
      );

      final updated = original.copyWith(
        content: 'Updated content',
        importance: 4,
      );
      final result = await storage.saveRecordSafely(
        updated,
        previousRecord: original,
        preparedEmbedding: embeddingFor(updated),
        rebuildIndex: () async => throw Exception('index failed'),
      );

      expect(result.status, MemoryMutationStatus.failedRolledBack);
      final reloaded = await storage.readRecord(
        'lt-edit',
        store: MemoryStoreKind.longTerm,
      );
      expect(reloaded?.content, 'Original content');
      expect(reloaded?.importance, 3);
      await storage.close();
    },
  );

  test(
    'long-term key change rolls back cleanly on index rebuild failure',
    () async {
      final storage = await openStorage();
      final original = MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'lt-old',
        content: 'Original content',
        category: 'prefs',
        importance: 3,
        createdAt: DateTime.now().toUtc(),
      );
      await storage.saveRecordSafely(
        original,
        preparedEmbedding: embeddingFor(original),
        rebuildIndex: () async {},
      );

      final replacement = original.copyWith(
        key: 'lt-new',
        content: 'Replacement content',
        importance: 5,
      );
      final result = await storage.saveRecordSafely(
        replacement,
        previousRecord: original,
        preparedEmbedding: embeddingFor(replacement),
        rebuildIndex: () async => throw Exception('index failed'),
      );

      expect(result.status, MemoryMutationStatus.failedRolledBack);
      expect(
        await storage.readRecord('lt-old', store: MemoryStoreKind.longTerm),
        isNotNull,
      );
      expect(
        await storage.readRecord('lt-new', store: MemoryStoreKind.longTerm),
        isNull,
      );
      await storage.close();
    },
  );

  test('long-term delete rolls back when index rebuild fails', () async {
    final storage = await openStorage();
    final record = MemoryRecord(
      store: MemoryStoreKind.longTerm,
      key: 'lt-delete',
      content: 'Delete me',
      category: 'prefs',
      importance: 2,
      createdAt: DateTime.now().toUtc(),
    );
    await storage.saveRecordSafely(
      record,
      preparedEmbedding: embeddingFor(record),
      rebuildIndex: () async {},
    );

    final result = await storage.deleteRecordSafely(
      record,
      rebuildIndex: () async => throw Exception('index failed'),
    );

    expect(result.status, MemoryMutationStatus.failedRolledBack);
    expect(
      await storage.readRecord('lt-delete', store: MemoryStoreKind.longTerm),
      isNotNull,
    );
    await storage.close();
  });

  test('store immutability is rejected below the UI layer', () async {
    final storage = await openStorage();
    final original = MemoryRecord(
      store: MemoryStoreKind.shortTerm,
      key: 'mutable-store',
      content: 'Short term',
      category: 'turn',
      importance: 1,
      createdAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await storage.saveRecord(original);

    final illegalEdit = original.copyWith(store: MemoryStoreKind.longTerm);
    final result = await storage.saveRecordSafely(
      illegalEdit,
      previousRecord: original,
      rebuildIndex: () async {},
    );

    expect(result.status, MemoryMutationStatus.failedNoWrite);
    final reloaded = await storage.readRecord(
      'mutable-store',
      store: MemoryStoreKind.shortTerm,
    );
    expect(reloaded?.store, MemoryStoreKind.shortTerm);
    await storage.close();
  });

  test(
    'bulk delete deletes the full filtered set, not the visible cap',
    () async {
      final storage = await openStorage();
      final index = MemoryIndex(storage);
      final controller = MemoryManagementController(
        storage: storage,
        memoryIndex: index,
      );
      await controller.initialize();

      final now = DateTime.now().toUtc();
      for (var i = 0; i < 301; i++) {
        await storage.saveRecord(
          MemoryRecord(
            store: MemoryStoreKind.shortTerm,
            key: 'short-$i',
            content: 'Record $i',
            category: 'bulk',
            importance: 1,
            createdAt: now.subtract(Duration(minutes: i)),
            expiresAt: now.add(const Duration(hours: 1)),
          ),
        );
      }

      await controller.reload();
      expect(controller.visibleRecords.length, 300);
      expect(controller.filteredRecords.length, 301);

      await controller.bulkDelete(category: 'bulk');

      await controller.reload();
      expect(controller.allRecords, isEmpty);
      await storage.close();
    },
  );

  test('corrupted rows are skipped during load without crashing', () async {
    final initialStorage = await openStorage();
    await initialStorage.close();

    final database = await databaseFactoryFfi.openDatabase(path);
    await database.insert(
      SqliteMemoryStorageBackend.memoryTable,
      <String, Object?>{
        'store_kind': MemoryStoreKind.shortTerm.value,
        'memory_key': 'bad-row',
        'content': 'broken',
        'category': 'bad',
        'importance': 1,
        'created_at': 'not-a-date',
        'expires_at': null,
        'metadata': '{broken-json}',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await database.close();

    final storage = await openStorage();
    final controller = MemoryManagementController(
      storage: storage,
      memoryIndex: MemoryIndex(storage),
    );
    await controller.initialize();
    expect(controller.warningMessage, isNotNull);
    expect(controller.warningMessage, contains('corrupted memory row'));
    expect(controller.allRecords, isEmpty);
    await storage.close();
  });
}
