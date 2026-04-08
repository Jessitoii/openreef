import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/skills/skill.dart';

class SkillRuntimeSnapshot {
  const SkillRuntimeSnapshot({
    required this.skill,
    required this.installed,
    required this.enabled,
    required this.runtimeEligible,
    required this.matchedThisTurn,
    required this.activeThisTurn,
    this.missingRequiredTools = const <String>[],
  });

  final Skill skill;
  final bool installed;
  final bool enabled;
  final bool runtimeEligible;
  final bool matchedThisTurn;
  final bool activeThisTurn;
  final List<String> missingRequiredTools;

  SkillRuntimeSnapshot copyWith({
    Skill? skill,
    bool? installed,
    bool? enabled,
    bool? runtimeEligible,
    bool? matchedThisTurn,
    bool? activeThisTurn,
    List<String>? missingRequiredTools,
  }) {
    return SkillRuntimeSnapshot(
      skill: skill ?? this.skill,
      installed: installed ?? this.installed,
      enabled: enabled ?? this.enabled,
      runtimeEligible: runtimeEligible ?? this.runtimeEligible,
      matchedThisTurn: matchedThisTurn ?? this.matchedThisTurn,
      activeThisTurn: activeThisTurn ?? this.activeThisTurn,
      missingRequiredTools: missingRequiredTools ?? this.missingRequiredTools,
    );
  }

  SkillDefinition toSkillDefinition() {
    return SkillDefinition(
      id: skill.id,
      displayName: skill.name,
      content: skill.bodyContent.trim(),
      toolsRequired: skill.manifest.toolsRequired,
      triggerPatterns: skill.manifest.triggerPatterns,
      runtimeEligible: runtimeEligible,
    );
  }
}
