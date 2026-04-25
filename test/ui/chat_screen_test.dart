import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/ui/chat/composer_models.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/screens/chat_screen.dart';

void main() {
  testWidgets('text-only send still uses onSendMessage', (tester) async {
    final sentMessages = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (message) async {
              sentMessages.add(message);
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'hello reef',
    );
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sentMessages, <String>['hello reef']);
  });

  testWidgets('attachment button opens disabled attachment menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-attachment-sheet')), findsOneWidget);
    expect(find.byKey(const Key('attachment-row-image')), findsOneWidget);
    expect(find.byKey(const Key('attachment-row-document')), findsOneWidget);
    expect(find.byKey(const Key('attachment-row-audio')), findsOneWidget);
    expect(find.text('Current model only supports text'), findsNWidgets(3));
  });

  testWidgets('disabled attachment rows do not create chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('attachment-row-image')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attachment-chip-image-1')), findsNothing);
  });

  testWidgets('attachment chips render and can be removed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
            initialComposerAttachments: const <ComposerAttachmentDescriptor>[
              ComposerAttachmentDescriptor(
                id: 'image-1',
                type: ComposerAttachmentType.image,
                displayName: 'reef-photo.jpg',
                sizeBytes: 2048,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('attachment-chip-image-1')), findsOneWidget);
    expect(find.text('reef-photo.jpg (2.0 KB)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove-attachment-image-1')));
    await tester.pump();

    expect(find.byKey(const Key('attachment-chip-image-1')), findsNothing);
  });

  testWidgets(
    'chat screen renders pending approval with approve and reject actions',
    (tester) async {
      final session = _FakeChatSession(
        pendingApproval: const PendingToolApproval(
          toolCallId: 'call-1',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.75},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScreen(
              chatSession: session,
              sessionTitle: 'Test Session',
              lastModified: DateTime(2026, 4, 6, 12),
              onSendMessage: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Approval required'), findsOneWidget);
      expect(find.textContaining('volume_set'), findsOneWidget);
      expect(find.byKey(const Key('approval-approve-button')), findsOneWidget);
      expect(find.byKey(const Key('approval-reject-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('approval-approve-button')));
      expect(session.approveCalls, 1);

      await tester.tap(find.byKey(const Key('approval-reject-button')));
      expect(session.rejectCalls, 1);
    },
  );
}

class _FakeChatSession extends ChangeNotifier
    implements ChatSessionPort, ApprovalCapableChatSession {
  _FakeChatSession({this.pendingApproval});

  @override
  final PendingToolApproval? pendingApproval;

  var approveCalls = 0;
  var rejectCalls = 0;

  @override
  List<SubAgentActivity> get activities => const <SubAgentActivity>[];

  @override
  List<ChatTranscriptMessage> get messages => const <ChatTranscriptMessage>[];

  @override
  ChatSessionStatus get status => ChatSessionStatus.idle;

  @override
  void approvePendingApproval() {
    approveCalls += 1;
  }

  @override
  void rejectPendingApproval() {
    rejectCalls += 1;
  }

  @override
  Future<void> sendMessage(String message) async {}

  @override
  Future<void> sendComposerSubmission(ComposerSubmission submission) async {}
}
