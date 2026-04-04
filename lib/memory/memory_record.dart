import 'dart:convert';

import 'package:openreef/memory/memory_store_kind.dart';

class MemoryRecord {
  const MemoryRecord({
    this.id,
    required this.store,
    required this.key,
    required this.content,
    required this.category,
    required this.importance,
    required this.createdAt,
    this.expiresAt,
    this.metadata = const <String, Object?>{},
  });

  factory MemoryRecord.fromDatabaseMap(Map<String, Object?> map) {
    final metadataJson = map['metadata'] as String?;
    return MemoryRecord(
      id: map['id'] as int?,
      store: MemoryStoreKind.fromValue(map['store_kind'] as String? ?? ''),
      key: map['memory_key'] as String? ?? '',
      content: map['content'] as String? ?? '',
      category: map['category'] as String? ?? '',
      importance: (map['importance'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: _parseDateTime(map['expires_at'] as String?),
      metadata: metadataJson == null || metadataJson.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(metadataJson) as Map<String, Object?>,
            ),
    );
  }

  final int? id;
  final MemoryStoreKind store;
  final String key;
  final String content;
  final String category;
  final int importance;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final Map<String, Object?> metadata;

  bool get isExpired {
    return expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id,
      'store_kind': store.value,
      'memory_key': key,
      'content': content,
      'category': category,
      'importance': importance,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'metadata': jsonEncode(metadata),
    };
  }

  MemoryRecord copyWith({
    int? id,
    MemoryStoreKind? store,
    String? key,
    String? content,
    String? category,
    int? importance,
    DateTime? createdAt,
    DateTime? expiresAt,
    Map<String, Object?>? metadata,
  }) {
    return MemoryRecord(
      id: id ?? this.id,
      store: store ?? this.store,
      key: key ?? this.key,
      content: content ?? this.content,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      metadata: metadata ?? this.metadata,
    );
  }

  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.parse(value);
  }
}
