import 'package:flutter/material.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/app_shell.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/screens/model_download_screen.dart';

class OpenReefApp extends StatelessWidget {
  const OpenReefApp({
    required this.settingsController,
    required this.chatSession,
    required this.modelDownloadController,
    required this.modelReady,
    required this.onModelReady,
    super.key,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;
  final ModelDownloadController modelDownloadController;
  final bool modelReady;
  final Future<void> Function() onModelReady;

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
          home: modelReady
              ? AppShell(
                  settingsController: settingsController,
                  chatSession: chatSession,
                )
              : ModelDownloadScreen(
                  controller: modelDownloadController,
                  onModelReady: onModelReady,
                ),
        );
      },
    );
  }
}
