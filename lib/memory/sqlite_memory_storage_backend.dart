import 'dart:math';
import 'dart:typed_data';

import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:sqflite/sqflite.dart';

class SqliteMemoryStorageBackend implements MemoryStorageBackend {
  SqliteMemoryStorageBackend({
    required this.path,
    DatabaseFactory? databaseFactory,
  }) : _databaseFactory = databaseFactory ?? databaseFactorySqflitePlugin;

  static const String memoryTable = 'memories';
  static const String pointerTable = 'memory_pointers';
  static const String embeddingTable = 'memory_embeddings';

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
        version: 2,
        onCreate: (Database database, int version) async {
          await _createTables(database);
        },
        onUpgrade: (Database database, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await _createEmbeddingTable(database);
          }
        },
      ),
    );
    await purgeExpiredRecords();
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
      whereArgs: _recordsWhereArgs(
        store: store,
        includeExpired: includeExpired,
      ),
      orderBy: 'category ASC, importance DESC, created_at DESC',
    );

    return rows.map(MemoryRecord.fromDatabaseMap).toList();
  }

  @override
  Future<void> saveEmbedding(MemoryEmbeddingRecord record) async {
    final database = await _requireDatabase();
    await database.insert(embeddingTable, <String, Object?>{
      'memory_key': record.memoryKey,
      'model_id': record.modelId,
      'embedding': record.toBlob(),
      'normalized_content': record.normalizedContent,
      'updated_at': record.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> purgeExpiredRecords() async {
    final database = await _requireDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    final expiredRows = await database.query(
      memoryTable,
      columns: <String>['memory_key'],
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: <Object?>[now],
    );
    if (expiredRows.isEmpty) {
      return;
    }
    final keys = expiredRows
        .map((row) => row['memory_key'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final batch = database.batch();
    for (final key in keys) {
      batch.delete(
        embeddingTable,
        where: 'memory_key = ?',
        whereArgs: <Object?>[key],
      );
      batch.delete(
        memoryTable,
        where: 'memory_key = ?',
        whereArgs: <Object?>[key],
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<MemoryEmbeddingRecord?> fetchEmbedding(String key) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      embeddingTable,
      where: 'memory_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.single;
    return MemoryEmbeddingRecord(
      memoryKey: row['memory_key'] as String? ?? '',
      modelId: row['model_id'] as String? ?? '',
      embedding: MemoryEmbeddingRecord.fromBlob(row['embedding'] as Uint8List),
      normalizedContent: row['normalized_content'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Future<MemoryRecord?> fetchRecordByNormalizedContent(
    String normalizedContent, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) async {
    final database = await _requireDatabase();
    final clauses = <String>[
      'e.normalized_content = ?',
      if (store != null) 'm.store_kind = ?',
      if (!includeExpired) '(m.expires_at IS NULL OR m.expires_at > ?)',
    ];
    final args = <Object?>[
      normalizedContent,
      if (store != null) store.value,
      if (!includeExpired) DateTime.now().toUtc().toIso8601String(),
    ];
    final rows = await database.rawQuery('''
      SELECT m.*
      FROM $memoryTable m
      INNER JOIN $embeddingTable e ON e.memory_key = m.memory_key
      WHERE ${clauses.join(' AND ')}
      ORDER BY m.importance DESC, m.created_at DESC
      LIMIT 1
      ''', args);
    if (rows.isEmpty) {
      return null;
    }
    return MemoryRecord.fromDatabaseMap(rows.single);
  }

  @override
  Future<List<SemanticMemoryMatch>> searchByEmbedding({
    required List<double> queryEmbedding,
    int limit = 5,
    double threshold = 0,
    MemoryStoreKind? store,
    String? category,
    bool includeExpired = false,
  }) async {
    final database = await _requireDatabase();
    final clauses = <String>[
      if (store != null) 'm.store_kind = ?',
      if (category != null && category.isNotEmpty) 'm.category = ?',
      if (!includeExpired) '(m.expires_at IS NULL OR m.expires_at > ?)',
    ];
    final args = <Object?>[
      if (store != null) store.value,
      if (category != null && category.isNotEmpty) category,
      if (!includeExpired) DateTime.now().toUtc().toIso8601String(),
    ];
    final whereClause = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await database.rawQuery('''
      SELECT m.*, e.embedding
      FROM $memoryTable m
      INNER JOIN $embeddingTable e ON e.memory_key = m.memory_key
      $whereClause
      ''', args);

    final matches = <SemanticMemoryMatch>[];
    for (final row in rows) {
      final embedding = MemoryEmbeddingRecord.fromBlob(
        row['embedding'] as Uint8List,
      );
      if (embedding.length != queryEmbedding.length) {
        continue;
      }
      final similarity = _cosineSimilarity(queryEmbedding, embedding);
      if (similarity < threshold) {
        continue;
      }
      matches.add(
        SemanticMemoryMatch(
          record: MemoryRecord.fromDatabaseMap(row),
          score: similarity,
        ),
      );
    }

    matches.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final importanceCompare = right.record.importance.compareTo(
        left.record.importance,
      );
      if (importanceCompare != 0) {
        return importanceCompare;
      }
      return right.record.createdAt.compareTo(left.record.createdAt);
    });

    if (matches.length <= limit) {
      return matches;
    }
    return matches.take(limit).toList(growable: false);
  }

  @override
  Future<void> deleteRecord(String key) async {
    final database = await _requireDatabase();
    await database.delete(
      embeddingTable,
      where: 'memory_key = ?',
      whereArgs: <Object?>[key],
    );
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
    final rows = await database.query(pointerTable, orderBy: 'category ASC');

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

  Future<void> _createTables(Database database) async {
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
    await _createEmbeddingTable(database);
  }

  Future<void> _createEmbeddingTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $embeddingTable (
        memory_key TEXT PRIMARY KEY,
        model_id TEXT NOT NULL,
        embedding BLOB NOT NULL,
        normalized_content TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_${embeddingTable}_normalized
      ON $embeddingTable(normalized_content)
    ''');
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

  double _cosineSimilarity(List<double> left, List<double> right) {
    var dot = 0.0;
    var leftMagnitude = 0.0;
    var rightMagnitude = 0.0;

    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftMagnitude += left[index] * left[index];
      rightMagnitude += right[index] * right[index];
    }

    if (leftMagnitude == 0 || rightMagnitude == 0) {
      return 0;
    }

    return dot / (sqrt(leftMagnitude) * sqrt(rightMagnitude));
  }
}
