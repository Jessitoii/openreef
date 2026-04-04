import 'package:flutter/foundation.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_registry.dart';

class SkillRegistryController {
  SkillRegistryController({
    required SkillRegistry registry,
  }) : _registry = registry;

  final SkillRegistry _registry;
  final ValueNotifier<List<Skill>> _skills =
      ValueNotifier<List<Skill>>(const <Skill>[]);

  ValueListenable<List<Skill>> get skills => _skills;

  Future<void> reload() async {
    final discovered = await _registry.discoverSkills();
    _skills.value = discovered;
  }

  List<SkillDefinition> toSkillDefinitions() {
    return _skills.value
        .map(
          (skill) => SkillDefinition(
            id: skill.id,
            content: skill.rawContent,
            triggerPatterns: const <String>[],
          ),
        )
        .toList(growable: false);
  }
}
