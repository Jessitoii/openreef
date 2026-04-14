import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_package_repository.dart';
import 'package:openreef/skills/skill_package_service.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/ui/screens/skills_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('skills workspace renders detail file tree and validation', (
    tester,
  ) async {
    final tempRoot = await Directory.systemTemp.createTemp('skills-ui-');
    final localRoot = Directory('${tempRoot.path}${Platform.pathSeparator}skills');
    await localRoot.create(recursive: true);
    final builtinRoot =
        Directory('${tempRoot.path}${Platform.pathSeparator}builtin_skills');
    await builtinRoot.create(recursive: true);
    final packageDir =
        Directory('${localRoot.path}${Platform.pathSeparator}sleep_tracker');
    await packageDir.create(recursive: true);
    await File('${packageDir.path}${Platform.pathSeparator}SKILL.md').writeAsString(
      '---\nname: Sleep Tracker\ntools_required: []\n---\n# Sleep Tracker\n',
    );
    await File('${packageDir.path}${Platform.pathSeparator}notes.txt')
        .writeAsString('support note');

    final registry = SkillRegistry(
      rootPaths: const <String>[],
      roots: <SkillRegistryRoot>[
        SkillRegistryRoot(path: builtinRoot.path, sourceType: SkillSourceType.builtin),
        SkillRegistryRoot(path: localRoot.path, sourceType: SkillSourceType.user),
      ],
    );
    final catalog = SkillRuntimeCatalog(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      stateFile: File(
        '${tempRoot.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await catalog.reload();
    final service = SkillPackageService(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      repository: SkillPackageRepository(
        localRootDirectory: localRoot,
        builtinRootDirectory: builtinRoot,
      ),
      isEnabled: (skillId) => catalog.enabledById[skillId] ?? true,
    );
    final controller = SkillRegistryController(
      catalog: catalog,
      packageService: service,
    );
    await controller.reload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SkillsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('sleep_tracker'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);

    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();

    expect(find.text('support note'), findsOneWidget);
  });

  testWidgets('mobile portrait opens detail as full-width flow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempRoot = await Directory.systemTemp.createTemp('skills-ui-mobile-');
    final localRoot = Directory('${tempRoot.path}${Platform.pathSeparator}skills');
    await localRoot.create(recursive: true);
    final builtinRoot =
        Directory('${tempRoot.path}${Platform.pathSeparator}builtin_skills');
    await builtinRoot.create(recursive: true);
    final packageDir =
        Directory('${localRoot.path}${Platform.pathSeparator}sleep_tracker');
    await packageDir.create(recursive: true);
    await File('${packageDir.path}${Platform.pathSeparator}SKILL.md').writeAsString(
      '---\nname: Sleep Tracker\ntools_required: []\n---\n# Sleep Tracker\n',
    );

    final registry = SkillRegistry(
      rootPaths: const <String>[],
      roots: <SkillRegistryRoot>[
        SkillRegistryRoot(path: builtinRoot.path, sourceType: SkillSourceType.builtin),
        SkillRegistryRoot(path: localRoot.path, sourceType: SkillSourceType.user),
      ],
    );
    final catalog = SkillRuntimeCatalog(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      stateFile: File(
        '${tempRoot.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await catalog.reload();
    final service = SkillPackageService(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      repository: SkillPackageRepository(
        localRootDirectory: localRoot,
        builtinRootDirectory: builtinRoot,
      ),
      isEnabled: (skillId) => catalog.enabledById[skillId] ?? true,
    );
    final controller = SkillRegistryController(
      catalog: catalog,
      packageService: service,
    );
    await controller.reload();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SkillsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('sleep_tracker'), findsOneWidget);

    await tester.tap(find.text('sleep_tracker'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Back to skills'), findsOneWidget);
    expect(find.text('Validation'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
  });

  testWidgets('built-in detail actions are disabled on narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempRoot = await Directory.systemTemp.createTemp('skills-ui-builtin-');
    final localRoot = Directory('${tempRoot.path}${Platform.pathSeparator}skills');
    await localRoot.create(recursive: true);
    final builtinRoot =
        Directory('${tempRoot.path}${Platform.pathSeparator}builtin_skills');
    await builtinRoot.create(recursive: true);
    final builtinDir = Directory(
      '${builtinRoot.path}${Platform.pathSeparator}context_auditor',
    );
    await builtinDir.create(recursive: true);
    await File('${builtinDir.path}${Platform.pathSeparator}SKILL.md').writeAsString(
      '---\nname: Context Auditor\ntools_required: []\n---\n# Context Auditor\n',
    );

    final registry = SkillRegistry(
      rootPaths: const <String>[],
      roots: <SkillRegistryRoot>[
        SkillRegistryRoot(path: builtinRoot.path, sourceType: SkillSourceType.builtin),
        SkillRegistryRoot(path: localRoot.path, sourceType: SkillSourceType.user),
      ],
    );
    final catalog = SkillRuntimeCatalog(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      stateFile: File(
        '${tempRoot.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await catalog.reload();
    final service = SkillPackageService(
      registry: registry,
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      repository: SkillPackageRepository(
        localRootDirectory: localRoot,
        builtinRootDirectory: builtinRoot,
      ),
      isEnabled: (skillId) => catalog.enabledById[skillId] ?? true,
    );
    final controller = SkillRegistryController(
      catalog: catalog,
      packageService: service,
    );
    await controller.reload();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SkillsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('context_auditor'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final saveButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Save'),
    );
    final deleteButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete'),
    );

    expect(saveButton.onPressed, isNull);
    expect(deleteButton.onPressed, isNull);
  });
}
