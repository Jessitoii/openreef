import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_frontmatter_parser.dart';
import 'package:openreef/skills/skill_package_models.dart';
import 'package:openreef/skills/skill_package_repository.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_manifest.dart';

class SkillPackageService {
  SkillPackageService({
    required SkillRegistry registry,
    required ToolCatalog toolCatalog,
    required SkillPackageRepository repository,
    required bool Function(String skillId) isEnabled,
    SkillFrontmatterParser parser = const SkillFrontmatterParser(),
  })  : _registry = registry,
        _toolCatalog = toolCatalog,
        _repository = repository,
        _isEnabled = isEnabled,
        _parser = parser;

  final SkillRegistry _registry;
  final ToolCatalog _toolCatalog;
  final SkillPackageRepository _repository;
  final bool Function(String skillId) _isEnabled;
  final SkillFrontmatterParser _parser;

  Future<List<SkillPackageRef>> listPackages() async {
    final packages = await _discoverAllPackages();
    final refs = <SkillPackageRef>[];
    for (final package in packages) {
      final detail = await _hydrateDetail(package);
      refs.add(detail.ref);
    }
    refs.sort((a, b) => a.displayName.compareTo(b.displayName));
    return refs;
  }

  Future<SkillPackageDetail?> hydrateById(String skillId) async {
    final packages = await _discoverAllPackages();
    for (final package in packages) {
      if (package.id == skillId) {
        return _hydrateDetail(package);
      }
    }
    return null;
  }

  Future<SkillPackageDetail> _hydrateDetail(_DiscoveredSkillPackage package) async {
    final writable = package.sourceType != SkillSourceType.builtin;
    final enabled = _isEnabled(package.id);
    final tree = await _buildTree(package.rootPath, writable: writable);
    final validation = _validate(package, tree);
    final lastModified = await _repository.lastModified(package.rootPath);
    final ref = SkillPackageRef(
      id: package.id,
      displayName: package.displayName,
      sourceType: package.sourceType,
      rootPath: package.rootPath,
      isWritable: writable,
      isEnabled: enabled,
      validationSummary: validation,
      lastModified: lastModified,
    );
    return SkillPackageDetail(
      ref: ref,
      fileTree: tree,
      rawSkillMarkdown: package.rawSkillMarkdown,
      parsedSkill: validation.isValid ? package.manifest : null,
      validationSummary: validation,
      permissionsAndToolsSummary: _permissionsSummary(package),
      lastModified: lastModified,
      isMalformed: !validation.isValid,
    );
  }

  Future<SkillPackageDetail> createLocalPackage({
    required String id,
    required String markdown,
    Map<String, String>? supportFiles,
  }) async {
    final root = await _repository.createLocalPackageDirectory(id);
    await _repository.writeTextFile(
      filePath: p.join(root.path, 'SKILL.md'),
      content: markdown,
    );
    for (final entry in (supportFiles ?? const <String, String>{}).entries) {
      await _repository.writeTextFile(
        filePath: p.join(root.path, entry.key),
        content: entry.value,
      );
    }
    final detail = await _locateSkillById(id);
    if (detail == null) {
      throw const SkillDiscoveryException('created_skill_not_discovered');
    }
    return detail;
  }

  Future<SkillPackageDetail> saveFile({
    required String skillId,
    required String relativePath,
    required String content,
  }) async {
    final package = await _requirePackage(skillId);
    if (package.sourceType == SkillSourceType.builtin) {
      throw StateError('built_in_skill_is_read_only');
    }
    await _repository.writeTextFile(
      filePath: p.join(package.rootPath, relativePath),
      content: content,
    );
    return hydrateById(skillId).then((detail) {
      if (detail == null) {
        throw const SkillDiscoveryException('missing_skill_after_save');
      }
      return detail;
    });
  }

