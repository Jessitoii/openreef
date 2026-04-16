import 'dart:io';

import 'package:flutter/services.dart';

class BuiltInSkillSource {
  const BuiltInSkillSource({
    this.assetPaths = const <String>[
      'assets/skills/context_auditor/SKILL.md',
      'assets/skills/memory_curator/SKILL.md',
      'assets/skills/skill-creator/SKILL.md',
    ],
  });

  static const List<String> defaultAssetPaths = <String>[
    'assets/skills/context_auditor/SKILL.md',
    'assets/skills/memory_curator/SKILL.md',
    'assets/skills/skill-creator/SKILL.md',
  ];

  final List<String> assetPaths;

  Future<Directory> materialize({
    required Directory parentDirectory,
    AssetBundle? bundle,
  }) async {
    final activeBundle = bundle ?? rootBundle;
    final root = Directory(
      '${parentDirectory.path}${Platform.pathSeparator}builtin_skills',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    for (final assetPath in assetPaths) {
      final skillId = _skillIdFor(assetPath);
      final skillDirectory = Directory(
        '${root.path}${Platform.pathSeparator}$skillId',
      );
      if (!await skillDirectory.exists()) {
        await skillDirectory.create(recursive: true);
      }
      final content = await activeBundle.loadString(assetPath);
      await File(
        '${skillDirectory.path}${Platform.pathSeparator}SKILL.md',
      ).writeAsString(content, flush: true);
    }

    return root;
  }

  String _skillIdFor(String assetPath) {
    final normalized = assetPath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.length < 2) {
      throw ArgumentError.value(assetPath, 'assetPath', 'invalid skill asset');
    }
    return parts[parts.length - 2];
  }
}
