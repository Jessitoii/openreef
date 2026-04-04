class MemoryPointer {
  const MemoryPointer({
    required this.category,
    required this.pointer,
    required this.updatedAt,
  });

  factory MemoryPointer.fromDatabaseMap(Map<String, Object?> map) {
    return MemoryPointer(
      category: map['category'] as String? ?? '',
      pointer: map['pointer'] as String? ?? '',
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String category;
  final String pointer;
  final DateTime updatedAt;

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'category': category,
      'pointer': pointer,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
