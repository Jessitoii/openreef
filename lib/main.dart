import 'package:flutter/material.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';
import 'package:openreef/ui/openreef_app.dart';

void main() {
  runApp(
    MyApp(
      settingsController: SettingsController(),
      chatSession: MockChatSession(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    required this.settingsController,
    required this.chatSession,
    super.key,
  });

  final SettingsController settingsController;
  final MockChatSession chatSession;

  @override
  Widget build(BuildContext context) {
    return OpenReefApp(
      settingsController: settingsController,
      chatSession: chatSession,
    );
  }
}
