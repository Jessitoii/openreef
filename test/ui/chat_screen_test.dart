import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
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
    expect(
      find.byKey(const Key('attachment-row-voice-message')),
      findsOneWidget,
    );
    expect(find.text('Current model only supports text'), findsNWidgets(3));
    expect(find.text('Speech-to-text is not available yet'), findsOneWidget);
  });

  testWidgets(
    'image disabled for text-only model when runtime supports image',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScreen(
              chatSession: _FakeChatSession(),
              sessionTitle: 'Test Session',
              lastModified: DateTime(2026, 4, 6, 12),
              onSendMessage: (_) async {},
              capabilityResolver: _resolver(
                modelCapabilities: ModelInputCapabilities.textOnly,
                runtimeSupport: const _RuntimeSupport(image: true),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('chat-attachment-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Switch to a model with image support to attach photos'),
        findsOneWidget,
      );
    },
  );

  testWidgets('audio disabled for model without audio support', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
            capabilityResolver: _resolver(
              modelCapabilities: const ModelInputCapabilities(
                supportsImageInput: true,
              ),
              runtimeSupport: const _RuntimeSupport(audio: true),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Switch to a model with audio support to attach voice files'),
      findsOneWidget,
    );
  });

  testWidgets('document disabled when preprocessor is unavailable', (
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
            capabilityResolver: _resolver(
              modelCapabilities: const ModelInputCapabilities(
                supportsDocumentInput: true,
              ),
              runtimeSupport: const _RuntimeSupport(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(find.text('Document attachments are not wired yet'), findsOneWidget);
  });

  testWidgets('available image pick action creates a removable chip', (
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
            capabilityResolver: _resolver(
              modelCapabilities: const ModelInputCapabilities(
                supportsImageInput: true,
              ),
              runtimeSupport: const _RuntimeSupport(image: true),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-row-image')));
    await tester.pumpAndSettle();

    expect(find.text('Selected image'), findsOneWidget);
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
        pendingApproval: PendingToolApproval(
          toolCallId: 'call-1',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.75},
          createdAt: DateTime.utc(2026, 4, 6, 12),
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

  testWidgets('chat screen renders streaming assistant bubble', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(
              messages: <ChatTranscriptMessage>[
                ChatTranscriptMessage(
                  id: 'assistant-stream',
                  sender: ChatMessageSender.assistant,
                  text: 'Writing the plan',
                  timestamp: DateTime(2026, 4, 6, 12),
                  isStreaming: true,
                ),
              ],
            ),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('streaming-assistant-bubble')), findsOneWidget);
    expect(find.text('Writing the plan'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
  });

  testWidgets('chat screen renders execution trace cards without raw JSON', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            chatSession: _FakeChatSession(
              executionTrace: ExecutionTrace(
                requestId: 'request-1',
                status: ExecutionTraceStatus.running,
                steps: <ExecutionTraceStep>[
                  ExecutionTraceStep(
                    id: 'tool-1',
                    kind: ExecutionStepKind.tool,
                    title: 'Battery Info',
                    status: ExecutionStepStatus.running,
                    summary: 'Running battery_info',
                    details: const <ExecutionTraceDetail>[
                      ExecutionTraceDetail(name: 'scope', value: 'current'),
                    ],
                    timestamp: DateTime(2026, 4, 6, 12),
                  ),
                  ExecutionTraceStep(
                    id: 'approval-1',
                    kind: ExecutionStepKind.approval,
                    title: 'Sms Send',
                    status: ExecutionStepStatus.approvalRequired,
                    summary: 'Waiting for approval',
                    details: const <ExecutionTraceDetail>[
                      ExecutionTraceDetail(name: 'message', value: '11 chars'),
                    ],
                    timestamp: DateTime(2026, 4, 6, 12),
                  ),
                ],
              ),
            ),
            sessionTitle: 'Test Session',
            lastModified: DateTime(2026, 4, 6, 12),
            onSendMessage: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('execution-trace-block')), findsOneWidget);
    expect(find.byKey(const Key('tool-step-tool-1')), findsOneWidget);
    expect(find.byKey(const Key('approval-step-approval-1')), findsOneWidget);
    expect(find.text('Battery Info'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
  });
}

ComposerCapabilityResolver _resolver({
  required ModelInputCapabilities modelCapabilities,
  required AttachmentRuntimeSupport runtimeSupport,
}) {
  return ComposerCapabilityResolver(
    modelCapabilityProvider: StaticActiveModelCapabilityProvider(
      modelCapabilities,
    ),
    runtimeSupport: runtimeSupport,
  );
}

class _RuntimeSupport implements AttachmentRuntimeSupport {
  const _RuntimeSupport({this.image = false, this.audio = false});

  final bool image;
  final bool audio;

  @override
  bool get textRuntimeAvailable => true;

  @override
  bool get imagePreprocessingAvailable => image;

  @override
  bool get audioPreprocessingAvailable => audio;

  @override
  bool get documentPreprocessingAvailable => false;

  @override
  bool get speechToTextAvailable => false;
}

class _FakeChatSession extends ChangeNotifier
    implements
        ChatSessionPort,
        ApprovalCapableChatSession,
        ExecutionTraceCapableChatSession {
  _FakeChatSession({
    this.pendingApproval,
    this.executionTrace,
    List<ChatTranscriptMessage> messages = const <ChatTranscriptMessage>[],
  }) : _messages = messages;

  @override
  final PendingToolApproval? pendingApproval;

  @override
  final ExecutionTrace? executionTrace;

  final List<ChatTranscriptMessage> _messages;
  var approveCalls = 0;
  var rejectCalls = 0;

  @override
  List<SubAgentActivity> get activities => const <SubAgentActivity>[];

  @override
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

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
