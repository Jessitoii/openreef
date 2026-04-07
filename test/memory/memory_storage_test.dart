import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late SqliteMemoryStorageBackend backend;

  setUp(() async {
    backend = SqliteMemoryStorageBackend(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    );
    storage = MemoryStorage(backend);
    await storage.initialize();
  });

  tearDown(() async {
    await storage.close();
  });

  test('saves and retrieves long-term and short-term memory records', () async {
    final now = DateTime.now().toUtc();
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_2026',
        content: 'Prefers concise answers.',
        category: 'user_prefs',
        importance: 5,
        createdAt: now,
      ),
    );
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.shortTerm,
        key: 'recent_fact',
        content: 'Asked about memory indexing today.',
        category: 'fact',
        importance: 2,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
      ),
    );

    final longTerm = await storage.readRecord(
      'prefs_2026',
      store: MemoryStoreKind.longTerm,
    );
    final shortTerm = await storage.readRecord(
      'recent_fact',
      store: MemoryStoreKind.shortTerm,
    );

    expect(longTerm?.content, 'Prefers concise answers.');
    expect(shortTerm?.content, 'Asked about memory indexing today.');
  });

  test('filters expired records from active reads', () async {
    final now = DateTime.now().toUtc();
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.episodic,
        key: 'session_old',
        content: 'Old compact summary',
        category: 'summary',
        importance: 2,
        createdAt: now.subtract(const Duration(days: 31)),
        expiresAt: now.subtract(const Duration(minutes: 5)),
      ),
    );

    final activeRecord = await storage.readRecord(
      'session_old',
      store: MemoryStoreKind.episodic,
    );
    final expiredRecord = await storage.readRecord(
      'session_old',
      store: MemoryStoreKind.episodic,
      includeExpired: true,
    );

    expect(activeRecord, isNull);
    expect(expiredRecord?.content, 'Old compact summary');
  });

  test('purges expired records during initialization lifecycle', () async {
    final directory = await Directory.systemTemp.createTemp('memory-purge-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final path = '${directory.path}${Platform.pathSeparator}memory.sqlite';
    final staleBackend = SqliteMemoryStorageBackend(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    final staleStorage = MemoryStorage(staleBackend);
    await staleStorage.initialize();
    await staleStorage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.episodic,
        key: 'expired_record',
        content: 'Should be deleted',
        category: 'summary',
        importance: 1,
        createdAt: DateTime.utc(2026, 4, 1),
        expiresAt: DateTime.utc(2026, 4, 2),
      ),
    );
    await staleStorage.close();

    final reopenedBackend = SqliteMemoryStorageBackend(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    final reopenedStorage = MemoryStorage(reopenedBackend);
    addTearDown(reopenedStorage.close);

    await reopenedStorage.initialize();
    final expired = await reopenedStorage.readRecord(
      'expired_record',
      store: MemoryStoreKind.episodic,
      includeExpired: true,
    );

    expect(expired, isNull);
  });
}
