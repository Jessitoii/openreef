import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:openreef/skills/skill_package_models.dart';

class SkillPackageRepository {
  SkillPackageRepository({
    required this.localRootDirectory,
    required this.builtinRootDirectory,
  });

  final Directory localRootDirectory;
  final Directory builtinRootDirectory;

  Future<List<SkillPackagePaths>> listPackagePaths() async {
    final results = <SkillPackagePaths>[];
    await for (final entry in _listSkillDirectories(builtinRootDirectory)) {
      results.add(
        SkillPackagePaths(
          rootPath: entry.path,
          skillMarkdownPath: p.join(entry.path, 'SKILL.md'),
        ),
      );
    }
    await for (final entry in _listSkillDirectories(localRootDirectory)) {
      results.add(
        SkillPackagePaths(
          rootPath: entry.path,
          skillMarkdownPath: p.join(entry.path, 'SKILL.md'),
        ),
      );
    }
    return List<SkillPackagePaths>.unmodifiable(results);
  }

  Future<Directory> createLocalPackageDirectory(String slug) async {
    if (!await localRootDirectory.exists()) {
      await localRootDirectory.create(recursive: true);
    }
    final directory = Directory(p.join(localRootDirectory.path, slug));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> writeTextFile({
    required String filePath,
    required String content,
  }) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<void> deleteDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String?> readTextIfExists(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<List<FileSystemEntity>> listDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return const <FileSystemEntity>[];
    }
    return directory.list(followLinks: false).toList();
  }

  Future<DateTime?> lastModified(String path) async {
    final type = await FileSystemEntity.type(path);
    final entity = type == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);
    if (!await entity.exists()) {
      return null;
    }
    return (await entity.stat()).modified;
  }

  Future<bool> exists(String path) async {
    return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
  }

  Stream<Directory> _listSkillDirectories(Directory root) async* {
    if (!await root.exists()) {
      return;
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final skillMarkdown = File(p.join(entity.path, 'SKILL.md'));
        if (await skillMarkdown.exists()) {
          yield entity;
        }
      }
    }
  }
}
