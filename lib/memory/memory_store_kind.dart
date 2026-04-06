enum MemoryStoreKind {
  shortTerm,
  longTerm,
  episodic,
  skillState,
  mcpConnections;

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
      case MemoryStoreKind.mcpConnections:
        return 'mcp_connections';
    }
  }

  static MemoryStoreKind fromValue(String value) {
    return MemoryStoreKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => MemoryStoreKind.shortTerm,
    );
  }
}
