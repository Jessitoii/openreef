class ChatSessionRecord {
  const ChatSessionRecord({
    required this.id,
    required this.title,
    required this.lastModified,
  });

  final String id;
  final String title;
  final DateTime lastModified;

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'last_modified': lastModified.toUtc().toIso8601String(),
    };
  }

  factory ChatSessionRecord.fromDatabaseMap(Map<String, Object?> map) {
    return ChatSessionRecord(
      id: map['id']! as String,
      title: map['title']! as String,
      lastModified: DateTime.parse(map['last_modified']! as String).toLocal(),
    );
  }
}
