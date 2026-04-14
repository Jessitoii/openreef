import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_manifest.dart';

enum SkillFileKind { directory, text, binary, unsupported }

class SkillValidationIssue {
  const SkillValidationIssue({
    required this.message,
    this.isError = true,
  });

  final String message;
  final bool isError;
}

class SkillValidationSummary {
  const SkillValidationSummary({
    required this.issues,
    required this.isValid,
  });

  final List<SkillValidationIssue> issues;
  final bool isValid;

  bool get hasIssues => issues.isNotEmpty;

  factory SkillValidationSummary.empty() {
    return const SkillValidationSummary(
      issues: <SkillValidationIssue>[],
      isValid: true,
    );
  }
}

class SkillPackageRef {
  const SkillPackageRef({
    required this.id,
    required this.displayName,
    required this.sourceType,
    required this.rootPath,
    required this.isWritable,
    required this.isEnabled,
    required this.validationSummary,
    required this.lastModified,
  });

  final String id;
  final String displayName;
  final SkillSourceType sourceType;
  final String rootPath;
  final bool isWritable;
  final bool isEnabled;
  final SkillValidationSummary validationSummary;
  final DateTime? lastModified;
}

class SkillFileNode {
  const SkillFileNode({
    required this.relativePath,
    required this.kind,
    required this.isEditable,
    required this.size,
  });

  final String relativePath;
  final SkillFileKind kind;
  final bool isEditable;
  final int size;
}

class SkillPackageDetail {
  const SkillPackageDetail({
    required this.ref,
    required this.fileTree,
    required this.rawSkillMarkdown,
    required this.parsedSkill,
    required this.validationSummary,
    required this.permissionsAndToolsSummary,
    required this.lastModified,
    required this.isMalformed,
  });

  final SkillPackageRef ref;
  final List<SkillFileNode> fileTree;
  final String? rawSkillMarkdown;
  final SkillManifest? parsedSkill;
  final SkillValidationSummary validationSummary;
  final String permissionsAndToolsSummary;
  final DateTime? lastModified;
  final bool isMalformed;
}

class SkillPackageWriteResult {
  const SkillPackageWriteResult({
    required this.detail,
  });

  final SkillPackageDetail detail;
}

class SkillPackagePaths {
  const SkillPackagePaths({
    required this.rootPath,
    required this.skillMarkdownPath,
  });

  final String rootPath;
  final String skillMarkdownPath;
}

class SkillFileContent {
  const SkillFileContent({
    required this.path,
    required this.content,
    required this.kind,
  });

  final String path;
  final String content;
  final SkillFileKind kind;
}

extension SkillPackageDetailFromSkill on Skill {
  SkillPackageRef toPackageRef({
    required bool isWritable,
    required bool isEnabled,
    required SkillValidationSummary validationSummary,
    DateTime? lastModified,
  }) {
    return SkillPackageRef(
      id: id,
      displayName: name,
      sourceType: sourceType,
      rootPath: directoryPath,
      isWritable: isWritable,
      isEnabled: isEnabled,
      validationSummary: validationSummary,
      lastModified: lastModified,
    );
  }
}
