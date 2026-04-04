import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:sqflite/sqflite.dart';

class SqliteMemoryStorageBackend implements MemoryStorageBackend {
  SqliteMemoryStorageBackend({
    required this.path,
    DatabaseFactory? databaseFactory,
  }) : _databaseFactory = databaseFactory ?? databaseFactorySqflitePlugin;

  static const String memoryTable = 'memories';
  static const String pointerTable = 'memory_pointers';

  final String path;
  final DatabaseFactory _databaseFactory;

  Database? _database;

  @override
  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    _database = await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database database, int version) async {
          await database.execute('''
            CREATE TABLE $memoryTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_kind TEXT NOT NULL,
              memory_key TEXT NOT NULL UNIQUE,
              content TEXT NOT NULL,
              category TEXT NOT NULL,
              importance INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              expires_at TEXT,
              metadata TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE $pointerTable (
              category TEXT PRIMARY KEY,
              pointer TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
  }

  @override
  Future<void> saveRecord(MemoryRecord record) async {
    final database = await _requireDatabase();
    await database.insert(
      memoryTable,
      record.toDatabaseMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      memoryTable,
      where: _recordWhereClause(store: store, includeExpired: includeExpired),
      whereArgs: _recordWhereArgs(
        key: key,
        store: store,
        includeExpired: includeExpired,
      ),
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MemoryRecord.fromDatabaseMap(rows.single);
  }

  @override
  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      memoryTable,
      where: _recordsWhereClause(store: store, includeExpired: includeExpired),
      whereArgs: _recordsWhereArgs(store: store, includeExpired: includeExpired),
      orderBy: 'category ASC, importance DESC, created_at DESC',
    );

    return rows.map(MemoryRecord.fromDatabaseMap).toList();
  }

  @override
  Future<void> deleteRecord(String key) async {
    final database = await _requireDatabase();
    await database.delete(
      memoryTable,
      where: 'memory_key = ?',
      whereArgs: <Object?>[key],
    );
  }

  @override
  Future<void> savePointer(MemoryPointer pointer) async {
    final database = await _requireDatabase();
    await database.insert(
      pointerTable,
      pointer.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<MemoryPointer?> fetchPointer(String category) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      pointerTable,
      where: 'category = ?',
      whereArgs: <Object?>[category],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MemoryPointer.fromDatabaseMap(rows.single);
  }

  @override
  Future<List<MemoryPointer>> fetchPointers() async {
    final database = await _requireDatabase();
    final rows = await database.query(
      pointerTable,
      orderBy: 'category ASC',
    );

    return rows.map(MemoryPointer.fromDatabaseMap).toList();
  }

  @override
  Future<void> deletePointer(String category) async {
    final database = await _requireDatabase();
    await database.delete(
      pointerTable,
      where: 'category = ?',
      whereArgs: <Object?>[category],
    );
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _requireDatabase() async {
    await initialize();
    return _database!;
  }

  String _recordWhereClause({
    required MemoryStoreKind? store,
    required bool includeExpired,
  }) {
    final clauses = <String>['memory_key = ?'];
    if (store != null) {
      clauses.add('store_kind = ?');
    }
    if (!includeExpired) {
      clauses.add('(expires_at IS NULL OR expires_at > ?)');
    }
    return clauses.join(' AND ');
  }

  List<Object?> _recordWhereArgs({
    required String key,
    required MemoryStoreKind? store,
    required bool includeExpired,
  }) {
    final args = <Object?>[key];
    if (store != null) {
      args.add(store.value);
    }
    if (!includeExpired) {
      args.add(DateTime.now().toUtc().toIso8601String());
    }
    return args;
  }

  String? _recordsWhereClause({
    required MemoryStoreKind? store,
    required bool includeExpired,
  }) {
    final clauses = <String>[];
    if (store != null) {
      clauses.add('store_kind = ?');
    }
    if (!includeExpired) {
      clauses.add('(expires_at IS NULL OR expires_at > ?)');
    }
    if (clauses.isEmpty) {
      return null;
    }
    return clauses.join(' AND ');
  }

  List<Object?>? _recordsWhereArgs({
    required MemoryStoreKind? store,
    required bool includeExpired,
  }) {
    final args = <Object?>[];
    if (store != null) {
      args.add(store.value);
    }
    if (!includeExpired) {
      args.add(DateTime.now().toUtc().toIso8601String());
    }
    if (args.isEmpty) {
      return null;
    }
    return args;
  }
}
