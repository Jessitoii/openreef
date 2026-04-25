import 'package:flutter/material.dart';
import 'package:openreef/memory/chat_session_record.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/chat_workspace_controller.dart';
import 'package:openreef/ui/screens/automation_screen.dart';
import 'package:openreef/ui/memory_management_controller.dart';
import 'package:openreef/ui/screens/chat_screen.dart';
import 'package:openreef/ui/screens/mcp_connections_screen.dart';
import 'package:openreef/ui/screens/memory_screen.dart';
import 'package:openreef/ui/screens/model_download_screen.dart';
import 'package:openreef/ui/screens/settings_screen.dart';
import 'package:openreef/ui/screens/skills_screen.dart';
import 'package:openreef/voice/wake_word_controller.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.settingsController,
    required this.chatSession,
    this.wakeWordController,
    required this.modelDownloadController,
    required this.skillRegistryController,
    this.automationController,
    required this.mcpConnectionsController,
    required this.onModelReady,
    this.embeddingModelManager,
    this.chatSessionRepository,
    required this.memoryStorage,
    required this.memoryIndex,
    super.key,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;
  final WakeWordController? wakeWordController;
  final ModelDownloadController modelDownloadController;
  final SkillRegistryController skillRegistryController;
  final AutomationController? automationController;
  final McpConnectionsController mcpConnectionsController;
  final Future<void> Function() onModelReady;
  final EmbeddingModelManager? embeddingModelManager;
  final ChatSessionRepository? chatSessionRepository;
  final MemoryStorage memoryStorage;
  final MemoryIndex memoryIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ChatWorkspaceController _workspaceController;
  late final MemoryManagementController _memoryController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _workspaceController = ChatWorkspaceController(
      prototypeSession: widget.chatSession,
      repository: widget.chatSessionRepository ?? ChatSessionRepository(),
    );
    _workspaceController.initialize();
    _memoryController = MemoryManagementController(
      storage: widget.memoryStorage,
      memoryIndex: widget.memoryIndex,
      embeddingModelManager: widget.embeddingModelManager,
    )..initialize();
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    _memoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _workspaceController,
      builder: (context, child) {
        final activeSession = _workspaceController.activeSession;
        return Scaffold(
          key: _scaffoldKey,
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: AppButton.primary(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _workspaceController.createNewSession();
                        },
                        icon: Icons.add_comment_outlined,
                        label: 'New Chat',
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      children: [
                        const _DrawerSectionLabel(label: 'Recent Chats'),
                        for (final session
                            in _workspaceController.recentSessions)
                          _RecentChatTile(
                            session: session,
                            selected: activeSession?.record.id == session.id,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _workspaceController.switchToSession(
                                session.id,
                              );
                            },
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        const _DrawerSectionLabel(label: 'Navigate'),
                        ListTile(
                          key: const Key('drawer-models'),
                          leading: const Icon(Icons.memory_outlined),
                          title: const Text('Models'),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => ModelDownloadScreen(
                                  controller: widget.modelDownloadController,
                                  onModelReady: widget.onModelReady,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          key: const Key('drawer-skills'),
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: const Text('Skills'),
                          selected:
                              _workspaceController.destination ==
                              AppShellDestination.skills,
                          onTap: () {
                            Navigator.of(context).pop();
                            _workspaceController.showDestination(
                              AppShellDestination.skills,
                            );
                          },
                        ),
                        ListTile(
                          key: const Key('drawer-automation'),
                          leading: const Icon(Icons.tune_outlined),
                          title: const Text('Automation'),
                          selected:
                              _workspaceController.destination ==
                              AppShellDestination.automation,
                          onTap: () {
                            Navigator.of(context).pop();
                            _workspaceController.showDestination(
                              AppShellDestination.automation,
                            );
                          },
                        ),
                        ListTile(
                          key: const Key('drawer-mcp'),
                          leading: const Icon(Icons.hub_outlined),
                          title: const Text('MCP Connections'),
                          selected:
                              _workspaceController.destination ==
                              AppShellDestination.mcp,
                          onTap: () {
                            Navigator.of(context).pop();
                            _workspaceController.showDestination(
                              AppShellDestination.mcp,
                            );
                          },
                        ),
                        ListTile(
                          key: const Key('drawer-memory'),
                          leading: const Icon(Icons.storage_outlined),
                          title: const Text('Memory'),
                          selected:
                              _workspaceController.destination ==
                              AppShellDestination.memory,
                          onTap: () {
                            Navigator.of(context).pop();
                            _workspaceController.showDestination(
                              AppShellDestination.memory,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: double.infinity,
                      child: AppButton.secondary(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _workspaceController.showDestination(
                            AppShellDestination.settings,
                          );
                        },
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _ShellTopBar(
                  title: _titleForDestination(_workspaceController.destination),
                  onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  onChatPressed: activeSession == null
                      ? null
                      : () => _workspaceController.showDestination(
                          AppShellDestination.chat,
                        ),
                ),
                Expanded(child: _buildBody(activeSession)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(ChatWorkspaceSession? activeSession) {
    switch (_workspaceController.destination) {
      case AppShellDestination.chat:
        if (activeSession == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ChatScreen(
          chatSession: activeSession.chatSession,
          sessionTitle: activeSession.record.title,
          lastModified: activeSession.record.lastModified,
          onSendMessage: _workspaceController.sendMessage,
          onSendComposerSubmission: _workspaceController.sendComposerSubmission,
          capabilityResolver: ComposerCapabilityResolver(
            modelCapabilityProvider: CallbackActiveModelCapabilityProvider(
              () =>
                  widget
                      .modelDownloadController
                      .state
                      .selectedModel
                      ?.inputCapabilities ??
                  ModelInputCapabilities.textOnly,
            ),
            runtimeSupport: const DefaultAttachmentRuntimeSupport(),
          ),
        );
      case AppShellDestination.settings:
        return SettingsScreen(manager: widget.embeddingModelManager!);
      case AppShellDestination.skills:
        return SkillsScreen(controller: widget.skillRegistryController);
      case AppShellDestination.automation:
        return widget.automationController == null
            ? const Center(child: Text('Automation unavailable'))
            : AutomationScreen(controller: widget.automationController!);
      case AppShellDestination.mcp:
        return McpConnectionsScreen(
          controller: widget.mcpConnectionsController,
        );
      case AppShellDestination.memory:
        return MemoryScreen(controller: _memoryController);
    }
  }

  String _titleForDestination(AppShellDestination destination) {
    switch (destination) {
      case AppShellDestination.chat:
        return 'OpenReef';
      case AppShellDestination.settings:
        return 'Settings';
      case AppShellDestination.skills:
        return 'Skills';
      case AppShellDestination.automation:
        return 'Automation';
      case AppShellDestination.mcp:
        return 'MCP Connections';
      case AppShellDestination.memory:
        return 'Memory';
    }
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.title,
    required this.onMenuPressed,
    required this.onChatPressed,
  });

  final String title;
  final VoidCallback onMenuPressed;
  final VoidCallback? onChatPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('open-drawer-button'),
            onPressed: onMenuPressed,
            icon: const Icon(Icons.menu),
          ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppButton.secondary(onPressed: onChatPressed, label: 'Chat'),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _RecentChatTile extends StatelessWidget {
  const _RecentChatTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final ChatSessionRecord session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle =
        '${session.lastModified.month.toString().padLeft(2, '0')}/${session.lastModified.day.toString().padLeft(2, '0')} ${session.lastModified.hour.toString().padLeft(2, '0')}:${session.lastModified.minute.toString().padLeft(2, '0')}';
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
