import 'package:flutter/material.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/ui/app_shell.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/screens/model_download_screen.dart';
import 'package:openreef/voice/wake_word_controller.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';

class OpenReefApp extends StatelessWidget {
  const OpenReefApp({
    required this.settingsController,
    required this.chatSession,
    this.wakeWordController,
    required this.modelDownloadController,
    required this.skillRegistryController,
    required this.mcpConnectionsController,
    required this.modelReady,
    required this.onModelReady,
    this.embeddingModelManager,
    this.chatSessionRepository,
    super.key,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;
  final WakeWordController? wakeWordController;
  final ModelDownloadController modelDownloadController;
  final SkillRegistryController skillRegistryController;
  final McpConnectionsController mcpConnectionsController;
  final bool modelReady;
  final Future<void> Function() onModelReady;
  final EmbeddingModelManager? embeddingModelManager;
  final ChatSessionRepository? chatSessionRepository;

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
                  wakeWordController: wakeWordController,
                  modelDownloadController: modelDownloadController,
                  skillRegistryController: skillRegistryController,
                  mcpConnectionsController: mcpConnectionsController,
                  onModelReady: onModelReady,
                  embeddingModelManager: embeddingModelManager,
                  chatSessionRepository: chatSessionRepository,
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
