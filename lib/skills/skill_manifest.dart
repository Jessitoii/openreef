class SkillManifest {
  const SkillManifest({
    required this.toolsRequired,
    this.name,
    this.description = '',
    this.triggerPatterns = const <String>[],
    this.priority = 0,
    this.maxTokens = 150,
    this.activationTerms = const <String>[],
    this.allowedModes = const <String>[],
    this.incompatibleSkillIds = const <String>[],
  });

  final List<String> toolsRequired;
  final String? name;
  final String description;
  final List<String> triggerPatterns;
  final int priority;
  final int maxTokens;
  final List<String> activationTerms;
  final List<String> allowedModes;
  final List<String> incompatibleSkillIds;
}
