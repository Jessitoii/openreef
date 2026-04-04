import 'package:openreef/memory/memory_fact.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/memory_turn.dart';

/// Shapes new memory entries before they are persisted.
class MemoryFormer {
  MemoryFormer({
    required MemoryStorage storage,
    required MemoryIndex memoryIndex,
  })  : _storage = storage,
        _memoryIndex = memoryIndex;

  static const Duration _shortTermTtl = Duration(hours: 24);

  final MemoryStorage _storage;
  final MemoryIndex _memoryIndex;

  Future<void> process(MemoryTurn turn) async {
    if (turn.hasFailedToolCalls) {
      await _storage.saveRecord(
        MemoryRecord(
          store: MemoryStoreKind.shortTerm,
          key: _statusKey(turn),
          content: 'error',
          category: 'turn_status',
          importance: 1,
          createdAt: turn.occurredAt,
          expiresAt: turn.occurredAt.add(_shortTermTtl),
          metadata: <String, Object?>{
            if (turn.sessionKey != null) 'session_key': turn.sessionKey,
          },
        ),
      );
      return;
    }

    final facts = turn.isAmbiguous
        ? turn.facts.map((fact) => fact.copyWith(importance: 1)).toList()
        : turn.facts;

    for (final fact in facts) {
      await _persistFact(fact, occurredAt: turn.occurredAt);
    }
  }

  Future<void> _persistFact(
    MemoryFact fact, {
    required DateTime occurredAt,
  }) async {
    final store = fact.importance >= 3
        ? MemoryStoreKind.longTerm
        : MemoryStoreKind.shortTerm;
    final expiresAt =
        store == MemoryStoreKind.shortTerm ? occurredAt.add(_shortTermTtl) : null;

    await _storage.saveRecord(
      MemoryRecord(
        store: store,
        key: fact.key,
        content: fact.fact,
        category: fact.category,
        importance: fact.importance,
        createdAt: occurredAt,
        expiresAt: expiresAt,
        metadata: fact.metadata,
      ),
    );

    if (store == MemoryStoreKind.longTerm && fact.category.isNotEmpty) {
      await _memoryIndex.updatePointer(
        category: fact.category,
        memoryKey: fact.key,
      );
    }
  }

  String _statusKey(MemoryTurn turn) {
    if (turn.sessionKey == null || turn.sessionKey!.isEmpty) {
      return 'last_turn_status';
    }

    return '${turn.sessionKey}_last_turn_status';
  }
}
