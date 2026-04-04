import 'dart:io';

import 'package:openreef/memory/chat_message_record.dart';
import 'package:openreef/memory/chat_session_record.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ChatSessionRepository {
  ChatSessionRepository({
    String? path,
    DatabaseFactory? databaseFactory,
  }) : _path = path,
       _databaseFactory = databaseFactory;

  static const String _databaseName = 'openreef_chat_sessions.sqlite';
  static const String _sessionsTable = 'chat_sessions';
  static const String _messagesTable = 'chat_messages';

  final String? _path;
  final DatabaseFactory? _databaseFactory;

  Database? _database;

  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    final factory = _databaseFactory ?? _resolveDatabaseFactory();
    final path = _path ?? await _defaultDatabasePath(factory);
    _database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE $_sessionsTable (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              last_modified TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE $_messagesTable (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              sender TEXT NOT NULL,
              text TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              position INTEGER NOT NULL,
              is_streaming INTEGER NOT NULL,
              FOREIGN KEY(session_id) REFERENCES $_sessionsTable(id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE INDEX idx_chat_messages_session_position
            ON $_messagesTable(session_id, position)
          ''');
        },
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  Future<List<ChatSessionRecord>> fetchSessions() async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _sessionsTable,
      orderBy: 'last_modified DESC',
    );
    return rows.map(ChatSessionRecord.fromDatabaseMap).toList();
  }

  Future<List<ChatTranscriptMessage>> fetchMessages(String sessionId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _messagesTable,
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'position ASC',
    );
    return rows
        .map(ChatMessageRecord.fromDatabaseMap)
        .map((record) => record.toTranscriptMessage())
        .toList();
  }

  Future<void> saveSession({
    required ChatSessionRecord session,
    required List<ChatTranscriptMessage> messages,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((transaction) async {
      await transaction.insert(
        _sessionsTable,
        session.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        _messagesTable,
        where: 'session_id = ?',
        whereArgs: <Object?>[session.id],
      );
      for (var index = 0; index < messages.length; index++) {
        final record = ChatMessageRecord.fromTranscriptMessage(
          sessionId: session.id,
          position: index,
          message: messages[index],
        );
        await transaction.insert(
          _messagesTable,
          record.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final database = await _requireDatabase();
    await database.delete(
      _sessionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _requireDatabase() async {
    await initialize();
    return _database!;
  }

  DatabaseFactory _resolveDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactorySqflitePlugin;
  }

  Future<String> _defaultDatabasePath(DatabaseFactory factory) async {
    final basePath = await factory.getDatabasesPath();
    final separator = Platform.pathSeparator;
    return '$basePath${basePath.endsWith(separator) ? '' : separator}$_databaseName';
  }
}
