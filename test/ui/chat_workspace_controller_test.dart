import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/chat_workspace_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'controller derives title from first user message and persists it',
    () async {
      final repository = await _createRepository();
      addTearDown(repository.close);

      final controller = ChatWorkspaceController(
        prototypeSession: MockChatSession(),
        repository: repository,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.sendMessage('This is the first chat title candidate');

      expect(
        controller.activeSession?.record.title,
        'This is the first chat title candida...',
      );
      final sessions = await repository.fetchSessions();
      expect(sessions.single.title, 'This is the first chat title candida...');
    },
  );

  test(
    'controller keeps transcripts isolated when switching sessions',
    () async {
      final repository = await _createRepository();
      addTearDown(repository.close);

      final controller = ChatWorkspaceController(
        prototypeSession: MockChatSession(),
        repository: repository,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      final firstId = controller.activeSession!.record.id;
      await controller.sendMessage('First session prompt');

      await controller.createNewSession();
      final secondId = controller.activeSession!.record.id;
      await controller.sendMessage('Second session prompt');

      await controller.switchToSession(firstId);
      expect(
        controller.activeSession!.chatSession.messages
            .map((message) => message.text)
            .join(' '),
        contains('First session prompt'),
      );
      expect(
        controller.activeSession!.chatSession.messages
            .map((message) => message.text)
            .join(' '),
        isNot(contains('Second session prompt')),
      );

      await controller.switchToSession(secondId);
      expect(
        controller.activeSession!.chatSession.messages
            .map((message) => message.text)
            .join(' '),
        contains('Second session prompt'),
      );
    },
  );

  test('controller persists active session changes before emitting', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    final prototype = _ExternallyMutableSession();
    final controller = ChatWorkspaceController(
      prototypeSession: prototype,
      repository: repository,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    final sessionId = controller.activeSession!.record.id;
    var observedPersistedFinal = false;
    controller.addListener(() async {
      final messages = await repository.fetchMessages(sessionId);
      observedPersistedFinal = messages.any(
        (message) =>
            message.sender == ChatMessageSender.assistant &&
            message.text == 'Runtime visible final.' &&
            !message.isStreaming,
      );
    });

    (controller.activeSession!.chatSession as _ExternallyMutableSession)
        .appendAssistantFinal('Runtime visible final.');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(observedPersistedFinal, isTrue);
  });

  test('controller persists streaming messages honestly', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    final controller = ChatWorkspaceController(
      prototypeSession: _ExternallyMutableSession(),
      repository: repository,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    final sessionId = controller.activeSession!.record.id;
    final session =
        controller.activeSession!.chatSession as _ExternallyMutableSession;

    session.appendAssistantStreaming('Partial');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    var messages = await repository.fetchMessages(sessionId);
    expect(messages.last.text, 'Partial');
    expect(messages.last.isStreaming, isTrue);

    session.finalizeAssistant('Partial final');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    messages = await repository.fetchMessages(sessionId);
    expect(messages.last.text, 'Partial final');
    expect(messages.last.isStreaming, isFalse);
  });
}

Future<ChatSessionRepository> _createRepository() async {
  final directory = await Directory.systemTemp.createTemp(
    'workspace-controller-',
  );
  final repository = ChatSessionRepository(
    path: '${directory.path}${Platform.pathSeparator}chat.sqlite',
    databaseFactory: databaseFactoryFfi,
  );
  await repository.initialize();
  return repository;
}

class _ExternallyMutableSession extends ChangeNotifier
    implements ChatSessionPort, ChatSessionFactory {
  _ExternallyMutableSession({
    this.sessionId = 'external-main',
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) : _messages = List<ChatTranscriptMessage>.from(initialMessages);

  final String sessionId;
  final List<ChatTranscriptMessage> _messages;

  @override
  List<SubAgentActivity> get activities => const <SubAgentActivity>[];

  @override
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

  @override
  ChatSessionStatus get status => ChatSessionStatus.completed;

  void appendAssistantFinal(String text) {
    _messages.add(
      ChatTranscriptMessage(
        id: 'external-${_messages.length}',
        sender: ChatMessageSender.assistant,
        text: text,
        timestamp: DateTime(2026, 4, 12, 10),
      ),
    );
    notifyListeners();
  }

  void appendAssistantStreaming(String text) {
    _messages.add(
      ChatTranscriptMessage(
        id: 'streaming',
        sender: ChatMessageSender.assistant,
        text: text,
        timestamp: DateTime(2026, 4, 12, 10),
        isStreaming: true,
      ),
    );
    notifyListeners();
  }

  void finalizeAssistant(String text) {
    final index = _messages.indexWhere((message) => message.id == 'streaming');
    _messages[index] = _messages[index].copyWith(
      text: text,
      isStreaming: false,
    );
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String message) async {}

  @override
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) {
    return _ExternallyMutableSession(
      sessionId: sessionId,
      initialMessages: initialMessages,
    );
  }
}
