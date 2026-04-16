import 'package:flutter/material.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_connector_registry.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';

class McpConnectionsScreen extends StatefulWidget {
  const McpConnectionsScreen({required this.controller, super.key});

  final McpConnectionsController controller;

  @override
  State<McpConnectionsScreen> createState() => _McpConnectionsScreenState();
}

class _McpConnectionsScreenState extends State<McpConnectionsScreen> {
  final TextEditingController _customUrlController = TextEditingController();
  String? _customUrlError;
  bool _connectingCustom = false;

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _connectCustom() async {
    final url = _customUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _customUrlError = 'Enter an MCP server URL.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _customUrlError = 'Use a full URL like https://host/sse.');
      return;
    }
    setState(() {
      _connectingCustom = true;
      _customUrlError = null;
    });
    try {
      await widget.controller.connectManualEndpoint(url, persist: true);
      if (!mounted) return;
      _customUrlController.clear();
    } catch (error) {
      if (!mounted) return;
      setState(() => _customUrlError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _connectingCustom = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<McpConnectionState>>(
      valueListenable: widget.controller.connections,
      builder: (context, connections, child) {
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const AppPageHeader(
                  title: 'Integrations',
                  subtitle: 'Connect OpenReef to real MCP servers.',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: _CustomMcpCard(
                    controller: _customUrlController,
                    errorText: _customUrlError,
                    connecting: _connectingCustom,
                    onSubmit: _connectCustom,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (connections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      'Connected endpoints',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final state in connections)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: _ConnectionCard(
                        state: state,
                        onRefresh: state.connected
                            ? () => widget.controller.refresh(state.url)
                            : null,
                        onDelete: state.persisted
                            ? () => AppComponents.showDestructiveDialog(
                                context: context,
                                title: 'Remove MCP endpoint?',
                                content:
                                    'This removes the saved endpoint and any imported tools from runtime.',
                                confirmLabel: 'Remove',
                                onConfirm: () => widget.controller
                                    .forgetPersisted(state.endpointId!),
                              )
                            : null,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(
                    'Coming soon',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final preset in McpConnectorRegistry.presets.where(
                  (preset) => preset.id != 'custom_url',
                ))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: _UnavailablePresetCard(preset: preset),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomMcpCard extends StatelessWidget {
  const _CustomMcpCard({
    required this.controller,
    required this.errorText,
    required this.connecting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool connecting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Custom MCP Server',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Use a real MCP endpoint URL. OpenReef will connect, discover tools, and persist the endpoint if the server responds.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            enabled: !connecting,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'MCP server URL',
              hintText: 'https://example.com/sse',
              errorText: errorText,
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => connecting ? null : onSubmit(),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.primary(
              onPressed: connecting ? null : onSubmit,
              icon: Icons.link_outlined,
              label: connecting ? 'Connecting...' : 'Connect custom server',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.onRefresh,
    required this.onDelete,
  });

  final McpConnectionState state;
  final VoidCallback? onRefresh;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (state.status) {
      McpConnectionStatus.connected => 'Connected',
      McpConnectionStatus.connecting => 'Connecting',
      McpConnectionStatus.error => 'Error',
      McpConnectionStatus.disconnected => 'Disconnected',
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  state.serverInfo?.name.isNotEmpty == true
                      ? state.serverInfo!.name
                      : state.url,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppBadge(
                label: statusLabel,
                isSuccess: state.connected,
                isError: state.status == McpConnectionStatus.error,
              ),
            ],
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.toolsImportedIntoRuntime
                ? '${state.importedToolCount} tools imported into runtime.'
                : 'No tools imported into runtime yet.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton.secondary(
                onPressed: onRefresh,
                icon: Icons.refresh,
                label: 'Refresh tools',
              ),
              if (onDelete != null)
                AppButton.destructive(
                  onPressed: onDelete,
                  icon: Icons.delete_outline,
                  label: 'Remove endpoint',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnavailablePresetCard extends StatelessWidget {
  const _UnavailablePresetCard({required this.preset});

  final McpConnectorPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(preset.icon, size: 32, color: theme.disabledColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.disabledColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Requires OAuth configuration, not yet available.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const AppBadge(label: 'Coming Soon'),
        ],
      ),
    );
  }
}
