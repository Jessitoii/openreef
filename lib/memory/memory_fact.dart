class MemoryFact {
  const MemoryFact({
    required this.key,
    required this.fact,
    required this.category,
    required this.importance,
    this.metadata = const <String, Object?>{},
  });

  final String key;
  final String fact;
  final String category;
  final int importance;
  final Map<String, Object?> metadata;

  MemoryFact copyWith({
    String? key,
    String? fact,
    String? category,
    int? importance,
    Map<String, Object?>? metadata,
  }) {
    return MemoryFact(
      key: key ?? this.key,
      fact: fact ?? this.fact,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      metadata: metadata ?? this.metadata,
    );
  }
}
