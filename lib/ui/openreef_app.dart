import 'package:flutter/material.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/app_shell.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';

class OpenReefApp extends StatelessWidget {
  const OpenReefApp({
    required this.settingsController,
    required this.chatSession,
    super.key,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, child) {
        final settings = settingsController.settings;
        return MaterialApp(
          title: 'OpenReef',
          themeMode: mapThemeMode(settings.themeMode),
          theme: buildReefTheme(Brightness.light),
          darkTheme: buildReefTheme(Brightness.dark),
          home: AppShell(
            settingsController: settingsController,
            chatSession: chatSession,
          ),
        );
      },
    );
  }
}
