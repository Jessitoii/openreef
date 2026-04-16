import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_manifest.dart';
import 'package:yaml/yaml.dart';

class ParsedSkillMarkdown {
  const ParsedSkillMarkdown({required this.manifest, required this.body});

  final SkillManifest manifest;
  final String body;
}

class SkillFrontmatterParser {
  const SkillFrontmatterParser();

  ParsedSkillMarkdown parse(String markdown) {
    if (!markdown.startsWith('---')) {
      throw const SkillParseException('missing_frontmatter');
    }

    final closingIndex = _findClosingDelimiter(markdown);
    if (closingIndex == null) {
      throw const SkillParseException('unterminated_frontmatter');
    }

    final yamlContent = markdown.substring(4, closingIndex);
    final bodyStart = closingIndex + 4;
    final body = bodyStart >= markdown.length
        ? ''
        : markdown.substring(bodyStart);

    final dynamic parsedYaml;
    try {
      parsedYaml = loadYaml(yamlContent);
    } on YamlException {
      throw const SkillParseException('invalid_frontmatter_yaml');
    }

    if (parsedYaml is! YamlMap) {
      throw const SkillParseException('invalid_frontmatter_root');
    }

    final toolsRequiredNode = parsedYaml['tools_required'];
    final toolsRequired = <String>[];
    if (toolsRequiredNode != null) {
      if (toolsRequiredNode is! YamlList) {
        throw const SkillParseException('invalid_tools_required');
      }
      for (final entry in toolsRequiredNode) {
        if (entry is! String) {
          throw const SkillParseException('invalid_tools_required');
        }
        toolsRequired.add(entry);
      }
    }

    final descriptionNode = parsedYaml['description'];
    final description = descriptionNode is String ? descriptionNode : '';
    final nameNode = parsedYaml['name'];
    final name = nameNode is String && nameNode.trim().isNotEmpty
        ? nameNode.trim()
        : null;
    final triggerPatterns = _parseStringList(
      parsedYaml['trigger_patterns'],
      errorMessage: 'invalid_trigger_patterns',
      normalize: true,
    );
    final activationTerms = _parseStringList(
      parsedYaml['activation_terms'],
      errorMessage: 'invalid_activation_terms',
      normalize: true,
    );
    final allowedModes = _parseStringList(
      parsedYaml['allowed_modes'],
      errorMessage: 'invalid_allowed_modes',
      normalize: true,
    );
    final incompatibleSkillIds = _parseStringList(
      parsedYaml['incompatible_skill_ids'],
      errorMessage: 'invalid_incompatible_skill_ids',
      normalize: true,
    );
    final priorityNode = parsedYaml['priority'];
    final maxTokensNode = parsedYaml['max_tokens'];

    return ParsedSkillMarkdown(
      manifest: SkillManifest(
        toolsRequired: toolsRequired,
        name: name,
        description: description,
        triggerPatterns: triggerPatterns,
        priority: priorityNode is int ? priorityNode : 0,
        maxTokens: maxTokensNode is int && maxTokensNode > 0
            ? maxTokensNode
            : 150,
        activationTerms: activationTerms,
        allowedModes: allowedModes,
        incompatibleSkillIds: incompatibleSkillIds,
      ),
      body: body,
    );
  }

  List<String> _parseStringList(
    Object? rawValue, {
    required String errorMessage,
    bool normalize = false,
  }) {
    if (rawValue == null) {
      return const <String>[];
    }
    if (rawValue is! YamlList) {
      throw SkillParseException(errorMessage);
    }

    final values = <String>[];
    for (final entry in rawValue) {
      if (entry is! String) {
        throw SkillParseException(errorMessage);
      }
      final value = normalize ? _normalizePattern(entry) : entry.trim();
      if (value.isEmpty) {
        continue;
      }
      values.add(value);
    }
    return List<String>.unmodifiable(values);
  }

  String _normalizePattern(String pattern) {
    final normalized = pattern.trim().toLowerCase();
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  int? _findClosingDelimiter(String markdown) {
    var delimiterIndex = markdown.indexOf('\n---\n', 4);
    if (delimiterIndex == -1) {
      delimiterIndex = markdown.indexOf('\r\n---\r\n', 4);
      if (delimiterIndex != -1) {
        return delimiterIndex + 2; // \r\n length is 2
      }
      delimiterIndex = markdown.indexOf('\n---\r\n', 4);
      if (delimiterIndex != -1) {
        return delimiterIndex + 1;
      }
      delimiterIndex = markdown.indexOf('\r\n---\n', 4);
      if (delimiterIndex != -1) {
        return delimiterIndex + 2;
      }
    } else {
      return delimiterIndex + 1;
    }

    if (markdown.endsWith('\n---') || markdown.endsWith('\r\n---')) {
      return markdown.lastIndexOf('---');
    }

    return null;
  }
}