  Future<String?> readFileContent({
    required String skillId,
    required String relativePath,
  }) async {
    final package = await _requirePackage(skillId);
    final filePath = p.join(package.rootPath, relativePath);
    return _repository.readTextIfExists(filePath);
  }

  Future<SkillPackageDetail> deletePackage(String skillId) async {
    final package = await _requirePackage(skillId);
    if (package.sourceType == SkillSourceType.builtin) {
      throw StateError('built_in_skill_is_read_only');
    }
    await _repository.deleteDirectory(package.rootPath);
    final refreshed = await _locateSkillById(skillId);
    if (refreshed != null) {
      return refreshed;
    }
    return SkillPackageDetail(
      ref: SkillPackageRef(
        id: package.id,
        displayName: package.displayName,
        sourceType: package.sourceType,
        rootPath: package.rootPath,
        isWritable: false,
        isEnabled: _isEnabled(package.id),
        validationSummary: const SkillValidationSummary(
          issues: <SkillValidationIssue>[
            SkillValidationIssue(
              message: 'package_deleted',
            ),
          ],
          isValid: false,
        ),
        lastModified: null,
      ),
      fileTree: const <SkillFileNode>[],
      rawSkillMarkdown: null,
      parsedSkill: null,
      validationSummary: const SkillValidationSummary(
        issues: <SkillValidationIssue>[
          SkillValidationIssue(message: 'package_deleted'),
        ],
        isValid: false,
      ),
      permissionsAndToolsSummary: 'Deleted package.',
      lastModified: null,
      isMalformed: true,
    );
  }

  Future<SkillPackageDetail> setEnabled({
    required String skillId,
    required bool enabled,
  }) async {
    final detail = await hydrateById(skillId);
    if (detail == null) {
      throw SkillDiscoveryException('missing_skill:$skillId');
    }
    return detail;
  }

  Future<SkillPackageDetail?> _locateSkillById(String skillId) async {
    final packages = await _discoverAllPackages();
    for (final package in packages) {
      if (package.id == skillId) {
        return _hydrateDetail(package);
      }
    }
    return null;
  }

  Future<_DiscoveredSkillPackage> _requirePackage(String skillId) async {
    final packages = await _discoverAllPackages();
    for (final package in packages) {
      if (package.id == skillId) {
        return package;
      }
    }
    throw SkillDiscoveryException('missing_skill:$skillId');
  }

  Future<List<SkillFileNode>> _buildTree(
    String rootPath, {
    required bool writable,
  }) async {
    final nodes = <SkillFileNode>[];
    final root = Directory(rootPath);
    if (!await root.exists()) {
      return nodes;
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relativePath = p.relative(entity.path, from: rootPath);
      if (relativePath.isEmpty) {
        continue;
      }
      if (entity is Directory) {
        nodes.add(
          SkillFileNode(
            relativePath: relativePath,
            kind: SkillFileKind.directory,
            isEditable: false,
            size: 0,
          ),
        );
      } else if (entity is File) {
        final kind = _classifyFile(relativePath);
        nodes.add(
          SkillFileNode(
            relativePath: relativePath,
            kind: kind,
            isEditable: writable && kind == SkillFileKind.text,
            size: await entity.length(),
          ),
        );
      }
    }
    nodes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return nodes;
  }

