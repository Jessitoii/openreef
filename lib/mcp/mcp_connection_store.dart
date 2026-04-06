import 'dart:convert';

import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';

class McpConnectionStore {
  McpConnectionStore(this._storage);

  final MemoryStorage _storage;

  Future<void> save(String url) async {
    final record = MemoryRecord(
      store: MemoryStoreKind.mcpConnections,
      key: _keyFor(url),
      content: jsonEncode(<String, Object?>{
        'url': url,
        'persistedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      category: 'mcp_connection',
      importance: 0,
      createdAt: DateTime.now().toUtc(),
    );
    await _storage.saveRecord(record);
  }

  Future<void> delete(String url) async {
    await _storage.deleteRecord(_keyFor(url));
  }

  Future<List<String>> loadAll() async {
    final records = await _storage.readRecords(
      store: MemoryStoreKind.mcpConnections,
      includeExpired: true,
    );
    final urls = <String>[];
    for (final record in records) {
      final parsed = _parseRecord(record);
      if (parsed != null) {
        urls.add(parsed);
      }
    }
    return urls;
  }

  String? _parseRecord(MemoryRecord record) {
    if (record.content.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(record.content);
      if (decoded is Map) {
        final url = decoded['url'];
        if (url is String && url.trim().isNotEmpty) {
          return url;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _keyFor(String url) => 'mcp_connection:$url';
}
