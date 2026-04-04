import 'dart:io';

import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:path_provider/path_provider.dart';

enum SkillCreatorPhase {
  captureIntent,
  interviewTriggers,
  interviewOutputFormat,
  interviewEdgeCases,
  interviewTools,
  interviewSuccessCriteria,
  interviewExamples,
  preview,
  confirmed,
}

class SkillCreatorSession {
  SkillCreatorSession({
    required this.sessionId,
    required this.createdAt,
    this.intent = '',
    this.triggers = '',
    this.outputFormat = '',
    this.edgeCases = '',
    this.toolsRequired = const <String>[],
    this.successCriteria = '',
    this.examples = '',
    this.phase = SkillCreatorPhase.captureIntent,
  });

  final String sessionId;
  final DateTime createdAt;
  String intent;
  String triggers;
  String outputFormat;
  String edgeCases;
  List<String> toolsRequired;
  String successCriteria;
  String examples;
  SkillCreatorPhase phase;
}

class SkillCreatorResponse {
  const SkillCreatorResponse({
    required this.message,
    this.previewMarkdown,
    this.readyToCreate = false,
  });

  final String message;
  final String? previewMarkdown;
  final bool readyToCreate;
}

class SkillCreator {
  SkillCreator({
    required SkillRegistryController registryController,
    Future<Directory> Function()? documentsDirectoryProvider,
    DateTime Function()? clock,
  })  : _registryController = registryController,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _clock = clock ?? DateTime.now;

  final SkillRegistryController _registryController;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final DateTime Function() _clock;
  final Map<String, SkillCreatorSession> _sessions =
      <String, SkillCreatorSession>{};

  SkillCreatorSession startSession(
    String sessionId, {
    String? initialUserMessage,
  }) {
    final session = SkillCreatorSession(
      sessionId: sessionId,
      createdAt: _clock(),
      intent: initialUserMessage?.trim() ?? '',
    );
    _sessions[sessionId] = session;
    return session;
  }

  SkillCreatorSession? sessionFor(String sessionId) => _sessions[sessionId];

  SkillCreatorResponse handleUserMessage(String sessionId, String message) {
    final session = _sessions[sessionId] ?? startSession(sessionId);
    final trimmed = message.trim();

    switch (session.phase) {
      case SkillCreatorPhase.captureIntent:
        if (session.intent.isEmpty) {
          session.intent = trimmed;
        }
        session.phase = SkillCreatorPhase.interviewTriggers;
        return const SkillCreatorResponse(
          message:
              'When should this skill trigger? Share typical phrases or contexts.',
        );
      case SkillCreatorPhase.interviewTriggers:
        session.triggers = trimmed;
        session.phase = SkillCreatorPhase.interviewOutputFormat;
        return const SkillCreatorResponse(
          message:
              'What output format should it produce? (structure, tone, files)',
        );
      case SkillCreatorPhase.interviewOutputFormat:
        session.outputFormat = trimmed;
        session.phase = SkillCreatorPhase.interviewEdgeCases;
        return const SkillCreatorResponse(
          message:
              'Any edge cases or constraints the skill must handle or avoid?',
        );
      case SkillCreatorPhase.interviewEdgeCases:
        session.edgeCases = trimmed;
        session.phase = SkillCreatorPhase.interviewTools;
        return const SkillCreatorResponse(
          message:
              'Which tools are required? Provide a comma-separated list (or "none").',
        );
      case SkillCreatorPhase.interviewTools:
        session.toolsRequired = _parseTools(trimmed);
        session.phase = SkillCreatorPhase.interviewSuccessCriteria;
        return const SkillCreatorResponse(
          message:
              'What does success look like? Define the expected outcome.',
        );
      case SkillCreatorPhase.interviewSuccessCriteria:
        session.successCriteria = trimmed;
        session.phase = SkillCreatorPhase.interviewExamples;
        return const SkillCreatorResponse(
          message:
              'Provide one or two example user requests and desired outputs.',
        );
      case SkillCreatorPhase.interviewExamples:
        session.examples = trimmed;
        session.phase = SkillCreatorPhase.preview;
        final preview = buildSkillMarkdown(session);
        return SkillCreatorResponse(
          message:
              'Here is a draft SKILL.md. Reply "confirm" to create it or provide edits.',
          previewMarkdown: preview,
          readyToCreate: true,
        );
      case SkillCreatorPhase.preview:
        if (_isConfirm(trimmed)) {
          session.phase = SkillCreatorPhase.confirmed;
          final preview = buildSkillMarkdown(session);
          return SkillCreatorResponse(
            message: 'Confirmed. Creating the skill now.',
            previewMarkdown: preview,
            readyToCreate: true,
          );
        }
        session.phase = SkillCreatorPhase.captureIntent;
        session.intent = trimmed;
        return const SkillCreatorResponse(
          message:
              'Updated intent noted. When should this skill trigger? Share typical phrases or contexts.',
        );
      case SkillCreatorPhase.confirmed:
        return const SkillCreatorResponse(
          message: 'Skill creation already confirmed.',
          readyToCreate: true,
        );
    }
  }

