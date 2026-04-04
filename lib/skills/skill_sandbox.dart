import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_exceptions.dart';

class SkillSandbox {
  const SkillSandbox();

  void assertToolAllowed({
    required Skill skill,
    required String toolId,
  }) {
    if (!skill.manifest.toolsRequired.contains(toolId)) {
      throw SandboxViolationException(skillId: skill.id, toolId: toolId);
    }
  }

  Future<T> runTool<T>({
    required Skill skill,
    required String toolId,
    required Future<T> Function() execute,
  }) {
    assertToolAllowed(skill: skill, toolId: toolId);
    return execute();
  }
}
