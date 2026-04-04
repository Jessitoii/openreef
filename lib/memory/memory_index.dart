import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';

/// Maintains lightweight pointers into long-term memory state.
class MemoryIndex {
  MemoryIndex(this._storage);

  final MemoryStorage _storage;

  Future<Map<String, String>> loadPointers() async {
    final pointers = await _storage.readPointers();
    return Map<String, String>.fromEntries(
      pointers.map(
        (pointer) => MapEntry<String, String>(pointer.category, pointer.pointer),
      ),
    );
  }

  Future<String> toContextBlock() async {
    final pointers = await loadPointers();
    final buffer = StringBuffer('[MEMORY INDEX]\n');
    for (final entry in pointers.entries) {
      buffer.writeln('${entry.key.padRight(16)} -> ${entry.value}');
    }
    buffer.write('[END INDEX]');
    return buffer.toString();
  }

  Future<String?> resolve(String pointer) async {
    final key = pointer.startsWith('memory:') ? pointer.substring(7) : pointer;
    for (final store in <MemoryStoreKind>[
      MemoryStoreKind.longTerm,
      MemoryStoreKind.episodic,
      MemoryStoreKind.shortTerm,
    ]) {
      final record = await _storage.readRecord(key, store: store);
      if (record != null) {
        return record.content;
      }
    }
    return null;
  }

  Future<void> updatePointer({
    required String category,
    required String memoryKey,
  }) {
    return _savePointer(category: category, memoryKey: memoryKey);
  }

  Future<void> updateSessionPointer({
    String category = 'last_session',
    required String memoryKey,
  }) {
    return _savePointer(category: category, memoryKey: memoryKey);
  }

  Future<void> _savePointer({
    required String category,
    required String memoryKey,
  }) {
    return _storage.savePointer(
      MemoryPointer(
        category: category,
        pointer: 'memory:$memoryKey',
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> rebuild() async {
    final records = await _storage.readRecords(store: MemoryStoreKind.longTerm);
    final selectedKeys = <String>{};

    for (final record in records) {
      if (record.category.isEmpty || selectedKeys.contains(record.category)) {
        continue;
      }

      selectedKeys.add(record.category);
      await updatePointer(
        category: record.category,
        memoryKey: record.key,
      );
    }
  }
}
