import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_package_repository.dart';
import 'package:openreef/skills/skill_package_service.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';

void main() {
  late Directory tempRoot;
  late Directory localRoot;
  late Directory builtinRoot;
  late SkillRegistry registry;
  late SkillRuntimeCatalog catalog;
  late SkillPackageService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('skill_package_service_');
    localRoot = Directory('${tempRoot.path}${Platform.pathSeparator}skills');
    builtinRoot =
        Directory('${tempRoot.path}${Platform.pathSeparator}builtin_skills');
    await localRoot.create(recursive: true);
    await builtinRoot.create(recursive: true);

    registry = SkillRegistry(
      rootPaths: const <String>[],
      roots: <SkillRegistryRoot>[
        SkillRegistryRoot(
          path: builtinRoot.path,
          sourceType: SkillSourceType.builtin,
        ),
        SkillRegistryRoot(
          path: localRoot.path,
          sourceType: SkillSourceType.user,
        ),
      ],
    );
    catalog = SkillRuntimeCatalog(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[
        ToolDefinition(
          id: 'notify',
          embedding: <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _noopExecute,
        ),
      ]),
      stateFile: File(
        '${tempRoot.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await catalog.reload();
    service = SkillPackageService(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[
        ToolDefinition(
          id: 'notify',
          embedding: <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _noopExecute,
        ),
      ]),
      repository: SkillPackageRepository(
        localRootDirectory: localRoot,
        builtinRootDirectory: builtinRoot,
      ),
      isEnabled: (skillId) => catalog.enabledById[skillId] ?? true,
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('create save and delete mutate the real filesystem', () async {
    final detail = await service.createLocalPackage(
      id: 'sleep_tracker',
      markdown: '''---
name: Sleep Tracker
tools_required: [notify]
---
# Sleep Tracker
''',
      supportFiles: <String, String>{'notes.txt': 'support note'},
    );

    expect(
      await File(
        '${localRoot.path}${Platform.pathSeparator}sleep_tracker${Platform.pathSeparator}SKILL.md',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${localRoot.path}${Platform.pathSeparator}sleep_tracker${Platform.pathSeparator}notes.txt',
      ).exists(),
      isTrue,
    );
    expect(detail.ref.isWritable, isTrue);

    await service.saveFile(
      skillId: 'sleep_tracker',
      relativePath: 'SKILL.md',
      content: '''---
name: Sleep Tracker
tools_required: [notify]
---
# Updated
''',
    );
    expect(
      await File(
        '${localRoot.path}${Platform.pathSeparator}sleep_tracker${Platform.pathSeparator}SKILL.md',
      ).readAsString(),
      contains('# Updated'),
    );

    await service.saveFile(
      skillId: 'sleep_tracker',
      relativePath: 'notes.txt',
      content: 'updated support',
    );
    expect(
      await File(
        '${localRoot.path}${Platform.pathSeparator}sleep_tracker${Platform.pathSeparator}notes.txt',
      ).readAsString(),
      'updated support',
    );

    await service.deletePackage('sleep_tracker');
    expect(
      await Directory(
        '${localRoot.path}${Platform.pathSeparator}sleep_tracker',
      ).exists(),
      isFalse,
    );
  });

  test('built-in packages reject save and delete through service path', () async {
    await _createSkillDirectory(
      root: builtinRoot,
      name: 'context_auditor',
      markdown: '''---
name: Context Auditor
tools_required: [notify]
---
# Context Auditor
''',
    );

    await expectLater(
      () => service.saveFile(
        skillId: 'context_auditor',
        relativePath: 'SKILL.md',
        content: '---\nname: Bad\ntools_required: []\n---\n',
      ),
      throwsStateError,
    );

    await expectLater(
      () => service.deletePackage('context_auditor'),
      throwsStateError,
    );
  });

  test('missing SKILL.md is surfaced as invalid from actual disk state', () async {
    await Directory('${localRoot.path}${Platform.pathSeparator}broken_skill')
        .create();

    final detail = await service.hydrateById('broken_skill');

    expect(detail, isNotNull);
    final packages = await service.listPackages();
    expect(packages.map((packageRef) => packageRef.id), contains('broken_skill'));
    expect(detail!.rawSkillMarkdown, isNull);
    expect(detail.isMalformed, isTrue);
    expect(
      detail.validationSummary.issues.map((issue) => issue.message),
      contains('missing_skill_md'),
    );
  });

  test('malformed SKILL.md is surfaced from the real parser failure', () async {
    await _createSkillDirectory(
      root: localRoot,
      name: 'bad_skill',
      markdown: '''---
name: Bad Skill
tools_required: [notify
---
# Bad Skill
''',
    );

    final detail = await service.hydrateById('bad_skill');

    expect(detail, isNotNull);
    expect(detail!.rawSkillMarkdown, contains('tools_required'));
    expect(detail.isMalformed, isTrue);
    expect(
      detail.validationSummary.issues.map((issue) => issue.message),
      contains('invalid_frontmatter_yaml'),
    );
  });

  test('unknown tools are reported in validation', () async {
    await _createSkillDirectory(
      root: localRoot,
      name: 'tool_mismatch',
      markdown: '''---
name: Tool Mismatch
tools_required: [missing_tool]
---
# Tool Mismatch
''',
    );

    final detail = await service.hydrateById('tool_mismatch');

    expect(detail, isNotNull);
    expect(
      detail!.validationSummary.issues.map((issue) => issue.message),
      contains('missing_tools:missing_tool'),
    );
  });

  test('enable state survives reload through the catalog state file', () async {
    await _createSkillDirectory(
      root: localRoot,
      name: 'sleep_tracker',
      markdown: '''---
name: Sleep Tracker
tools_required: [notify]
---
# Sleep Tracker
''',
    );

    await catalog.reload();
    await catalog.setSkillEnabled('sleep_tracker', false);

    final reloadedCatalog = SkillRuntimeCatalog(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[
        ToolDefinition(
          id: 'notify',
          embedding: <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _noopExecute,
        ),
      ]),
      stateFile: File(
        '${tempRoot.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await reloadedCatalog.reload();

    expect(reloadedCatalog.snapshots.single.enabled, isFalse);
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

Future<ToolResult> _noopExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
