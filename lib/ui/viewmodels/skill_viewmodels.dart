import 'package:openreef/skills/skill_package_models.dart';

class SkillViewModel {
  const SkillViewModel({
    required this.id,
    required this.name,
    required this.summary,
    required this.version,
    required this.category,
    required this.isBuiltIn,
    required this.isLoaded,
    required this.isActive,
    required this.rawDetails,
  });

  final String id;
  final String name;
  final String summary;
  final String version;
  final String category;
  final bool isBuiltIn;
  final bool isLoaded;
  final bool isActive;
  final String rawDetails;

  factory SkillViewModel.fromDomain(SkillPackageDetail package) {
    String rawInstructions = package.rawSkillMarkdown ?? '';
    String name = package.ref.displayName;
    String summary = package.validationSummary.isValid
        ? 'Standard skill'
        : 'Needs attention';

    // Naive front-matter extraction for guided UI mode
    if (rawInstructions.startsWith('---')) {
      final parts = rawInstructions.split('---');
      if (parts.length >= 3) {
        final frontMatter = parts[1];
        if (frontMatter.contains('name:')) {
          name = frontMatter.split('name:')[1].split('\n')[0].trim();
        }
        if (frontMatter.contains('description:')) {
          summary = frontMatter.split('description:')[1].split('\n')[0].trim();
        }
      }
    }

    final parsed = package.parsedSkill;
    return SkillViewModel(
      id: package.ref.id,
      name: name,
      summary: summary,
      version: '1.0.0',
      category: parsed != null && parsed.triggerPatterns.isNotEmpty
          ? parsed.triggerPatterns.first
          : 'General',
      isBuiltIn: !package.ref.isWritable,
      isLoaded: true,
      isActive: package.ref.isEnabled,
      rawDetails: rawInstructions,
    );
  }

  factory SkillViewModel.fromRef(SkillPackageRef ref) {
    return SkillViewModel(
      id: ref.id,
      name: ref.displayName,
      summary: 'Standard skill',
      version: '1.0.0',
      category: 'General',
      isBuiltIn: !ref.isWritable,
      isLoaded: true,
      isActive: ref.isEnabled,
      rawDetails: '',
    );
  }
}
