import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';

enum CapabilityKind { nativeTool, mcpTool, skill }

class CapabilityCandidate {
  const CapabilityCandidate({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.description,
    this.capabilityPhrases = const <String>[],
    this.usageExamples = const <String>[],
    this.tags = const <String>[],
    this.allowedModes = const <ExecutionMode>{},
    this.enabled = true,
    this.requiresConfirmation = false,
    this.destructive = false,
    this.expensive = false,
    this.longRunning = false,
    this.requiresWorkflowState = false,
    this.runtimeMetadata = const <String, Object?>{},
    this.tool,
    this.skill,
    this.requiredToolIds = const <String>[],
    this.incompatibleSkillIds = const <String>[],
  });

  final String id;
  final CapabilityKind kind;
  final String displayName;
  final String description;
  final List<String> capabilityPhrases;
  final List<String> usageExamples;
  final List<String> tags;
  final Set<ExecutionMode> allowedModes;
  final bool enabled;
  final bool requiresConfirmation;
  final bool destructive;
  final bool expensive;
  final bool longRunning;
  final bool requiresWorkflowState;
  final Map<String, Object?> runtimeMetadata;
  final ToolDefinition? tool;
  final SkillDefinition? skill;
  final List<String> requiredToolIds;
  final List<String> incompatibleSkillIds;

  String get sourceKey =>
      runtimeMetadata['sourceId']?.toString() ??
      runtimeMetadata['source']?.toString() ??
      kind.name;
}

class CapabilityRetrievedCandidate {
  const CapabilityRetrievedCandidate({
    required this.candidate,
    required this.score,
    required this.documentHash,
    required this.document,
  });

  final CapabilityCandidate candidate;
  final double score;
  final String documentHash;
  final String document;
}

class CandidateSelectionProposal {
  const CandidateSelectionProposal({
    this.primaryToolIds = const <String>[],
    this.fallbackToolIds = const <String>[],
    this.selectedSkillIds = const <String>[],
    this.rejected = const <CandidateRejection>[],
    this.notes = const <String>[],
    this.degraded = false,
    this.degradationReason,
    this.violations = const <String>[],
  });

  final List<String> primaryToolIds;
  final List<String> fallbackToolIds;
  final List<String> selectedSkillIds;
  final List<CandidateRejection> rejected;
  final List<String> notes;
  final bool degraded;
  final String? degradationReason;
  final List<String> violations;
}

class CandidateRejection {
  const CandidateRejection({required this.id, required this.reason});

  final String id;
  final String reason;
}

abstract class CapabilitySelector {
  Future<CandidateSelectionProposal> select({
    required String userMessage,
    required ExecutionMode executionMode,
    required List<CapabilityRetrievedCandidate> retrievedCandidates,
  });
}

class SemanticFallbackCapabilitySelector implements CapabilitySelector {
  const SemanticFallbackCapabilitySelector({
    this.primaryToolLimit = 8,
    this.skillLimit = 2,
  });

  final int primaryToolLimit;
  final int skillLimit;

  @override
  Future<CandidateSelectionProposal> select({
    required String userMessage,
    required ExecutionMode executionMode,
    required List<CapabilityRetrievedCandidate> retrievedCandidates,
  }) async {
    final tools = retrievedCandidates
        .where((entry) => entry.candidate.kind != CapabilityKind.skill)
        .take(primaryToolLimit)
        .map((entry) => entry.candidate.id)
        .toList(growable: false);
    final skills = retrievedCandidates
        .where((entry) => entry.candidate.kind == CapabilityKind.skill)
        .take(skillLimit)
        .map((entry) => entry.candidate.id)
        .toList(growable: false);
    return CandidateSelectionProposal(
      primaryToolIds: tools,
      selectedSkillIds: skills,
      degraded: true,
      degradationReason: 'selector_degraded:semantic_fallback',
      notes: const <String>[
        'Deterministic semantic fallback used; no keyword routing applied.',
      ],
    );
  }
}

class CandidateDocumentBuilder {
  const CandidateDocumentBuilder();

