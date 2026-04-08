import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_manifest.dart';
import 'package:openreef/skills/skill_sandbox.dart';

void main() {
  const sandbox = SkillSandbox();
  const skill = Skill(
    id: 'calendar_helper',
    name: 'calendar_helper',
    directoryPath: '/skills/calendar_helper',
    skillMarkdownPath: '/skills/calendar_helper/SKILL.md',
    rawContent: '---\ntools_required: [calendar_read]\n---\n# Calendar Helper\n',
    bodyContent: '# Calendar Helper\n',
    manifest: SkillManifest(toolsRequired: <String>['calendar_read']),
  );

  test('allows execution for declared tools', () async {
    var executed = false;

    final result = await sandbox.runTool<String>(
      skill: skill,
      toolId: 'calendar_read',
      execute: () async {
        executed = true;
        return 'ok';
      },
    );

    expect(result, 'ok');
    expect(executed, isTrue);
  });

  test('throws sandbox violation for undeclared tools', () {
    expect(
      () => sandbox.assertToolAllowed(skill: skill, toolId: 'memory_save'),
      throwsA(
        isA<SandboxViolationException>()
            .having((error) => error.skillId, 'skillId', 'calendar_helper')
            .having((error) => error.toolId, 'toolId', 'memory_save'),
      ),
    );
  });

  test('does not invoke wrapped executor when sandbox blocks the tool', () async {
    var executed = false;

    await expectLater(
      () => sandbox.runTool<void>(
        skill: skill,
        toolId: 'memory_save',
        execute: () async {
          executed = true;
        },
      ),
      throwsA(isA<SandboxViolationException>()),
    );

    expect(executed, isFalse);
  });
}
