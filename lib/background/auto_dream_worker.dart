import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/background/auto_dream_run_result.dart';
import 'package:openreef/memory/auto_dream_session_state.dart';
import 'package:openreef/memory/chat_message_record.dart';
import 'package:openreef/memory/chat_session_record.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/ui/chat_session_port.dart';

/// Coordinates nightly background memory consolidation scheduling.
///
/// This stub only exposes scheduling hooks so the Android WorkManager
/// integration can be wired without touching agent or memory logic.
class AutoDreamWorker {
  AutoDreamWorker({
    OptionalMethodChannel? methodChannel,
    ChatSessionRepository? chatSessionRepository,
    MemoryStorage? memoryStorage,
    MemoryIndex? memoryIndex,
    DateTime Function()? now,
  }) : _methodChannel =
          methodChannel ?? const OptionalMethodChannel(methodChannelName),
       _chatSessionRepository = chatSessionRepository,
       _memoryStorage = memoryStorage,
       _memoryIndex = memoryIndex,
       _now = now;

  static const String workName = 'openreef.auto_dream.nightly';
  static const String methodChannelName = 'openreef/background_channel';
  static const Duration episodicTtl = Duration(days: 30);
  static const int _maxSnippetLength = 96;
  static const int _maxBulletCount = 4;

  static const String _scheduleMethod = 'scheduleNightlyAutoDream';
  static const String _cancelMethod = 'cancelNightlyAutoDream';
  static bool _isRunning = false;

  final OptionalMethodChannel _methodChannel;
  final ChatSessionRepository? _chatSessionRepository;
  final MemoryStorage? _memoryStorage;
  final MemoryIndex? _memoryIndex;
  final DateTime Function()? _now;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  DateTime _currentTime() => (_now ?? DateTime.now).call().toUtc();

  Future<bool> scheduleNightly() async {
    if (!isSupported) {
      return false;
    }

    final scheduled = await _methodChannel.invokeMethod<bool>(
      _scheduleMethod,
      <String, Object?>{'workName': workName},
    );
    return scheduled ?? false;
  }

  Future<bool> cancelNightly() async {
    if (!isSupported) {
      return false;
    }

    final cancelled = await _methodChannel.invokeMethod<bool>(
      _cancelMethod,
      <String, Object?>{'workName': workName},
    );
    return cancelled ?? false;
  }

  Future<AutoDreamRunResult> runConsolidation() async {
    final startedAt = _currentTime();
    if (_isRunning) {
      return AutoDreamRunResult.skipped(at: startedAt);
    }

    final chatSessionRepository = _chatSessionRepository;
    final memoryStorage = _memoryStorage;
    final memoryIndex = _memoryIndex;
    if (chatSessionRepository == null ||
        memoryStorage == null ||
        memoryIndex == null) {
      throw StateError(
        'AutoDreamWorker requires chatSessionRepository, memoryStorage, and '
        'memoryIndex to run consolidation.',
      );
    }

    _isRunning = true;
    try {
      final sessions = await chatSessionRepository.fetchSessions();
      final memoryKeys = <String>[];
      var sessionsSummarized = 0;

      for (final session in sessions) {
        final summary = await _buildSessionSummary(
          session,
          chatSessionRepository: chatSessionRepository,
        );
        if (summary == null) {
          continue;
        }

        final createdAt = summary.messages.last.timestamp.toUtc();
        final memoryKey = _buildMemoryKey(
          sessionId: session.id,
          lastPosition: summary.lastPosition,
          occurredAt: createdAt,
        );
        await memoryStorage.saveRecord(
          MemoryRecord(
            store: MemoryStoreKind.episodic,
            key: memoryKey,
            content: summary.content,
            category: 'last_session',
            importance: 3,
            createdAt: createdAt,
            expiresAt: createdAt.add(episodicTtl),
            metadata: <String, Object?>{
              'session_id': session.id,
              'session_title': session.title,
              'source_message_ids': summary.messages
                  .map((message) => message.id)
                  .toList(),
              'source_positions': summary.messages
                  .map((message) => message.position)
                  .toList(),
              'window_started_at': summary.messages.first.timestamp
                  .toUtc()
                  .toIso8601String(),
              'window_finished_at': createdAt.toIso8601String(),
            },
          ),
        );
        await chatSessionRepository.saveAutoDreamState(
          AutoDreamSessionState(
            sessionId: session.id,
            lastSummarizedPosition: summary.lastPosition,
            lastSummarizedAt: startedAt,
            lastMemoryKey: memoryKey,
          ),
        );
        await memoryIndex.updateSessionPointer(memoryKey: memoryKey);
        memoryKeys.add(memoryKey);
        sessionsSummarized++;
      }

      return AutoDreamRunResult(
        status: AutoDreamRunStatus.completed,
        startedAt: startedAt,
        finishedAt: _currentTime(),
        sessionsScanned: sessions.length,
        sessionsSummarized: sessionsSummarized,
        memoriesWritten: memoryKeys.length,
        memoryKeys: memoryKeys,
      );
    } finally {
      _isRunning = false;
    }
  }

