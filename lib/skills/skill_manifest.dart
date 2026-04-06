class SkillManifest {
  const SkillManifest({
    required this.toolsRequired,
    this.description = '',
  });

  final List<String> toolsRequired;
  final String description;
}
