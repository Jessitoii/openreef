import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/background/auto_dream_run_result.dart';
import 'package:openreef/background/auto_dream_worker.dart';
import 'package:openreef/memory/chat_session_record.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late ChatSessionRepository sessionRepository;
  late MemoryStorage memoryStorage;
  late MemoryIndex memoryIndex;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('auto-dream-worker-');
    sessionRepository = ChatSessionRepository(
      path: '${directory.path}${Platform.pathSeparator}chat.sqlite',
      databaseFactory: databaseFactoryFfi,
    );
    await sessionRepository.initialize();

    memoryStorage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: '${directory.path}${Platform.pathSeparator}memory.sqlite',
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await memoryStorage.initialize();
    memoryIndex = MemoryIndex(memoryStorage);
  });

  tearDown(() async {
    await sessionRepository.close();
    await memoryStorage.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('creates episodic memories for unsummarized sessions and updates last_session', () async {
    await sessionRepository.saveSession(
      session: ChatSessionRecord(
        id: 'session-a',
        title: 'Planning Chat',
        lastModified: DateTime(2026, 4, 5, 10, 03),
      ),
      messages: <ChatTranscriptMessage>[
        ChatTranscriptMessage(
          id: 'msg-1',
          sender: ChatMessageSender.user,
          text: 'Plan the AutoDream worker implementation.',
          timestamp: DateTime(2026, 4, 5, 10, 00),
        ),
        ChatTranscriptMessage(
          id: 'msg-2',
          sender: ChatMessageSender.assistant,
          text: 'We should summarize unsaved chat history into episodic memories.',
          timestamp: DateTime(2026, 4, 5, 10, 01),
        ),
        ChatTranscriptMessage(
          id: 'msg-3',
          sender: ChatMessageSender.user,
          text: 'Next, check analyzer output?',
          timestamp: DateTime(2026, 4, 5, 10, 03),
        ),
      ],
    );

    final worker = AutoDreamWorker(
      chatSessionRepository: sessionRepository,
      memoryStorage: memoryStorage,
      memoryIndex: memoryIndex,
      now: () => DateTime.utc(2026, 4, 5, 11),
    );

    final result = await worker.runConsolidation();
    final episodicRecords = await memoryStorage.readRecords(
      store: MemoryStoreKind.episodic,
    );
    final pointer = await memoryIndex.loadPointers();
    final resolved = await memoryIndex.resolve(pointer['last_session']!);

    expect(result.status, AutoDreamRunStatus.completed);
    expect(result.sessionsSummarized, 1);
    expect(episodicRecords, hasLength(1));
    expect(episodicRecords.single.content, contains('[EPISODIC MEMORY] Planning Chat'));
    expect(episodicRecords.single.content, contains('Pending: Next, check analyzer output?'));
    expect(pointer['last_session'], 'memory:${episodicRecords.single.key}');
    expect(resolved, episodicRecords.single.content);
  });

  test('skips sessions with no stable unsummarized messages and stays idempotent', () async {
    await sessionRepository.saveSession(
      session: ChatSessionRecord(
        id: 'session-b',
        title: 'Noisy Chat',
        lastModified: DateTime(2026, 4, 5, 12, 00),
      ),
      messages: <ChatTranscriptMessage>[
        ChatTranscriptMessage(
          id: 'msg-1',
          sender: ChatMessageSender.system,
          text: 'OPENREEF READY',
          timestamp: DateTime(2026, 4, 5, 12, 00),
        ),
        ChatTranscriptMessage(
          id: 'msg-2',
          sender: ChatMessageSender.assistant,
          text: 'Streaming',
          timestamp: DateTime(2026, 4, 5, 12, 01),
          isStreaming: true,
        ),
      ],
    );

    final worker = AutoDreamWorker(
      chatSessionRepository: sessionRepository,
      memoryStorage: memoryStorage,
      memoryIndex: memoryIndex,
      now: () => DateTime.utc(2026, 4, 5, 13),
    );

    final firstRun = await worker.runConsolidation();
    final secondRun = await worker.runConsolidation();
    final episodicRecords = await memoryStorage.readRecords(
      store: MemoryStoreKind.episodic,
    );

    expect(firstRun.sessionsSummarized, 0);
    expect(secondRun.sessionsSummarized, 0);
    expect(episodicRecords, isEmpty);
  });

  test('returns skipped when another consolidation is already running', () async {
    await sessionRepository.saveSession(
      session: ChatSessionRecord(
        id: 'session-c',
        title: 'Concurrency Chat',
        lastModified: DateTime(2026, 4, 5, 14, 00),
      ),
      messages: <ChatTranscriptMessage>[
        ChatTranscriptMessage(
          id: 'msg-1',
          sender: ChatMessageSender.user,
          text: 'Need a background-safe API.',
          timestamp: DateTime(2026, 4, 5, 14, 00),
        ),
      ],
    );

    final slowMemoryStorage = MemoryStorage(
      _SlowMemoryStorageBackend(
        SqliteMemoryStorageBackend(
          path: '${directory.path}${Platform.pathSeparator}slow-memory.sqlite',
          databaseFactory: databaseFactoryFfi,
        ),
      ),
    );
    await slowMemoryStorage.initialize();
    addTearDown(slowMemoryStorage.close);
    final worker = AutoDreamWorker(
      chatSessionRepository: sessionRepository,
      memoryStorage: slowMemoryStorage,
      memoryIndex: MemoryIndex(slowMemoryStorage),
      now: () => DateTime.utc(2026, 4, 5, 15),
    );

    final firstRun = worker.runConsolidation();
    final secondRun = await worker.runConsolidation();
    await firstRun;

    expect(secondRun.status, AutoDreamRunStatus.skippedAlreadyRunning);
  });
}

class _SlowMemoryStorageBackend implements MemoryStorageBackend {
  _SlowMemoryStorageBackend(this._delegate);

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<void> saveRecord(MemoryRecord record) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _delegate.saveRecord(record);
  }

  @override
  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _delegate.fetchRecord(
      key,
      store: store,
      includeExpired: includeExpired,
    );
  }

  @override
  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _delegate.fetchRecords(store: store, includeExpired: includeExpired);
  }

  @override
  Future<void> deleteRecord(String key) => _delegate.deleteRecord(key);

  @override
  Future<void> savePointer(MemoryPointer pointer) => _delegate.savePointer(pointer);

  @override
  Future<MemoryPointer?> fetchPointer(String category) {
    return _delegate.fetchPointer(category);
  }

  @override
  Future<List<MemoryPointer>> fetchPointers() => _delegate.fetchPointers();

  @override
  Future<void> deletePointer(String category) => _delegate.deletePointer(category);

  @override
  Future<void> close() => _delegate.close();

  final MemoryStorageBackend _delegate;
}
