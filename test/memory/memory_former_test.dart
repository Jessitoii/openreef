import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_fact.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/memory_turn.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late MemoryIndex index;
  late MemoryFormer former;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    index = MemoryIndex(storage);
    former = MemoryFormer(
      storage: storage,
      memoryIndex: index,
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test('writes durable memory and updates pointers for successful turns', () async {
    final occurredAt = DateTime.utc(2026, 4, 4, 16);
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'prefs_2026',
            fact: 'Prefers short responses.',
            category: 'user_prefs',
            importance: 4,
          ),
          MemoryFact(
            key: 'recent_topic',
            fact: 'Discussed memory architecture.',
            category: 'fact',
            importance: 2,
          ),
        ],
        hasFailedToolCalls: false,
        isAmbiguous: false,
        occurredAt: occurredAt,
      ),
    );

    final longTerm = await storage.readRecord(
      'prefs_2026',
      store: MemoryStoreKind.longTerm,
    );
    final shortTerm = await storage.readRecord(
      'recent_topic',
      store: MemoryStoreKind.shortTerm,
    );
    final pointerBlock = await index.toContextBlock();

    expect(longTerm?.content, 'Prefers short responses.');
    expect(shortTerm?.content, 'Discussed memory architecture.');
    expect(pointerBlock, contains('user_prefs       -> memory:prefs_2026'));
  });

  test('strict write discipline skips durable writes after failed tool calls', () async {
    final occurredAt = DateTime.utc(2026, 4, 4, 17);
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'prefs_failed',
            fact: 'Should never be stored long term.',
            category: 'user_prefs',
            importance: 5,
          ),
        ],
        hasFailedToolCalls: true,
        isAmbiguous: false,
        sessionKey: 'agent:main',
        occurredAt: occurredAt,
      ),
    );

    final durableRecord = await storage.readRecord(
      'prefs_failed',
      store: MemoryStoreKind.longTerm,
    );
    final guardRecord = await storage.readRecord(
      'agent:main_last_turn_status',
      store: MemoryStoreKind.shortTerm,
    );

    expect(durableRecord, isNull);
    expect(guardRecord?.content, 'error');
  });

  test('ambiguous turns are downgraded to short-term only', () async {
    final occurredAt = DateTime.utc(2026, 4, 4, 18);
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'work_projects',
            fact: 'Maybe the deadline moved to next week.',
            category: 'work_context',
            importance: 5,
          ),
        ],
        hasFailedToolCalls: false,
        isAmbiguous: true,
        occurredAt: occurredAt,
      ),
    );

    final longTerm = await storage.readRecord(
      'work_projects',
      store: MemoryStoreKind.longTerm,
    );
    final shortTerm = await storage.readRecord(
      'work_projects',
      store: MemoryStoreKind.shortTerm,
    );

    expect(longTerm, isNull);
    expect(shortTerm?.content, 'Maybe the deadline moved to next week.');
  });
}
