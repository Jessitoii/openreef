import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_package_models.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';
import 'package:openreef/ui/screens/skills_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user skill opens in guided mode and saves SKILL.md', (
    tester,
  ) async {
    final controller = _FakeSkillRegistryController(
      packages: <SkillPackageDetail>[
        _detail(
          id: 'sleep_tracker',
          displayName: 'sleep_tracker',
          isWritable: true,
          markdown:
              '---\nname: Sleep Tracker\ndescription: Track rest\n---\n# Sleep Tracker\n',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SkillsScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.text('sleep_tracker'));
    await tester.pump();

    expect(find.text('Skill Name'), findsOneWidget);
    expect(find.text('Agent Instructions (Prompt)'), findsOneWidget);
    expect(find.text('Raw markdown...'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'Sleep Coach');
    await tester.enterText(find.byType(TextField).at(1), 'Gentle sleep help');
    await tester.enterText(
      find.byType(TextField).at(2),
      'Help the user review sleep patterns.',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(controller.savedSkillId, 'sleep_tracker');
    expect(controller.savedRelativePath, 'SKILL.md');
    expect(controller.savedContent, contains('name: Sleep Coach'));
    expect(controller.savedContent, contains('Gentle sleep help'));
    expect(
      controller.savedContent,
      contains('Help the user review sleep patterns.'),
    );
    expect(find.text('Skills'), findsOneWidget);
  });

  testWidgets('advanced raw SKILL.md editor requires explicit toggle', (
    tester,
  ) async {
    final controller = _FakeSkillRegistryController(
      packages: <SkillPackageDetail>[
        _detail(
          id: 'sleep_tracker',
          displayName: 'sleep_tracker',
          isWritable: true,
          markdown:
              '---\nname: Sleep Tracker\ndescription: Track rest\n---\n# Sleep Tracker\n',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SkillsScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.text('sleep_tracker'));
    await tester.pump();

    expect(find.text('Raw markdown...'), findsNothing);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    expect(find.text('Raw markdown...'), findsOneWidget);
  });

  testWidgets('built-in skills show read-only state and disable mutation', (
    tester,
  ) async {
    final controller = _FakeSkillRegistryController(
      packages: <SkillPackageDetail>[
        _detail(
          id: 'context_auditor',
          displayName: 'context_auditor',
          isWritable: false,
          markdown:
              '---\nname: Context Auditor\ndescription: Audit context\n---\n# Context Auditor\n',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SkillsScreen(controller: controller)),
    );
    await tester.pump();

    final deleteIcon = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byIcon(Icons.delete_outline),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(deleteIcon.onPressed, isNull);

    await tester.tap(find.text('context_auditor'));
    await tester.pump();

    expect(
      find.text(
        'Built-in skills are read-only. You can review this skill, but Save and Delete are disabled.',
      ),
      findsOneWidget,
    );
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('new skill creates a user package and opens guided editor', (
    tester,
  ) async {
    final controller = _FakeSkillRegistryController();

    await tester.pumpWidget(
      MaterialApp(home: SkillsScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.text('New Skill'));
    await tester.pump();

    expect(controller.createdIds.single, startsWith('new_skill_'));
    expect(find.text('Skill Name'), findsOneWidget);
    expect(find.text('Agent Instructions (Prompt)'), findsOneWidget);
  });
}

SkillPackageDetail _detail({
  required String id,
  required String displayName,
  required bool isWritable,
  required String markdown,
}) {
  final ref = SkillPackageRef(
    id: id,
    displayName: displayName,
    sourceType: isWritable ? SkillSourceType.user : SkillSourceType.builtin,
    rootPath: '/skills/$id',
    isWritable: isWritable,
    isEnabled: true,
    validationSummary: SkillValidationSummary.empty(),
    lastModified: null,
  );
  return SkillPackageDetail(
    ref: ref,
    fileTree: const <SkillFileNode>[],
    rawSkillMarkdown: markdown,
    parsedSkill: null,
    validationSummary: SkillValidationSummary.empty(),
    permissionsAndToolsSummary: '',
    lastModified: null,
    isMalformed: false,
  );
}

class _FakeSkillRegistryController implements SkillRegistryController {
  _FakeSkillRegistryController({
    List<SkillPackageDetail> packages = const <SkillPackageDetail>[],
  }) : _details = <String, SkillPackageDetail>{
         for (final detail in packages) detail.ref.id: detail,
       } {
    _syncPackages();
  }

  final Map<String, SkillPackageDetail> _details;
  final ValueNotifier<List<SkillRuntimeSnapshot>> _skills =
      ValueNotifier<List<SkillRuntimeSnapshot>>(const <SkillRuntimeSnapshot>[]);
  final ValueNotifier<List<SkillPackageRef>> _packages =
      ValueNotifier<List<SkillPackageRef>>(const <SkillPackageRef>[]);
  final ValueNotifier<SkillPackageDetail?> _selectedPackage =
      ValueNotifier<SkillPackageDetail?>(null);

  String? savedSkillId;
  String? savedRelativePath;
  String? savedContent;
  final List<String> createdIds = <String>[];
  final List<String> deletedIds = <String>[];

  @override
  ValueListenable<List<SkillRuntimeSnapshot>> get skills => _skills;

  @override
  ValueListenable<List<SkillPackageRef>> get packages => _packages;

  @override
  ValueListenable<SkillPackageDetail?> get selectedPackage => _selectedPackage;

  @override
  Future<void> reload() async {
    _syncPackages();
  }

  @override
  Future<void> setSkillEnabled(String skillId, bool enabled) async {
    final detail = _details[skillId];
    if (detail == null) {
      return;
    }
    _details[skillId] = _copyDetail(
      detail,
      ref: _copyRef(detail.ref, isEnabled: enabled),
    );
    _syncPackages();
  }

  @override
  Future<void> selectPackage(String skillId) async {
    _selectedPackage.value = _details[skillId];
  }

  @override
  Future<SkillPackageDetail?> createPackage({
    required String id,
    required String markdown,
    Map<String, String>? supportFiles,
  }) async {
    createdIds.add(id);
    final detail = _detail(
      id: id,
      displayName: 'New Skill',
      isWritable: true,
      markdown: markdown,
    );
    _details[id] = detail;
    _selectedPackage.value = detail;
    _syncPackages();
    return detail;
  }

  @override
  Future<SkillPackageDetail?> saveFile({
    required String skillId,
    required String relativePath,
    required String content,
  }) async {
    savedSkillId = skillId;
    savedRelativePath = relativePath;
    savedContent = content;
    final current = _details[skillId];
    if (current == null) {
      return null;
    }
    final detail = _copyDetail(current, rawSkillMarkdown: content);
    _details[skillId] = detail;
    _selectedPackage.value = detail;
    _syncPackages();
    return detail;
  }

  @override
  Future<String?> loadFileContent({
    required String skillId,
    required String relativePath,
  }) async {
    return _details[skillId]?.rawSkillMarkdown;
  }

  @override
  Future<SkillPackageDetail?> deletePackage(String skillId) async {
    deletedIds.add(skillId);
    final removed = _details.remove(skillId);
    _syncPackages();
    return removed;
  }

  void _syncPackages() {
    _packages.value = List<SkillPackageRef>.unmodifiable(
      _details.values.map((detail) => detail.ref),
    );
  }
}

SkillPackageRef _copyRef(SkillPackageRef ref, {bool? isEnabled}) {
  return SkillPackageRef(
    id: ref.id,
    displayName: ref.displayName,
    sourceType: ref.sourceType,
    rootPath: ref.rootPath,
    isWritable: ref.isWritable,
    isEnabled: isEnabled ?? ref.isEnabled,
    validationSummary: ref.validationSummary,
    lastModified: ref.lastModified,
  );
}

SkillPackageDetail _copyDetail(
  SkillPackageDetail detail, {
  SkillPackageRef? ref,
  String? rawSkillMarkdown,
}) {
  return SkillPackageDetail(
    ref: ref ?? detail.ref,
    fileTree: detail.fileTree,
    rawSkillMarkdown: rawSkillMarkdown ?? detail.rawSkillMarkdown,
    parsedSkill: detail.parsedSkill,
    validationSummary: detail.validationSummary,
    permissionsAndToolsSummary: detail.permissionsAndToolsSummary,
    lastModified: detail.lastModified,
    isMalformed: detail.isMalformed,
  );
}