  String build(CapabilityCandidate candidate) {
    final buffer = StringBuffer()
      ..writeln('kind: ${candidate.kind.name}')
      ..writeln('id: ${candidate.id}')
      ..writeln('displayName: ${candidate.displayName}')
      ..writeln('description: ${candidate.description}');
    if (candidate.capabilityPhrases.isNotEmpty) {
      buffer.writeln(
        'capabilityPhrases: ${candidate.capabilityPhrases.join(' | ')}',
      );
    }
    if (candidate.usageExamples.isNotEmpty) {
      buffer.writeln('usageExamples: ${candidate.usageExamples.join(' | ')}');
    }
    if (candidate.tags.isNotEmpty) {
      buffer.writeln('tags: ${candidate.tags.join(', ')}');
    }
    if (candidate.allowedModes.isNotEmpty) {
      buffer.writeln(
        'allowedModes: ${candidate.allowedModes.map((mode) => mode.name).join(', ')}',
      );
    }
    if (candidate.requiredToolIds.isNotEmpty) {
      buffer.writeln('requiredTools: ${candidate.requiredToolIds.join(', ')}');
    }
    if (candidate.incompatibleSkillIds.isNotEmpty) {
      buffer.writeln(
        'incompatibleSkills: ${candidate.incompatibleSkillIds.join(', ')}',
      );
    }
    final constraints = <String>[
      if (!candidate.enabled) 'disabled',
      if (candidate.requiresConfirmation) 'requires confirmation',
      if (candidate.destructive) 'destructive',
      if (candidate.expensive) 'expensive',
      if (candidate.longRunning) 'long running',
      if (candidate.requiresWorkflowState) 'requires workflow state',
    ];
    if (constraints.isNotEmpty) {
      buffer.writeln('constraints: ${constraints.join(', ')}');
    }
    if (candidate.runtimeMetadata.isNotEmpty) {
      buffer.writeln('sourceInfo: ${jsonEncode(candidate.runtimeMetadata)}');
    }
    return buffer.toString();
  }
}

class CapabilityEmbeddingIndex {
  CapabilityEmbeddingIndex({
    required SemanticTextEmbedder embedder,
    CandidateDocumentBuilder documentBuilder = const CandidateDocumentBuilder(),
  }) : _embedder = embedder,
       _documentBuilder = documentBuilder;

  final SemanticTextEmbedder _embedder;
  final CandidateDocumentBuilder _documentBuilder;
  final Map<String, _CachedCandidateEmbedding> _cache =
      <String, _CachedCandidateEmbedding>{};
  int _version = 0;

  String get modelId => _embedder.modelId;

  int get version => _version;

  void invalidate({String? reason}) {
    _cache.clear();
    _version += 1;
  }

  Future<List<IndexedCapabilityCandidate>> index(
    List<CapabilityCandidate> candidates,
  ) async {
    debugPrint(
      'OpenReef.CapabilityEmbeddingIndex: build.start candidates=${candidates.length} version=$_version model=${_embedder.modelId}',
    );
    final indexed = <IndexedCapabilityCandidate>[];
    for (final candidate in candidates) {
      final document = _documentBuilder.build(candidate);
      final documentHash = _fnv1a64(document);
      final cacheKey = '${_embedder.modelId}:${candidate.id}:$documentHash';
      final cached = _cache[cacheKey];
      late final List<double> embedding;
      if (cached != null) {
        embedding = cached.embedding;
      } else {
        try {
          embedding = await _embedder.embedDocument(document);
        } catch (error, stackTrace) {
          debugPrint(
            'OpenReef.CapabilityEmbeddingIndex: build.failed candidate=${candidate.id} ${error.runtimeType}: $error',
          );
          debugPrintStack(
            stackTrace: stackTrace,
            label: 'candidate index build',
          );
          rethrow;
        }
      }
      _cache[cacheKey] = _CachedCandidateEmbedding(embedding);
      indexed.add(
        IndexedCapabilityCandidate(
          candidate: candidate,
          document: document,
          documentHash: documentHash,
          embedding: embedding,
        ),
      );
    }
    debugPrint(
      'OpenReef.CapabilityEmbeddingIndex: build.end indexed=${indexed.length} cache=${_cache.length}',
    );
    return indexed;
  }

