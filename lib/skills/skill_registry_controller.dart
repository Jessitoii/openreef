import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/skills/skill_package_models.dart';
import 'package:openreef/skills/skill_package_service.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';

class SkillRegistryController {
  SkillRegistryController({
    required SkillRuntimeCatalog catalog,
    required SkillPackageService packageService,
  }) : _catalog = catalog {
    _packageService = packageService;
    _catalog.addListener(_syncSnapshots);
    _syncSnapshots();
  }

  final SkillRuntimeCatalog _catalog;
  late final SkillPackageService _packageService;
  final ValueNotifier<List<SkillRuntimeSnapshot>> _skills =
      ValueNotifier<List<SkillRuntimeSnapshot>>(const <SkillRuntimeSnapshot>[]);
  final ValueNotifier<List<SkillPackageRef>> _packages =
      ValueNotifier<List<SkillPackageRef>>(const <SkillPackageRef>[]);
  final ValueNotifier<SkillPackageDetail?> _selectedPackage =
      ValueNotifier<SkillPackageDetail?>(null);

  ValueListenable<List<SkillRuntimeSnapshot>> get skills => _skills;
  ValueListenable<List<SkillPackageRef>> get packages => _packages;
  ValueListenable<SkillPackageDetail?> get selectedPackage => _selectedPackage;

  Future<void> reload() async {
    await _catalog.reload();
    await _syncPackages();
  }

  Future<void> setSkillEnabled(String skillId, bool enabled) {
    return _catalog.setSkillEnabled(skillId, enabled).then((_) async {
      await _syncPackages();
      final detail = await _packageService.hydrateById(skillId);
      if (detail != null) {
        _selectedPackage.value = detail;
      }
    });
  }

  Future<void> selectPackage(String skillId) async {
    _selectedPackage.value = await _packageService.hydrateById(skillId);
  }

  Future<SkillPackageDetail?> createPackage({
    required String id,
    required String markdown,
    Map<String, String>? supportFiles,
  }) async {
    final detail = await _packageService.createLocalPackage(
      id: id,
      markdown: markdown,
      supportFiles: supportFiles,
    );
    await reload();
    _selectedPackage.value = detail;
    return detail;
  }

  Future<SkillPackageDetail?> saveFile({
    required String skillId,
    required String relativePath,
    required String content,
  }) async {
    final detail = await _packageService.saveFile(
      skillId: skillId,
      relativePath: relativePath,
      content: content,
    );
    await reload();
    _selectedPackage.value = detail;
    return detail;
  }

  Future<String?> loadFileContent({
    required String skillId,
    required String relativePath,
  }) {
    return _packageService.readFileContent(
      skillId: skillId,
      relativePath: relativePath,
    );
  }

  Future<SkillPackageDetail?> deletePackage(String skillId) async {
    final detail = await _packageService.deletePackage(skillId);
    await reload();
    if (_selectedPackage.value?.ref.id == skillId) {
      _selectedPackage.value = null;
    }
    return detail;
  }

  void _syncSnapshots() {
    _skills.value = _catalog.snapshots;
    unawaited(_syncPackages());
  }

  Future<void> _syncPackages() async {
    _packages.value = await _packageService.listPackages();
  }
}