  Future<_SessionSummary?> _buildSessionSummary(
    ChatSessionRecord session, {
    required ChatSessionRepository chatSessionRepository,
  }) async {
    final messages = await chatSessionRepository.fetchUnsummarizedMessages(
      session.id,
    );
    final stableMessages = messages
        .where((message) => _isRelevantMessage(message))
        .toList();

    if (stableMessages.isEmpty) {
      return null;
    }

    final content = _formatSummary(session: session, messages: stableMessages);
    if (content == null) {
      return null;
    }

    return _SessionSummary(
      content: content,
      messages: stableMessages,
      lastPosition: stableMessages.last.position,
    );
  }

  bool _isRelevantMessage(ChatMessageRecord message) {
    if (message.isStreaming || message.sender == ChatMessageSender.system) {
      return false;
    }

    final normalized = _normalizeText(message.text);
    return normalized.isNotEmpty && normalized.length > 2;
  }

  String? _formatSummary({
    required ChatSessionRecord session,
    required List<ChatMessageRecord> messages,
  }) {
    final firstAt = messages.first.timestamp.toUtc();
    final lastAt = messages.last.timestamp.toUtc();
    final bullets = <String>[
      _buildTopicLine(session, messages),
      ..._buildPointLines(messages),
      ..._buildPendingLine(messages),
    ].whereType<String>().take(_maxBulletCount).toList();

    if (bullets.isEmpty) {
      return null;
    }

    final buffer = StringBuffer(
      '[EPISODIC MEMORY] ${session.title} | '
      '${firstAt.toIso8601String()} -> ${lastAt.toIso8601String()}\n',
    );
    for (final bullet in bullets) {
      buffer.writeln('- $bullet');
    }
    return buffer.toString().trimRight();
  }

  String _buildTopicLine(
    ChatSessionRecord session,
    List<ChatMessageRecord> messages,
  ) {
    final firstUser = messages.firstWhere(
      (message) => message.sender == ChatMessageSender.user,
      orElse: () => messages.first,
    );
    final snippet = _truncateSnippet(_normalizeText(firstUser.text));
    if (snippet.isEmpty) {
      return 'Topic: ${session.title}';
    }
    return 'Topic: $snippet';
  }

  List<String> _buildPointLines(List<ChatMessageRecord> messages) {
    final points = <String>[];
    final seen = <String>{};

    for (final message in messages) {
      final normalized = _truncateSnippet(_normalizeText(message.text));
      if (normalized.isEmpty || !seen.add('${message.sender.name}:$normalized')) {
        continue;
      }

      final prefix = switch (message.sender) {
        ChatMessageSender.user => 'User',
        ChatMessageSender.assistant => 'Assistant',
        ChatMessageSender.system => 'System',
      };
      points.add('$prefix: $normalized');
      if (points.length >= _maxBulletCount - 1) {
        break;
      }
    }

    return points;
  }

  List<String> _buildPendingLine(List<ChatMessageRecord> messages) {
    for (final message in messages.reversed) {
      if (message.sender != ChatMessageSender.user) {
        continue;
      }

      final normalized = _truncateSnippet(_normalizeText(message.text));
      if (normalized.isEmpty) {
        continue;
      }

      if (message.text.trim().endsWith('?') || _looksActionable(normalized)) {
        return <String>['Pending: $normalized'];
      }
    }

    return const <String>[];
  }

  bool _looksActionable(String value) {
    const actionTerms = <String>[
      'need',
      'should',
      'follow up',
      'remind',
      'check',
      'plan',
      'todo',
      'next',
    ];

    final lower = value.toLowerCase();
    return actionTerms.any(lower.contains);
  }

  String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncateSnippet(String value) {
    if (value.length <= _maxSnippetLength) {
      return value;
    }
    return '${value.substring(0, _maxSnippetLength - 3).trimRight()}...';
  }

  String _buildMemoryKey({
    required String sessionId,
    required int lastPosition,
    required DateTime occurredAt,
  }) {
    final compactSessionId = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final stamp =
        '${occurredAt.year.toString().padLeft(4, '0')}'
        '${occurredAt.month.toString().padLeft(2, '0')}'
        '${occurredAt.day.toString().padLeft(2, '0')}'
        '_${occurredAt.hour.toString().padLeft(2, '0')}'
        '${occurredAt.minute.toString().padLeft(2, '0')}'
        '${occurredAt.second.toString().padLeft(2, '0')}';
    return 'session_${compactSessionId}_${stamp}_$lastPosition';
  }
}

class _SessionSummary {
  const _SessionSummary({
    required this.content,
    required this.messages,
    required this.lastPosition,
  });

  final String content;
  final List<ChatMessageRecord> messages;
  final int lastPosition;
}
