import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_store_kind.dart';

abstract class MemoryStorageBackend {
  Future<void> initialize();

  Future<void> saveRecord(MemoryRecord record);

  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<void> deleteRecord(String key);

  Future<void> savePointer(MemoryPointer pointer);

  Future<MemoryPointer?> fetchPointer(String category);

  Future<List<MemoryPointer>> fetchPointers();

  Future<void> deletePointer(String category);

  Future<void> close();
}
