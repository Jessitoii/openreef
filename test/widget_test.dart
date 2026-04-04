import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/main.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';

void main() {
  testWidgets('app boots into chat screen', (tester) async {
    await tester.pumpWidget(_buildApp());

    expect(find.text('> OPENREEF_TERMINAL'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('sending a message shows user text and mock reply', (
    tester,
  ) async {
    final settingsController = SettingsController();
    final chatSession = MockChatSession();
    await tester.pumpWidget(
      MyApp(
        settingsController: settingsController,
        chatSession: chatSession,
      ),
    );

    final sendFuture = chatSession.sendMessage('Check theme status');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    await sendFuture;

    expect(find.textContaining('Check theme status'), findsOneWidget);
    expect(find.textContaining('Theme changes are live.'), findsOneWidget);
  });

  testWidgets('theme mode can be changed from settings', (tester) async {
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });

  testWidgets('voice settings controls update visible state', (tester) async {
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wake-word-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Wake Sensitivity 0.7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts-engine-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kokoro').last);
    await tester.pumpAndSettle();

    expect(find.text('Kokoro'), findsOneWidget);
  });
}

Widget _buildApp() {
  return MyApp(
    settingsController: SettingsController(),
    chatSession: MockChatSession(),
  );
}
