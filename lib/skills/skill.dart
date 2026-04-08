import 'package:openreef/skills/skill_manifest.dart';

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.directoryPath,
    required this.skillMarkdownPath,
    required this.rawContent,
    required this.bodyContent,
    required this.manifest,
  });

  final String id;
  final String name;
  final String directoryPath;
  final String skillMarkdownPath;
  final String rawContent;
  final String bodyContent;
  final SkillManifest manifest;
}
