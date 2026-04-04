class SkillParseException implements Exception {
  const SkillParseException(this.message);

  final String message;

  @override
  String toString() => 'SkillParseException: $message';
}

class SkillDiscoveryException implements Exception {
  const SkillDiscoveryException(this.message);

  final String message;

  @override
  String toString() => 'SkillDiscoveryException: $message';
}

class SandboxViolationException implements Exception {
  const SandboxViolationException({
    required this.skillId,
    required this.toolId,
  });

  final String skillId;
  final String toolId;

  @override
  String toString() => 'sandbox_violation:$skillId:$toolId';
}
