import 'dart:io';

import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_frontmatter_parser.dart';

class SkillRegistry {
  SkillRegistry({
    required List<String> rootPaths,
    SkillFrontmatterParser parser = const SkillFrontmatterParser(),
  }) : _rootPaths = List<String>.unmodifiable(rootPaths),
       _parser = parser;

  final List<String> _rootPaths;
  final SkillFrontmatterParser _parser;

  Future<List<Skill>> discoverSkills() async {
    final discovered = <Skill>[];

    for (final rootPath in _rootPaths) {
      final rootDirectory = Directory(rootPath);
      if (!await rootDirectory.exists()) {
        continue;
      }

      await for (final entry in rootDirectory.list(followLinks: false)) {
        if (entry is! Directory) {
          continue;
        }

        final skillMarkdownPath =
            '${entry.path}${Platform.pathSeparator}SKILL.md';
        final skillFile = File(skillMarkdownPath);
        if (!await skillFile.exists()) {
          continue;
        }

        final rawContent = await skillFile.readAsString();
        final parsed = _parser.parse(rawContent);
        final name = _basename(entry.path);

        discovered.add(
          Skill(
            id: name,
            name: parsed.manifest.name ?? name,
            directoryPath: entry.path,
            skillMarkdownPath: skillMarkdownPath,
            rawContent: rawContent,
            bodyContent: parsed.body,
            manifest: parsed.manifest,
          ),
        );
      }
    }

    return List<Skill>.unmodifiable(discovered);
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final separatorIndex = trimmed.lastIndexOf('/');
    if (separatorIndex == -1) {
      if (trimmed.isEmpty) {
        throw const SkillDiscoveryException('invalid_skill_directory');
      }
      return trimmed;
    }

    final basename = trimmed.substring(separatorIndex + 1);
    if (basename.isEmpty) {
      throw const SkillDiscoveryException('invalid_skill_directory');
    }
    return basename;
  }
}
