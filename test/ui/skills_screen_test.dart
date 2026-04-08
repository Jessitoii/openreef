import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_manifest.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';
import 'package:openreef/ui/screens/skills_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('skills screen renders runtime truth and toggles enablement', (
    tester,
  ) async {
    final controller = _FakeSkillRegistryController(
      snapshots: <SkillRuntimeSnapshot>[
        SkillRuntimeSnapshot(
          skill: Skill(
            id: 'sleep_tracker',
            name: 'Sleep Tracker',
            directoryPath: 'D:/tmp/skills/sleep_tracker',
            skillMarkdownPath: 'D:/tmp/skills/sleep_tracker/SKILL.md',
            rawContent: 'raw',
            bodyContent: '# Sleep Tracker\nAlways prompt with a bedtime checklist.',
            manifest: const SkillManifest(
              description: 'Tracks bedtime routines.',
              toolsRequired: <String>['notify'],
              triggerPatterns: <String>['bedtime check'],
            ),
          ),
          installed: true,
          enabled: true,
          runtimeEligible: true,
          matchedThisTurn: true,
          activeThisTurn: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SkillsScreen(controller: controller),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('runtime-eligible'), findsOneWidget);
    expect(find.text('matched this turn'), findsOneWidget);
    expect(find.text('active this turn'), findsOneWidget);
    expect(find.text('bedtime check'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('disabled'), findsOneWidget);
    expect(find.text('runtime-blocked'), findsOneWidget);
    expect(controller.skills.value.single.enabled, isFalse);
  });
}

class _FakeSkillRegistryController extends SkillRegistryController {
  _FakeSkillRegistryController({required List<SkillRuntimeSnapshot> snapshots})
      : _skills = ValueNotifier<List<SkillRuntimeSnapshot>>(
          List<SkillRuntimeSnapshot>.unmodifiable(snapshots),
        ),
        super(
          catalog: SkillRuntimeCatalog(
            registry: SkillRegistry(rootPaths: <String>[]),
            toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
            stateFile: File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}skills_screen_test_runtime_state.json',
            ),
          ),
        );

  final ValueNotifier<List<SkillRuntimeSnapshot>> _skills;

  @override
  ValueListenable<List<SkillRuntimeSnapshot>> get skills => _skills;

  @override
  Future<void> reload() async {}

  @override
  Future<void> setSkillEnabled(String skillId, bool enabled) async {
    _skills.value = _skills.value
        .map((snapshot) {
          if (snapshot.skill.id != skillId) {
            return snapshot;
          }
          return snapshot.copyWith(
            enabled: enabled,
            runtimeEligible: enabled && snapshot.missingRequiredTools.isEmpty,
            activeThisTurn: enabled ? snapshot.activeThisTurn : false,
          );
        })
        .toList(growable: false);
  }
}
