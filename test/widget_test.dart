import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/main.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';

void main() {
  testWidgets('app boots into chat screen', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(_buildApp());

    expect(find.text('> OPENREEF_TERMINAL'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('sending a message shows user text and mock reply', (
    tester,
  ) async {
    _setLargeSurface(tester);
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
    await tester.pump(const Duration(milliseconds: 2300));
    await sendFuture;
    await tester.pump();

    expect(find.textContaining('Check theme status'), findsOneWidget);
    expect(find.textContaining('Theme changes are live.'), findsOneWidget);
  });

  testWidgets('sub-agent activity blocks can expand during execution', (
    tester,
  ) async {
    _setLargeSurface(tester);
    final settingsController = SettingsController();
    final chatSession = MockChatSession();
    await tester.pumpWidget(
      MyApp(
        settingsController: settingsController,
        chatSession: chatSession,
      ),
    );

    final sendFuture = chatSession.sendMessage('Check voice pipeline');
    await tester.pump();

    expect(find.text('planner.daemon'), findsOneWidget);
    expect(find.textContaining('Input classified as offline chat request.'), findsNothing);

    await tester.tap(find.byKey(const Key('activity-planner')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Input classified as offline chat request.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2300));
    await sendFuture;
  });

  testWidgets('theme mode can be changed from settings', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });

  testWidgets('voice settings controls update visible state', (tester) async {
    _setLargeSurface(tester);
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

void _setLargeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
