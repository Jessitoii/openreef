import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';

class SkillRuntimeCatalog extends ChangeNotifier implements SkillCatalog {
  SkillRuntimeCatalog({
    required SkillRegistry registry,
    required ToolCatalog toolCatalog,
    required File stateFile,
  })  : _registry = registry,
        _toolCatalog = toolCatalog,
        _stateFile = stateFile;

  final SkillRegistry _registry;
  final ToolCatalog _toolCatalog;
  final File _stateFile;

  List<SkillRuntimeSnapshot> _snapshots = const <SkillRuntimeSnapshot>[];
  Map<String, bool> _enabledById = const <String, bool>{};

  List<SkillRuntimeSnapshot> get snapshots =>
      List<SkillRuntimeSnapshot>.unmodifiable(_snapshots);

  Map<String, bool> get enabledById =>
      Map<String, bool>.unmodifiable(_enabledById);

  Future<void> reload() async {
    final discovered = await _registry.discoverSkills();
    _enabledById = await _loadEnabledState();

    var shouldPersist = false;
    final nextEnabledById = Map<String, bool>.from(_enabledById);
    for (final skill in discovered) {
      if (nextEnabledById.containsKey(skill.id)) {
        continue;
      }
      nextEnabledById[skill.id] = true;
      shouldPersist = true;
    }

    final validIds = discovered.map((skill) => skill.id).toSet();
    final staleIds = nextEnabledById.keys
        .where((skillId) => !validIds.contains(skillId))
        .toList(growable: false);
    for (final staleId in staleIds) {
      nextEnabledById.remove(staleId);
      shouldPersist = true;
    }

    _enabledById = Map<String, bool>.unmodifiable(nextEnabledById);
    if (shouldPersist) {
      await _persistEnabledState();
    }

    _snapshots = _buildSnapshots(discovered);
    notifyListeners();
  }

  Future<void> setSkillEnabled(String skillId, bool enabled) async {
    if (_enabledById[skillId] == enabled) {
      return;
    }

    final nextEnabled = Map<String, bool>.from(_enabledById);
    nextEnabled[skillId] = enabled;
    _enabledById = Map<String, bool>.unmodifiable(nextEnabled);
    await _persistEnabledState();

    final skills = _snapshots.map((snapshot) => snapshot.skill).toList(growable: false);
    _snapshots = _buildSnapshots(skills);
    notifyListeners();
  }

  @override
  List<SkillDefinition> listSkills() {
    return _snapshots
        .map((snapshot) => snapshot.toSkillDefinition())
        .toList(growable: false);
  }

  @override
  void recordTurnState({
    required List<String> matchedSkillIds,
    required List<String> activeSkillIds,
  }) {
    final matchedSet = matchedSkillIds.toSet();
    final activeSet = activeSkillIds.toSet();
    var hasChanges = false;
    final nextSnapshots = _snapshots
        .map((snapshot) {
          final matched = matchedSet.contains(snapshot.skill.id);
          final active = activeSet.contains(snapshot.skill.id);
          if (snapshot.matchedThisTurn == matched &&
              snapshot.activeThisTurn == active) {
            return snapshot;
          }
          hasChanges = true;
          return snapshot.copyWith(
            matchedThisTurn: matched,
            activeThisTurn: active,
          );
        })
        .toList(growable: false);

    if (!hasChanges) {
      return;
    }
    _snapshots = nextSnapshots;
    notifyListeners();
  }

  List<SkillRuntimeSnapshot> _buildSnapshots(List<Skill> skills) {
    return skills
        .map((skill) {
          final enabled = _enabledById[skill.id] ?? true;
          final missingRequiredTools = skill.manifest.toolsRequired
              .where((toolId) {
                final tool = _toolCatalog.byId(toolId);
                return tool == null || !tool.enabled;
              })
              .toList(growable: false);
          return SkillRuntimeSnapshot(
            skill: skill,
            installed: true,
            enabled: enabled,
            runtimeEligible: enabled && missingRequiredTools.isEmpty,
            matchedThisTurn: false,
            activeThisTurn: false,
            missingRequiredTools: missingRequiredTools,
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, bool>> _loadEnabledState() async {
    if (!await _stateFile.exists()) {
      return const <String, bool>{};
    }

    final rawContent = await _stateFile.readAsString();
    if (rawContent.trim().isEmpty) {
      return const <String, bool>{};
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(rawContent);
    } on FormatException {
      return const <String, bool>{};
    }
    if (decoded is! Map) {
      return const <String, bool>{};
    }

    final enabledById = <String, bool>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! bool) {
        continue;
      }
      enabledById[entry.key as String] = entry.value as bool;
    }
    return enabledById;
  }

  Future<void> _persistEnabledState() async {
    final parentDirectory = _stateFile.parent;
    if (!await parentDirectory.exists()) {
      await parentDirectory.create(recursive: true);
    }
    await _stateFile.writeAsString(
      jsonEncode(_enabledById),
      flush: true,
    );
  }
}