  String _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class SemanticCandidateRetriever {
  const SemanticCandidateRetriever({
    required CapabilityEmbeddingIndex index,
    this.topK = 16,
  }) : _index = index;

  final CapabilityEmbeddingIndex _index;
  final int topK;

  Future<List<CapabilityRetrievedCandidate>> retrieve({
    required String userMessage,
    required List<CapabilityCandidate> candidates,
  }) async {
    debugPrint(
      'OpenReef.SemanticCandidateRetriever: retrieve.start candidates=${candidates.length} topK=$topK',
    );
    late final List<double> queryEmbedding;
    try {
      queryEmbedding = await _index._embedder.embedQuery(userMessage);
    } catch (error, stackTrace) {
      debugPrint(
        'OpenReef.SemanticCandidateRetriever: query_embed.failed ${error.runtimeType}: $error',
      );
      debugPrintStack(stackTrace: stackTrace, label: 'semantic query embed');
      rethrow;
    }
    final indexed = await _index.index(candidates);
    final ranked =
        indexed
            .map(
              (entry) => CapabilityRetrievedCandidate(
                candidate: entry.candidate,
                score: _cosineSimilarity(queryEmbedding, entry.embedding),
                documentHash: entry.documentHash,
                document: entry.document,
              ),
            )
            .toList()
          ..sort((left, right) {
            final scoreCompare = right.score.compareTo(left.score);
            if (scoreCompare != 0) return scoreCompare;
            return left.candidate.id.compareTo(right.candidate.id);
          });
    final result = ranked.take(topK).toList(growable: false);
    debugPrint(
      'OpenReef.SemanticCandidateRetriever: retrieve.end top=${result.map((entry) => '${entry.candidate.id}:${entry.score.toStringAsFixed(3)}').join(', ')}',
    );
    return result;
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0;
    }
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) {
      return 0;
    }
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }
}

class CapabilityCandidateBuilder {
  const CapabilityCandidateBuilder();

  List<CapabilityCandidate> build({
    required ToolCatalog toolCatalog,
    required SkillCatalog skillCatalog,
  }) {
    return <CapabilityCandidate>[
      ...toolCatalog.listTools().map(_toolCandidate),
      ...skillCatalog.listSkills().map(_skillCandidate),
    ];
  }

  CapabilityCandidate _toolCandidate(ToolDefinition tool) {
    final isMcp = tool.source == 'mcp' || tool.category == 'mcp';
    final metadata = <String, Object?>{
      'source': tool.source ?? (isMcp ? 'mcp' : 'native'),
      ...tool.runtimeMetadata,
    };
    return CapabilityCandidate(
      id: tool.id,
      kind: isMcp ? CapabilityKind.mcpTool : CapabilityKind.nativeTool,
      displayName:
          metadata['displayName']?.toString() ?? tool.id.replaceAll('_', ' '),
      description: tool.description,
      capabilityPhrases: _stringList(metadata['capabilityPhrases']),
      usageExamples: _stringList(metadata['usageExamples']),
      tags: tool.tags,
      enabled: tool.enabled,
      requiresConfirmation: tool.requiresConfirmation,
      destructive:
          metadata['destructive'] == true || tool.tags.contains('destructive'),
      expensive: metadata['expensive'] == true,
      longRunning: metadata['longRunning'] == true,
      requiresWorkflowState: metadata['requiresWorkflowState'] == true,
      allowedModes: _allowedModesFrom(metadata['allowedModes']),
      runtimeMetadata: metadata,
      tool: tool,
    );
  }

  CapabilityCandidate _skillCandidate(SkillDefinition skill) {
    return CapabilityCandidate(
      id: skill.id,
      kind: CapabilityKind.skill,
      displayName: skill.displayName,
      description: skill.description,
      capabilityPhrases: <String>[
        ...skill.activationTerms,
        ...skill.triggerPatterns,
      ],
      usageExamples: _stringList(skill.sourceType.name),
      enabled: skill.runtimeEligible,
      allowedModes: skill.allowedModes,
      runtimeMetadata: <String, Object?>{'sourceType': skill.sourceType.name},
      skill: skill,
      requiredToolIds: skill.toolsRequired,
      incompatibleSkillIds: skill.incompatibleSkillIds,
    );
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((entry) => entry.toString()).toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return <String>[value];
    }
    return const <String>[];
  }

  Set<ExecutionMode> _allowedModesFrom(Object? value) {
    return _stringList(value)
        .map((name) => ExecutionMode.values.where((mode) => mode.name == name))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => matches.first)
        .toSet();
  }
}

