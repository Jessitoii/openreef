enum MemoryStoreKind {
  shortTerm,
  longTerm,
  episodic,
  skillState;

  String get value {
    switch (this) {
      case MemoryStoreKind.shortTerm:
        return 'short_term';
      case MemoryStoreKind.longTerm:
        return 'long_term';
      case MemoryStoreKind.episodic:
        return 'episodic';
      case MemoryStoreKind.skillState:
        return 'skill_state';
    }
  }

  static MemoryStoreKind fromValue(String value) {
    return MemoryStoreKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => MemoryStoreKind.shortTerm,
    );
  }
}
