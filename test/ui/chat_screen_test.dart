import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/screens/chat_screen.dart';

void main() {
  testWidgets('chat screen renders pending approval with approve and reject actions', (
    tester,
  ) async {
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
  });
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
}