  SkillFileKind _classifyFile(String relativePath) {
    if (relativePath.toUpperCase() == 'SKILL.MD') {
      return SkillFileKind.text;
    }
    final extension = p.extension(relativePath).toLowerCase();
    const textExtensions = <String>{
      '.md',
      '.txt',
      '.yaml',
      '.yml',
      '.json',
      '.xml',
      '.csv',
      '.toml',
    };
    if (textExtensions.contains(extension)) {
      return SkillFileKind.text;
    }
    const binaryExtensions = <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.pdf',
      '.zip',
      '.mp3',
      '.mp4',
    };
    if (binaryExtensions.contains(extension)) {
      return SkillFileKind.binary;
    }
    return SkillFileKind.unsupported;
  }

  SkillValidationSummary _validate(
    _DiscoveredSkillPackage package,
    List<SkillFileNode> tree,
  ) {
    final issues = <SkillValidationIssue>[];
    final skillMarkdownExists = tree.any(
      (node) => node.relativePath.toUpperCase() == 'SKILL.MD',
    );
    if (!skillMarkdownExists) {
      issues.add(
        const SkillValidationIssue(
          message: 'missing_skill_md',
        ),
      );
      return SkillValidationSummary(issues: issues, isValid: false);
    }

    final rawContent = package.rawSkillMarkdown;
    if (rawContent == null) {
      issues.add(
        const SkillValidationIssue(
          message: 'missing_skill_md',
        ),
      );
      return SkillValidationSummary(issues: issues, isValid: false);
    }

    try {
      _parser.parse(rawContent);
    } on SkillParseException catch (error) {
      issues.add(SkillValidationIssue(message: error.message));
      return SkillValidationSummary(issues: issues, isValid: false);
    }

    final missingTools = package.manifest?.toolsRequired ?? const <String>[];
    final unresolvedTools = missingTools
        .where((toolId) => _toolCatalog.byId(toolId) == null)
        .toList(growable: false);
    if (unresolvedTools.isNotEmpty) {
      issues.add(
        SkillValidationIssue(
          message: 'missing_tools:${unresolvedTools.join(',')}',
        ),
      );
    }

    final hasUnsupported = tree.any((node) => node.kind == SkillFileKind.unsupported);
    if (hasUnsupported) {
      issues.add(
        const SkillValidationIssue(
          message: 'unsupported_file_present',
          isError: false,
        ),
      );
    }

    return SkillValidationSummary(issues: issues, isValid: issues.every((issue) => !issue.isError));
  }

  String _permissionsSummary(_DiscoveredSkillPackage package) {
    final tools = package.manifest?.toolsRequired ?? const <String>[];
    if (tools.isEmpty) {
      return 'No required tools declared.';
    }
    return 'Requires: ${tools.join(', ')}';
  }

  Future<List<_DiscoveredSkillPackage>> _discoverAllPackages() async {
    final packages = <_DiscoveredSkillPackage>[];
    for (final root in _registry.roots) {
      final directory = Directory(root.path);
      if (!await directory.exists()) {
        continue;
      }
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! Directory) {
          continue;
        }
        final skillMarkdownPath = p.join(entry.path, 'SKILL.md');
        final skillFile = File(skillMarkdownPath);
        String? rawContent;
        SkillManifest? manifest;
        String? body;
        try {
          if (await skillFile.exists()) {
            rawContent = await skillFile.readAsString();
            final parsed = _parser.parse(rawContent);
            manifest = parsed.manifest;
            body = parsed.body;
          }
        } on SkillParseException {
          rawContent = await skillFile.readAsString();
        }
        packages.add(
          _DiscoveredSkillPackage(
            id: p.basename(entry.path),
            displayName: manifest?.name ?? p.basename(entry.path),
            rootPath: entry.path,
            skillMarkdownPath: skillMarkdownPath,
            sourceType: root.sourceType,
            rawSkillMarkdown: rawContent,
            bodyContent: body,
            manifest: manifest,
          ),
        );
      }
    }
    return packages;
  }
}

class _DiscoveredSkillPackage {
  const _DiscoveredSkillPackage({
    required this.id,
    required this.displayName,
    required this.rootPath,
    required this.skillMarkdownPath,
    required this.sourceType,
    required this.rawSkillMarkdown,
    required this.bodyContent,
    required this.manifest,
  });

  final String id;
  final String displayName;
  final String rootPath;
  final String skillMarkdownPath;
  final SkillSourceType sourceType;
  final String? rawSkillMarkdown;
  final String? bodyContent;
  final SkillManifest? manifest;
}