class CapabilityPolicyGate {
  const CapabilityPolicyGate({
    required this.toolLimit,
    required this.skillLimit,
  });

  final int toolLimit;
  final int skillLimit;

  CapabilityGateResult apply({
    required CandidateSelectionProposal proposal,
    required List<CapabilityRetrievedCandidate> retrievedCandidates,
    required ExecutionMode executionMode,
    required ExecutionPolicy? executionPolicy,
    required int skillBudget,
  }) {
    debugPrint(
      'OpenReef.CapabilityPolicyGate: start primary=${proposal.primaryToolIds.length} fallback=${proposal.fallbackToolIds.length} skills=${proposal.selectedSkillIds.length}',
    );
    final byId = <String, CapabilityRetrievedCandidate>{
      for (final entry in retrievedCandidates) entry.candidate.id: entry,
    };
    final policyRejections = <String, String>{};
    final finalReasons = <String, String>{};
    final selectorViolations = <String>[];
    final primaryTools = <ToolDefinition>[];
    final fallbackTools = <ToolDefinition>[];
    final activeSkills = <SkillDefinition>[];
    final skillDecisions = <SkillActivationDecision>[];
    var remainingSkillBudget = skillBudget;

    for (final entry in retrievedCandidates) {
      final rejection = _policyRejection(
        candidate: entry.candidate,
        executionMode: executionMode,
        executionPolicy: executionPolicy,
      );
      if (rejection != null) {
        policyRejections[entry.candidate.id] = rejection;
      }
    }

    List<String> validIds(Iterable<String> ids, String slot) {
      final valid = <String>[];
      for (final id in ids) {
        if (!byId.containsKey(id)) {
          selectorViolations.add('$slot invented candidate id: $id');
          continue;
        }
        valid.add(id);
      }
      return valid;
    }

    bool isToolValid(CapabilityCandidate candidate, String slot) {
      final rejection = _policyRejection(
        candidate: candidate,
        executionMode: executionMode,
        executionPolicy: executionPolicy,
      );
      if (rejection != null) {
        policyRejections[candidate.id] = rejection;
        return false;
      }
      final tool = candidate.tool;
      if (tool == null) {
        policyRejections[candidate.id] = 'candidate has no executable tool';
        return false;
      }
      finalReasons[candidate.id] = '$slot selected; policy valid';
      return true;
    }

    for (final id in validIds(proposal.primaryToolIds, 'primary_tools')) {
      if (primaryTools.length >= toolLimit) {
        policyRejections[id] = 'primary tool limit exhausted';
        continue;
      }
      final candidate = byId[id]!.candidate;
      if (candidate.kind == CapabilityKind.skill) {
        policyRejections[id] = 'skill id proposed as tool';
        continue;
      }
      if (isToolValid(candidate, 'primary')) {
        primaryTools.add(candidate.tool!);
      }
    }

    for (final id in validIds(proposal.fallbackToolIds, 'fallback_tools')) {
      if (primaryTools.length + fallbackTools.length >= toolLimit) {
        policyRejections[id] = 'tool limit exhausted';
        continue;
      }
      final candidate = byId[id]!.candidate;
      if (candidate.kind == CapabilityKind.skill) {
        policyRejections[id] = 'skill id proposed as fallback tool';
        continue;
      }
      if (isToolValid(candidate, 'fallback')) {
        fallbackTools.add(candidate.tool!);
      }
    }

    final exposedToolIds = <String>{
      ...primaryTools.map((tool) => tool.id),
      ...fallbackTools.map((tool) => tool.id),
    };

    for (final id in validIds(proposal.selectedSkillIds, 'selected_skills')) {
      if (activeSkills.length >= skillLimit) {
        policyRejections[id] = 'skill limit exhausted';
        skillDecisions.add(
          _skillDecision(
            id,
            SkillDecisionStatus.skippedBudget,
            policyRejections[id]!,
          ),
        );
        continue;
      }
      final candidate = byId[id]!.candidate;
      final skill = candidate.skill;
      if (candidate.kind != CapabilityKind.skill || skill == null) {
        policyRejections[id] = 'tool id proposed as skill';
        continue;
      }
      final rejection = _policyRejection(
        candidate: candidate,
        executionMode: executionMode,
        executionPolicy: executionPolicy,
      );
      if (rejection != null) {
        policyRejections[id] = rejection;
        skillDecisions.add(
          _skillDecision(id, SkillDecisionStatus.skippedPolicy, rejection),
        );
        continue;
      }
      final incompatible = activeSkills.any(
        (active) =>
            active.incompatibleSkillIds.contains(skill.id) ||
            skill.incompatibleSkillIds.contains(active.id),
      );
      if (incompatible) {
        policyRejections[id] = 'incompatible with active skill';
        skillDecisions.add(
          _skillDecision(
            id,
            SkillDecisionStatus.skippedPolicy,
            policyRejections[id]!,
          ),
        );
        continue;
      }
      final missingTools = <String>[];
      for (final requiredToolId in skill.toolsRequired) {
        if (exposedToolIds.contains(requiredToolId)) {
          continue;
        }
        final requiredCandidate = byId[requiredToolId]?.candidate;
        if (requiredCandidate == null ||
            requiredCandidate.kind == CapabilityKind.skill ||
            !isToolValid(requiredCandidate, 'skill_dependency')) {
          missingTools.add(requiredToolId);
          continue;
        }
        if (primaryTools.length + fallbackTools.length >= toolLimit) {
          missingTools.add(requiredToolId);
          policyRejections[requiredToolId] = 'tool limit exhausted';
          continue;
        }
        fallbackTools.add(requiredCandidate.tool!);
        exposedToolIds.add(requiredToolId);
        finalReasons[requiredToolId] = 'required by selected skill ${skill.id}';
      }
      if (missingTools.isNotEmpty) {
        final reason = 'required tools unavailable: ${missingTools.join(', ')}';
        policyRejections[id] = reason;
        skillDecisions.add(
          _skillDecision(id, SkillDecisionStatus.skippedPolicy, reason),
        );
        continue;
      }
      final perSkillBudget = math.min(skill.maxTokens, remainingSkillBudget);
      if (perSkillBudget <= 0) {
        policyRejections[id] = 'skill budget exhausted';
        skillDecisions.add(
          _skillDecision(
            id,
            SkillDecisionStatus.skippedBudget,
            policyRejections[id]!,
          ),
        );
        continue;
      }
      final trimmed = ContextAssembler.trimToTokens(
        skill.content,
        perSkillBudget,
      );
      final active = skill.copyWith(
        content: trimmed,
        maxTokens: perSkillBudget,
      );
      activeSkills.add(active);
      remainingSkillBudget -= ContextAssembler.estimateTextTokens(trimmed);
      finalReasons[id] = 'selected skill; policy valid';
      skillDecisions.add(
        SkillActivationDecision(
          skillId: id,
          status: SkillDecisionStatus.activated,
          activationReason: finalReasons[id]!,
          injectionBudget: perSkillBudget,
          score: ((byId[id]?.score ?? 0) * 1000).round(),
          toolAllowanceSnapshot: exposedToolIds.toList(growable: false),
          requestedToolIds: skill.toolsRequired,
        ),
      );
    }

    final result = CapabilityGateResult(
      toolExposure: ToolExposure(
        primaryTools: List<ToolDefinition>.unmodifiable(primaryTools),
        fallbackTools: List<ToolDefinition>.unmodifiable(fallbackTools),
        excludedToolIds: policyRejections.keys.toList(growable: false),
        exclusionReasons: Map<String, String>.unmodifiable(policyRejections),
        inclusionReasons: Map<String, String>.unmodifiable(finalReasons),
      ),
      skillPlan: SkillPlan(
        activeSkills: List<SkillDefinition>.unmodifiable(activeSkills),
        decisions: List<SkillActivationDecision>.unmodifiable(skillDecisions),
        candidateDecisions: retrievedCandidates
            .where((entry) => entry.candidate.kind == CapabilityKind.skill)
            .map(
              (entry) => SkillActivationDecision(
                skillId: entry.candidate.id,
                status: SkillDecisionStatus.skippedIrrelevant,
                activationReason:
                    'semantic candidate score ${entry.score.toStringAsFixed(4)}',
                injectionBudget: 0,
                score: (entry.score * 1000).round(),
                requestedToolIds: entry.candidate.requiredToolIds,
              ),
            )
            .toList(growable: false),
        candidateSkills: retrievedCandidates
            .map((entry) => entry.candidate.skill)
            .whereType<SkillDefinition>()
            .toList(growable: false),
        requestedToolIds: retrievedCandidates
            .expand((entry) => entry.candidate.requiredToolIds)
            .toSet()
            .toList(growable: false),
        skillBudget: skillBudget,
      ),
      policyRejections: Map<String, String>.unmodifiable(policyRejections),
      finalExposureReasons: Map<String, String>.unmodifiable(finalReasons),
      selectorViolations: List<String>.unmodifiable(selectorViolations),
    );
    debugPrint(
      'OpenReef.CapabilityPolicyGate: end tools=${result.toolExposure.exposedTools.length} skills=${result.skillPlan.activeSkills.length} rejections=${result.policyRejections.length}',
    );
    return result;
  }