  Future<String> confirmAndCreate(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('missing_skill_creator_session');
    }

    if (session.phase != SkillCreatorPhase.confirmed) {
      throw StateError('skill_creator_not_confirmed');
    }

    final markdown = buildSkillMarkdown(session);
    final slug = _slugify(session.intent);
    final docsDir = await _documentsDirectoryProvider();
    final skillsDir = Directory('${docsDir.path}${Platform.pathSeparator}skills');
    if (!await skillsDir.exists()) {
      await skillsDir.create(recursive: true);
    }

    final skillDir = Directory(
      '${skillsDir.path}${Platform.pathSeparator}$slug',
    );
    if (!await skillDir.exists()) {
      await skillDir.create(recursive: true);
    }

    final skillFile = File(
      '${skillDir.path}${Platform.pathSeparator}SKILL.md',
    );
    await skillFile.writeAsString(markdown);
    await _registryController.reload();
    return skillDir.path;
  }

  String buildSkillMarkdown(SkillCreatorSession session) {
    final name = _slugify(session.intent);
    final description = _buildPushyDescription(
      intent: session.intent,
      triggers: session.triggers,
    );
    final toolsRequired = session.toolsRequired.isEmpty
        ? const <String>['none']
        : session.toolsRequired;

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('name: $name')
      ..writeln('description: ${_escapeYaml(description)}')
      ..writeln('tools_required: [${toolsRequired.join(', ')}]')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${_titleCase(session.intent)}')
      ..writeln()
      ..writeln('## Overview')
      ..writeln(session.intent.isEmpty ? 'Describe the goal.' : session.intent)
      ..writeln()
      ..writeln('## When to Use')
      ..writeln(session.triggers.isEmpty ? 'Specify triggers.' : session.triggers)
      ..writeln()
      ..writeln('## Inputs')
      ..writeln('Describe required inputs, files, or parameters.')
      ..writeln()
      ..writeln('## Outputs')
      ..writeln(
        session.outputFormat.isEmpty
            ? 'Describe the output format.'
            : session.outputFormat,
      )
      ..writeln()
      ..writeln('## Steps')
      ..writeln('1. Clarify missing details if needed.')
      ..writeln('2. Execute the workflow in clear, ordered steps.')
      ..writeln('3. Confirm the final output matches the expected format.')
      ..writeln()
      ..writeln('## Constraints')
      ..writeln(
        session.edgeCases.isEmpty
            ? 'List edge cases, exclusions, or safety constraints.'
            : session.edgeCases,
      )
      ..writeln()
      ..writeln('## Success Criteria')
      ..writeln(
        session.successCriteria.isEmpty
            ? 'Define what success looks like.'
            : session.successCriteria,
      )
      ..writeln()
      ..writeln('## Examples')
      ..writeln(
        session.examples.isEmpty
            ? 'Add example inputs and outputs.'
            : session.examples,
      );

    return buffer.toString();
  }

  static List<String> _parseTools(String raw) {
    if (raw.trim().isEmpty || raw.trim().toLowerCase() == 'none') {
      return <String>[];
    }
    return raw
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isConfirm(String message) {
    final normalized = message.toLowerCase();
    return normalized == 'confirm' ||
        normalized == 'yes' ||
        normalized == 'create' ||
        normalized == 'ok';
  }

  static String _slugify(String input) {
    final lowered = input.toLowerCase();
    final slug = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+'), '')
        .replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'custom-skill' : slug;
  }

  static String _titleCase(String input) {
    if (input.trim().isEmpty) {
      return 'New Skill';
    }
    final words = input.trim().split(RegExp(r'\s+'));
    return words
        .map(
          (word) =>
              word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  static String _buildPushyDescription({
    required String intent,
    required String triggers,
  }) {
    final intentText = intent.trim().isEmpty ? 'This skill' : intent.trim();
    final triggerText = triggers.trim().isEmpty
        ? 'Use it whenever the user describes this task.'
        : 'Use it whenever the user mentions $triggers, even if they do not ask explicitly.';
    return '$intentText. $triggerText';
  }

  static String _escapeYaml(String value) {
    final escaped = value.replaceAll('"', '\\"');
    return '"$escaped"';
  }
}
