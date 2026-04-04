import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late MemoryIndex index;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    index = MemoryIndex(storage);
  });

  tearDown(() async {
    await storage.close();
  });

  test('serializes the MEMORY.md pointer block deterministically', () async {
    final now = DateTime.utc(2026, 4, 4, 14);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'contacts_vip',
        content: 'Ali and Zeynep are priority contacts.',
        category: 'contacts_key',
        importance: 4,
        createdAt: now,
      ),
    );
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_2026',
        content: 'User prefers Turkish UI labels.',
        category: 'user_prefs',
        importance: 5,
        createdAt: now,
      ),
    );

    await index.rebuild();

    final block = await index.toContextBlock();

    expect(
      block,
      '[MEMORY INDEX]\n'
      'contacts_key     -> memory:contacts_vip\n'
      'user_prefs       -> memory:prefs_2026\n'
      '[END INDEX]',
    );
  });

  test('resolves a memory pointer to the stored content', () async {
    final now = DateTime.utc(2026, 4, 4, 15);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'work_projects',
        content: 'OpenReef memory system is the active project.',
        category: 'work_context',
        importance: 5,
        createdAt: now,
      ),
    );
    await index.updatePointer(
      category: 'work_context',
      memoryKey: 'work_projects',
    );

    final resolved = await index.resolve('memory:work_projects');

    expect(resolved, 'OpenReef memory system is the active project.');
  });
}