  SkillActivationDecision _skillDecision(
    String id,
    SkillDecisionStatus status,
    String reason,
  ) {
    return SkillActivationDecision(
      skillId: id,
      status: status,
      activationReason: reason,
      injectionBudget: 0,
    );
  }

  String? _policyRejection({
    required CapabilityCandidate candidate,
    required ExecutionMode executionMode,
    required ExecutionPolicy? executionPolicy,
  }) {
    if (!candidate.enabled) {
      return 'disabled or runtime-ineligible';
    }
    if (executionPolicy != null &&
        !executionPolicy.allowToolUse &&
        candidate.kind != CapabilityKind.skill) {
      return 'tool use disabled by execution policy';
    }
    if (candidate.allowedModes.isNotEmpty &&
        !candidate.allowedModes.contains(executionMode)) {
      return 'mode ${executionMode.name} not allowed';
    }
    if (candidate.requiresWorkflowState &&
        executionMode != ExecutionMode.workflowContinuation) {
      return 'workflow state required';
    }
    if (candidate.kind == CapabilityKind.mcpTool) {
      final state = candidate.runtimeMetadata;
      final active = state['mcpActive'];
      final trusted = state['mcpTrusted'];
      final hasSecret = state['mcpHasSecret'];
      if (active != true || trusted != true || hasSecret != true) {
        if (active == null || trusted == null || hasSecret == null) {
          return 'unknown_mcp_runtime_state';
        }
        if (active != true) return 'mcp_disconnected';
        if (trusted != true) return 'mcp_untrusted';
        if (hasSecret != true) return 'mcp_auth_missing';
      }
    }
    return null;
  }
}

class CapabilityGateResult {
  const CapabilityGateResult({
    required this.toolExposure,
    required this.skillPlan,
    this.policyRejections = const <String, String>{},
    this.finalExposureReasons = const <String, String>{},
    this.selectorViolations = const <String>[],
  });

  final ToolExposure toolExposure;
  final SkillPlan skillPlan;
  final Map<String, String> policyRejections;
  final Map<String, String> finalExposureReasons;
  final List<String> selectorViolations;
}

class IndexedCapabilityCandidate {
  const IndexedCapabilityCandidate({
    required this.candidate,
    required this.document,
    required this.documentHash,
    required this.embedding,
  });

  final CapabilityCandidate candidate;
  final String document;
  final String documentHash;
  final List<double> embedding;
}

class _CachedCandidateEmbedding {
  const _CachedCandidateEmbedding(this.embedding);

  final List<double> embedding;
}
