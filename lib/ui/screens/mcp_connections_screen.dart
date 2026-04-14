import 'package:flutter/material.dart';
import 'package:openreef/mcp/mcp_connector_registry.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:url_launcher/url_launcher.dart';

enum McpDiscoveryState { unknown, loading, available, empty, error }

class McpConnectionsScreen extends StatefulWidget {
  const McpConnectionsScreen({required this.controller, super.key});

  final McpConnectionsController controller;

  @override
  State<McpConnectionsScreen> createState() => _McpConnectionsScreenState();
}

class _McpConnectionsScreenState extends State<McpConnectionsScreen> {
  final TextEditingController _customUrlController = TextEditingController();
  bool _persistCustom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<McpConnectionState>>(
      valueListenable: widget.controller.connections,
      builder: (context, connections, _) {
        final connected = connections.where((state) => state.connected).toList();
        final presets = McpConnectorRegistry.presets
            .where((preset) => preset.id != 'custom_url')
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SectionHeader(
              title: 'Custom MCP Server',
              subtitle: 'Connect a manual MCP endpoint by URL.',
            ),
            const SizedBox(height: 12),
            _CustomUrlCard(
              controller: _customUrlController,
              persist: _persistCustom,
              onPersistChanged: (value) => setState(() => _persistCustom = value),
              onConnect: _connectCustom,
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              title: 'Available connectors',
              subtitle: 'Connect built-in integrations.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 720 ? 330.0 : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final preset in presets)
                      SizedBox(
                        width: cardWidth,
                        child: _PresetConnectorCard(
                          preset: preset,
                          onConnect: () => _openPresetSetup(preset),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              title: 'Connected connectors',
              subtitle: 'Manage active integrations and inspect runtime state.',
            ),
            const SizedBox(height: 12),
            connected.isEmpty
                ? const _EmptyConnectedState()
                : Column(
                    children: [
                      for (final connection in connected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ConnectedConnectorCard(
                            connection: connection,
                            onOpenDetails: () => _openDetails(connection),
                            onReconnect: () => _reconnect(connection),
                            onDisconnect: () => widget.controller.disconnect(connection.url),
                            onToggleEnabled: (value) => widget.controller.setEnabled(
                              connection.endpointId ?? connection.url,
                              value,
                            ),
                          ),
                        ),
                    ],
                  ),
            const SizedBox(height: 12),
            Text(
              'Connected only means the transport session is live. Discovery, import, and enablement remain separate.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectCustom() async {
    final raw = _customUrlController.text.trim();
    if (raw.isEmpty) return;
    try {
      await widget.controller.connect(raw, persist: _persistCustom);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return;
    }
    if (!mounted) return;
    _customUrlController.clear();
  }

  Future<void> _reconnect(McpConnectionState connection) async {
    if (connection.endpointId != null) {
      await widget.controller.reconnectPersisted(connection.endpointId!);
    } else {
      await widget.controller.connect(connection.url, persist: connection.persisted);
    }
  }

  void _openDetails(McpConnectionState connection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ConnectorDetailsScreen(
          connection: connection,
          onReconnect: () => _reconnect(connection),
          onDisconnect: () => widget.controller.disconnect(connection.url),
          onToggleEnabled: (value) => widget.controller.setEnabled(
            connection.endpointId ?? connection.url,
            value,
          ),
        ),
      ),
    );
  }

  Future<void> _openPresetSetup(McpConnectorPreset preset) async {
    if (preset.id == 'github') {
      await _openGitHubSheet(preset);
      return;
    }
    switch (preset.setupType) {
      case McpConnectorSetupType.manualEndpoint:
        await _openManualEndpointSheet(title: preset.authLaunchLabel);
      case McpConnectorSetupType.oauth:
        await _openOAuthSheet(preset);
      case McpConnectorSetupType.pat:
        await _openUnsupportedSheet(
          title: preset.authLaunchLabel,
          message: 'PAT/token connect is not implemented yet.',
        );
      case McpConnectorSetupType.apiKey:
        await _openUnsupportedSheet(
          title: preset.authLaunchLabel,
          message: 'API key connect is not implemented yet.',
        );
      case McpConnectorSetupType.baseUrlToken:
        await _openBaseUrlTokenSheet(preset);
    }
  }

  Future<void> _openGitHubSheet(McpConnectorPreset preset) async {
    final patController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preset.authLaunchLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Use GitHub OAuth or paste a personal access token.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                debugPrint('[MCP UI] github oauth tapped');
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final authUrl = await widget.controller.startOAuth(preset.id);
                  if (!mounted || authUrl == null) {
                    return;
                  }
                  navigator.pop();
                  final uri = Uri.parse(authUrl);
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.inAppBrowserView,
                  );
                  if (!launched) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: const Text('Launch OAuth'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: patController,
              decoration: const InputDecoration(labelText: 'Personal access token'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                final token = patController.text.trim();
                if (token.isEmpty) return;
                debugPrint('[MCP UI] github pat submit tapped');
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  navigator.pop();
                  await widget.controller.connectWithToken(
                    connectorId: preset.id,
                    token: token,
                    persist: true,
                  );
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: const Text('Connect with token'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOAuthSheet(McpConnectorPreset preset) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SetupSheet(
        title: preset.authLaunchLabel,
        subtitle: 'OAuth flow not implemented yet.',
        primaryLabel: 'OAuth flow not implemented yet',
        onPrimary: null,
        body: const [
          _SetupNote('This connector cannot launch OAuth yet.'),
        ],
      ),
    );
  }

  Future<void> _openBaseUrlTokenSheet(McpConnectorPreset preset) async {
    final baseUrlController = TextEditingController();
    final tokenController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preset.authLaunchLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Enter the Home Assistant base URL and long-lived token.'),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrlController,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(labelText: 'Long-lived token'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final baseUrl = baseUrlController.text.trim();
                final token = tokenController.text.trim();
                if (baseUrl.isEmpty || token.isEmpty) return;
                debugPrint('[MCP UI] baseUrlToken submit tapped for ${preset.id}');
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  navigator.pop();
                  await widget.controller.connectWithBaseUrlToken(
                    connectorId: preset.id,
                    baseUrl: baseUrl,
                    token: token,
                    persist: true,
                  );
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: Text(preset.authLaunchLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManualEndpointSheet({required String title}) async {
    final endpointController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Connect a manual MCP endpoint by URL.'),
            const SizedBox(height: 12),
            TextField(
              controller: endpointController,
              decoration: const InputDecoration(
                labelText: 'MCP server URL',
                hintText: 'https://server.example.com/sse',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final raw = endpointController.text.trim();
                if (raw.isEmpty) return;
                debugPrint('[MCP UI] manual endpoint submit tapped');
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  navigator.pop();
                  await widget.controller.connectManualEndpoint(raw, persist: true);
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnsupportedSheet({
    required String title,
    required String message,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: null,
              child: Text(message),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CustomUrlCard extends StatelessWidget {
  const _CustomUrlCard({
    required this.controller,
    required this.persist,
    required this.onPersistChanged,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool persist;
  final ValueChanged<bool> onPersistChanged;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'MCP server URL',
              hintText: 'https://server.example.com/sse',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: persist,
            onChanged: onPersistChanged,
            contentPadding: EdgeInsets.zero,
            title: const Text('Persist server'),
            subtitle: Text(
              'Saved endpoints can reconnect later without retyping the URL.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const Text('Connect custom server'),
          ),
        ],
      ),
    );
  }
}

class _PresetConnectorCard extends StatelessWidget {
  const _PresetConnectorCard({required this.preset, required this.onConnect});

  final McpConnectorPreset preset;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ConnectorIcon(icon: preset.icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      preset.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(label: preset.setupType.label),
              _Badge(label: preset.authStrategy.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            preset.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _isRealConnectSupported(preset) ? onConnect : null,
            child: Text(_buttonLabel(preset)),
          ),
        ],
      ),
    );
  }

  bool _isRealConnectSupported(McpConnectorPreset preset) {
    return preset.setupType == McpConnectorSetupType.manualEndpoint ||
        preset.setupType == McpConnectorSetupType.baseUrlToken ||
        preset.id == 'github';
  }

  String _buttonLabel(McpConnectorPreset preset) {
    if (preset.id == 'github') {
      return preset.authLaunchLabel;
    }
    return switch (preset.setupType) {
      McpConnectorSetupType.manualEndpoint => preset.authLaunchLabel,
      McpConnectorSetupType.baseUrlToken => preset.authLaunchLabel,
      McpConnectorSetupType.oauth => 'OAuth flow not implemented yet',
      McpConnectorSetupType.pat => 'PAT/token flow not implemented yet',
      McpConnectorSetupType.apiKey => 'API key flow not implemented yet',
    };
  }
}

class _ConnectedConnectorCard extends StatelessWidget {
  const _ConnectedConnectorCard({
    required this.connection,
    required this.onOpenDetails,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onToggleEnabled,
  });

  final McpConnectionState connection;
  final VoidCallback onOpenDetails;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discoveryState = _toolsDiscoveryState(connection);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ConnectorIcon(icon: Icons.hub_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.serverInfo?.name.isNotEmpty == true
                          ? connection.serverInfo!.name
                          : connection.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _connectionSubtitle(connection),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: connection.enabled, onChanged: onToggleEnabled),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(label: connection.connected ? 'Transport live' : 'Offline'),
              _Badge(label: connection.enabled ? 'Enabled' : 'Disabled'),
              _Badge(label: _statusLabel(connection)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('Tools', style: theme.textTheme.bodySmall)),
              _Badge(label: _discoveryLabel(discoveryState)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Events', style: theme.textTheme.bodySmall)),
              const _Badge(label: 'unknown'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onOpenDetails, child: const Text('Details')),
              OutlinedButton(onPressed: onReconnect, child: const Text('Reconnect')),
              FilledButton.tonal(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectorDetailsScreen extends StatelessWidget {
  const _ConnectorDetailsScreen({
    required this.connection,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onToggleEnabled,
  });

  final McpConnectionState connection;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(connection.serverInfo?.name ?? 'Connector details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSection(
            title: 'Status',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Badge(label: connection.enabled ? 'Enabled' : 'Disabled'),
                _Badge(label: connection.connected ? 'Transport live' : 'Transport offline'),
                _Badge(label: connection.toolsImportedIntoRuntime ? 'Imported' : 'Not imported'),
                _Badge(label: _statusLabel(connection)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CardSection(
            title: 'Auth',
            child: _KeyValueList(
              items: [
                ('Strategy', _authLabel(connection)),
                ('State', _authStateLabel(connection)),
                ('Health', _healthLabel(connection)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CardSection(
            title: 'Discovery',
            child: Column(
              children: [
                _DiscoveryBlock(
                  title: 'Tools',
                  state: _toolsDiscoveryState(connection),
                  entries: connection.tools.map((tool) => tool.name).toList(growable: false),
                ),
                const SizedBox(height: 12),
                const _DiscoveryBlock(
                  title: 'Events',
                  state: McpDiscoveryState.unknown,
                  entries: <String>[],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CardSection(
            title: 'Actions',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: connection.enabled,
                  onChanged: onToggleEnabled,
                  title: const Text('Enabled'),
                  contentPadding: EdgeInsets.zero,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onReconnect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    ),
                    FilledButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CardSection(
            title: 'Tools',
            child: connection.tools.isEmpty
                ? const _EmptyStateCard(
                    title: 'No tools discovered',
                    body: 'This connector has not exposed any runtime tools yet, or discovery is unavailable.',
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: connection.tools.map((tool) => _Badge(label: tool.name)).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          const _CardSection(
            title: 'Events',
            child: _EmptyStateCard(
              title: 'Events not yet discovered',
              body: 'The current MCP runtime does not expose event discovery for this connector.',
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyConnectedState extends StatelessWidget {
  const _EmptyConnectedState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: const Text('No connectors are connected yet'),
    );
  }
}

class _DiscoveryBlock extends StatelessWidget {
  const _DiscoveryBlock({
    required this.title,
    required this.state,
    required this.entries,
  });

  final String title;
  final McpDiscoveryState state;
  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              _Badge(label: _discoveryLabel(state)),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              _emptyDiscoveryMessage(state),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entries.map((entry) => _Badge(label: entry)).toList(),
            ),
        ],
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  const _KeyValueList({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 96, child: Text(item.$1, style: theme.textTheme.bodySmall)),
                Expanded(
                  child: Text(
                    item.$2,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectorIcon extends StatelessWidget {
  const _ConnectorIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      ),
      child: Icon(icon, size: 20),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SetupSheet extends StatelessWidget {
  const _SetupSheet({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    this.onPrimary,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle),
          const SizedBox(height: 12),
          ...body,
          const SizedBox(height: 12),
          FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        ],
      ),
    );
  }
}

class _SetupNote extends StatelessWidget {
  const _SetupNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text('• $text');
}

McpDiscoveryState _toolsDiscoveryState(McpConnectionState connection) {
  if (connection.status == McpConnectionStatus.error) return McpDiscoveryState.error;
  if (connection.status == McpConnectionStatus.connecting) return McpDiscoveryState.loading;
  if (!connection.connected) return McpDiscoveryState.unknown;
  return connection.tools.isEmpty ? McpDiscoveryState.empty : McpDiscoveryState.available;
}

String _discoveryLabel(McpDiscoveryState state) => switch (state) {
  McpDiscoveryState.unknown => 'unknown',
  McpDiscoveryState.loading => 'loading',
  McpDiscoveryState.available => 'available',
  McpDiscoveryState.empty => 'empty',
  McpDiscoveryState.error => 'error',
};

String _emptyDiscoveryMessage(McpDiscoveryState state) => switch (state) {
  McpDiscoveryState.unknown => 'Not yet discovered.',
  McpDiscoveryState.loading => 'Discovery is loading.',
  McpDiscoveryState.available => 'No entries provided.',
  McpDiscoveryState.empty => 'No runtime items discovered yet.',
  McpDiscoveryState.error => 'Discovery is unavailable.',
};

String _statusLabel(McpConnectionState connection) {
  if (!connection.enabled) return 'disabled';
  if (connection.status == McpConnectionStatus.connecting) return 'connecting';
  if (connection.status == McpConnectionStatus.connected) return 'connected';
  if (connection.status == McpConnectionStatus.error) return 'auth_error';
  return 'disconnected';
}

String _connectionSubtitle(McpConnectionState connection) {
  final parts = <String>[
    if (connection.serverInfo?.name.isNotEmpty == true) connection.serverInfo!.name,
    if (connection.serverInfo?.version.isNotEmpty == true) connection.serverInfo!.version,
    connection.enabled ? 'enabled' : 'disabled',
  ];
  return parts.join(' · ');
}

String _authLabel(McpConnectionState connection) {
  return connection.persisted ? 'persistent endpoint' : 'manual session';
}

String _authStateLabel(McpConnectionState connection) {
  if (connection.status == McpConnectionStatus.error) return 'auth error';
  if (connection.connected) return 'authenticated/transport live';
  if (connection.status == McpConnectionStatus.connecting) return 'auth in progress';
  return 'not authenticated';
}

String _healthLabel(McpConnectionState connection) {
  if (!connection.enabled) return 'disabled';
  if (connection.status == McpConnectionStatus.error) return 'degraded';
  if (connection.connected) {
    return connection.tools.isEmpty ? 'degraded' : 'healthy';
  }
  return 'unknown';
}
