import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/skills/skill_registry.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('skill_registry_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('discovers only directories containing SKILL.md', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'sleep_tracker',
      markdown: _skillMarkdown(<String>['alarm_set']),
    );
    await Directory('${tempRoot.path}${Platform.pathSeparator}notes').create();
    await File('${tempRoot.path}${Platform.pathSeparator}README.md')
        .writeAsString('not a skill');

    final registry = SkillRegistry(rootPaths: <String>[tempRoot.path]);
    final skills = await registry.discoverSkills();

    expect(skills, hasLength(1));
    expect(skills.single.id, 'sleep_tracker');
    expect(skills.single.name, 'sleep_tracker');
  });

  test('ignores unrelated files and directories without manifests', () async {
    await Directory('${tempRoot.path}${Platform.pathSeparator}empty_dir')
        .create();
    await File('${tempRoot.path}${Platform.pathSeparator}orphan.txt')
        .writeAsString('orphan');

    final registry = SkillRegistry(rootPaths: <String>[tempRoot.path]);
    final skills = await registry.discoverSkills();

    expect(skills, isEmpty);
  });

  test('returns stable ids names and parsed manifests from folder names', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'calendar_helper',
      markdown: _skillMarkdown(<String>['calendar_read', 'notify']),
    );

    final registry = SkillRegistry(rootPaths: <String>[tempRoot.path]);
    final skills = await registry.discoverSkills();

    expect(skills, hasLength(1));
    expect(skills.single.id, 'calendar_helper');
    expect(skills.single.name, 'calendar_helper');
    expect(
      skills.single.manifest.toolsRequired,
      <String>['calendar_read', 'notify'],
    );
  });
}

Future<void> _createSkillDirectory({
  required Directory root,
  required String name,
  required String markdown,
}) async {
  final directory = await Directory(
    '${root.path}${Platform.pathSeparator}$name',
  ).create();
  final skillFile = File('${directory.path}${Platform.pathSeparator}SKILL.md');
  await skillFile.writeAsString(markdown);
}

String _skillMarkdown(List<String> toolsRequired) {
  final tools = toolsRequired.map((tool) => '  - $tool').join('\n');
  return '''---
tools_required:
$tools
---
# Test Skill
''';
}
