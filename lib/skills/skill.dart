import 'package:openreef/skills/skill_manifest.dart';

enum SkillSourceType { builtin, user }

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.directoryPath,
    required this.skillMarkdownPath,
    required this.rawContent,
    required this.bodyContent,
    required this.manifest,
    this.sourceType = SkillSourceType.user,
  });

  final String id;
  final String name;
  final String directoryPath;
  final String skillMarkdownPath;
  final String rawContent;
  final String bodyContent;
  final SkillManifest manifest;
  final SkillSourceType sourceType;
}
