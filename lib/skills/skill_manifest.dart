class SkillManifest {
  const SkillManifest({
    required this.toolsRequired,
    this.name,
    this.description = '',
    this.triggerPatterns = const <String>[],
  });

  final List<String> toolsRequired;
  final String? name;
  final String description;
  final List<String> triggerPatterns;
}
