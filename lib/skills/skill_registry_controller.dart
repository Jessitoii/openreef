import 'package:flutter/foundation.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';

class SkillRegistryController {
  SkillRegistryController({
    required SkillRuntimeCatalog catalog,
  }) : _catalog = catalog {
    _catalog.addListener(_syncSnapshots);
    _syncSnapshots();
  }

  final SkillRuntimeCatalog _catalog;
  final ValueNotifier<List<SkillRuntimeSnapshot>> _skills =
      ValueNotifier<List<SkillRuntimeSnapshot>>(const <SkillRuntimeSnapshot>[]);

  ValueListenable<List<SkillRuntimeSnapshot>> get skills => _skills;

  Future<void> reload() async {
    await _catalog.reload();
  }

  Future<void> setSkillEnabled(String skillId, bool enabled) {
    return _catalog.setSkillEnabled(skillId, enabled);
  }

  void _syncSnapshots() {
    _skills.value = _catalog.snapshots;
  }
}
