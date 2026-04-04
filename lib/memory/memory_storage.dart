import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';

class MemoryStorage {
  MemoryStorage(this._backend);

  final MemoryStorageBackend _backend;

  Future<void> initialize() => _backend.initialize();

  Future<void> saveRecord(MemoryRecord record) => _backend.saveRecord(record);

  Future<MemoryRecord?> readRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecord(
      key,
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<List<MemoryRecord>> readRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecords(
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<void> deleteRecord(String key) => _backend.deleteRecord(key);

  Future<void> savePointer(MemoryPointer pointer) => _backend.savePointer(pointer);

  Future<MemoryPointer?> readPointer(String category) {
    return _backend.fetchPointer(category);
  }

  Future<List<MemoryPointer>> readPointers() => _backend.fetchPointers();

  Future<void> deletePointer(String category) => _backend.deletePointer(category);

  Future<void> close() => _backend.close();
}
