import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/auto_dream_session_state.dart';
import 'package:openreef/memory/chat_session_record.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('repository saves and loads session transcripts', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);

    final session = ChatSessionRecord(
      id: 'session-a',
      title: 'First Chat',
      lastModified: DateTime(2026, 4, 5, 12, 30),
    );
    final messages = <ChatTranscriptMessage>[
      ChatTranscriptMessage(
        id: 'msg-1',
        sender: ChatMessageSender.system,
        text: 'OPENREEF READY',
        timestamp: DateTime(2026, 4, 5, 12, 30),
      ),
      ChatTranscriptMessage(
        id: 'msg-2',
        sender: ChatMessageSender.user,
        text: 'Persist this chat',
        timestamp: DateTime(2026, 4, 5, 12, 31),
      ),
      ChatTranscriptMessage(
        id: 'msg-3',
        sender: ChatMessageSender.assistant,
        text: 'Transcript restored.',
        timestamp: DateTime(2026, 4, 5, 12, 32),
      ),
    ];

    await repository.saveSession(session: session, messages: messages);

    final loadedSessions = await repository.fetchSessions();
    final loadedMessages = await repository.fetchMessages('session-a');

    expect(loadedSessions, hasLength(1));
    expect(loadedSessions.single.title, 'First Chat');
    expect(loadedMessages.map((message) => message.text).toList(), <String>[
      'OPENREEF READY',
      'Persist this chat',
      'Transcript restored.',
    ]);
  });

  test('repository sorts recent chats by last modified descending', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);

    await repository.saveSession(
      session: ChatSessionRecord(
        id: 'older',
        title: 'Older Chat',
        lastModified: DateTime(2026, 4, 4, 20, 00),
      ),
      messages: const <ChatTranscriptMessage>[],
    );
    await repository.saveSession(
      session: ChatSessionRecord(
        id: 'newer',
        title: 'Newer Chat',
        lastModified: DateTime(2026, 4, 5, 20, 00),
      ),
      messages: const <ChatTranscriptMessage>[],
    );

    final sessions = await repository.fetchSessions();

    expect(sessions.map((session) => session.id).toList(), <String>[
      'newer',
      'older',
    ]);
  });

  test('fetches unsummarized messages after the saved checkpoint', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);

    await repository.saveSession(
      session: ChatSessionRecord(
        id: 'session-a',
        title: 'Checkpoint Chat',
        lastModified: DateTime(2026, 4, 5, 20, 00),
      ),
      messages: <ChatTranscriptMessage>[
        ChatTranscriptMessage(
          id: 'msg-1',
          sender: ChatMessageSender.user,
          text: 'First point',
          timestamp: DateTime(2026, 4, 5, 20, 00),
        ),
        ChatTranscriptMessage(
          id: 'msg-2',
          sender: ChatMessageSender.assistant,
          text: 'Second point',
          timestamp: DateTime(2026, 4, 5, 20, 01),
        ),
        ChatTranscriptMessage(
          id: 'msg-3',
          sender: ChatMessageSender.user,
          text: 'Third point',
          timestamp: DateTime(2026, 4, 5, 20, 02),
        ),
        ChatTranscriptMessage(
          id: 'msg-4',
          sender: ChatMessageSender.assistant,
          text: 'Streaming draft',
          timestamp: DateTime(2026, 4, 5, 20, 03),
          isStreaming: true,
        ),
      ],
    );
    await repository.saveAutoDreamState(
      AutoDreamSessionState(
        sessionId: 'session-a',
        lastSummarizedPosition: 1,
        lastSummarizedAt: DateTime.utc(2026, 4, 5, 20, 05),
        lastMemoryKey: 'session_existing',
      ),
    );

    final unsummarized = await repository.fetchUnsummarizedMessages('session-a');
    final savedState = await repository.fetchAutoDreamState('session-a');

    expect(unsummarized.map((message) => message.id).toList(), <String>['msg-3']);
    expect(savedState?.lastMemoryKey, 'session_existing');
  });
}

Future<ChatSessionRepository> _createRepository() async {
  final directory = await Directory.systemTemp.createTemp('chat-repository-');
  final repository = ChatSessionRepository(
    path: '${directory.path}${Platform.pathSeparator}chat.sqlite',
    databaseFactory: databaseFactoryFfi,
  );
  await repository.initialize();
  return repository;
}
