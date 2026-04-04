import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/ui/chat_workspace_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('controller derives title from first user message and persists it', () async {
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

    final reloadedRepository = ChatSessionRepository(
      path: repositoryPath(repository),
      databaseFactory: databaseFactoryFfi,
    );
    await reloadedRepository.initialize();
    addTearDown(reloadedRepository.close);
    final sessions = await reloadedRepository.fetchSessions();
    expect(
      sessions.single.title,
      'This is the first chat title candida...',
    );
  });

  test('controller keeps transcripts isolated when switching sessions', () async {
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
  });
}

Future<ChatSessionRepository> _createRepository() async {
  final directory = await Directory.systemTemp.createTemp('workspace-controller-');
  final repository = ChatSessionRepository(
    path: '${directory.path}${Platform.pathSeparator}chat.sqlite',
    databaseFactory: databaseFactoryFfi,
  );
  await repository.initialize();
  return repository;
}

String repositoryPath(ChatSessionRepository repository) {
  return (repository as dynamic)._path as String;
}
