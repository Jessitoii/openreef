import 'package:flutter/material.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/ui/app_theme.dart';

class McpConnectionsScreen extends StatefulWidget {
  const McpConnectionsScreen({required this.controller, super.key});

  final McpConnectionsController controller;

  @override
  State<McpConnectionsScreen> createState() => _McpConnectionsScreenState();
}

class _McpConnectionsScreenState extends State<McpConnectionsScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _persistConnection = false;
  bool _canConnect = false;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
    _urlController.addListener(_handleUrlChanged);
    _handleUrlChanged();
  }

  @override
  void dispose() {
    _urlController.removeListener(_handleUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<McpConnectionState>>(
      valueListenable: widget.controller.connections,
      builder: (context, connections, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ConnectionHeader(
              controller: _urlController,
              persistConnection: _persistConnection,
              onPersistChanged: (value) {
                setState(() {
                  _persistConnection = value;
                });
              },
              onConnect: _canConnect ? _handleConnect : null,
            ),
            const SizedBox(height: 12),
            if (connections.isEmpty)
              _EmptyConnectionsCard(onConnect: _handleConnect)
            else
              ...connections.map(
                (connection) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ConnectionCard(
                    connection: connection,
                    onDisconnect: () =>
                        widget.controller.disconnect(connection.url),
                    onConnect: () {
                      final endpointId = connection.endpointId;
                      if (endpointId != null) {
                        widget.controller.reconnectPersisted(endpointId);
                        return;
                      }
                      widget.controller.connect(
                        connection.url,
                        persist: connection.persisted,
                      );
                    },
                    onForget:
                        connection.persisted && connection.endpointId != null
                        ? () => widget.controller.forgetPersisted(
                            connection.endpointId!,
                          )
                        : null,
                  ),
                ),
              ),
            if (connections.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tip: Persisted connections auto-connect on boot for connection state recovery.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _handleConnect() async {
    if (!_canConnect) {
      return;
    }
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      return;
    }
    await widget.controller.connect(raw, persist: _persistConnection);
    if (!mounted) {
      return;
    }
    _urlController.clear();
  }

  void _handleUrlChanged() {
    final value = _urlController.text.trim();
    final parsed = Uri.tryParse(value);
    final canConnect =
        parsed != null && parsed.hasScheme && parsed.host.isNotEmpty;
    if (canConnect != _canConnect) {
      setState(() {
        _canConnect = canConnect;
      });
    }
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({
    required this.controller,
    required this.persistConnection,
    required this.onPersistChanged,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool persistConnection;
  final ValueChanged<bool> onPersistChanged;
  final Future<void> Function()? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCP CONNECTIONS',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to SSE endpoints and inspect available MCP tools. Current runtime does not route these tools into the active agent loop.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'MCP SSE URL',
                hintText: 'https://server.example.com/sse',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                final handler = onConnect;
                if (handler != null) {
                  handler();
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: persistConnection,
              onChanged: onPersistChanged,
              contentPadding: EdgeInsets.zero,
              title: const Text('Persist connection for reconnect on boot'),
              subtitle: Text(
                'Saves this endpoint and auto-reconnects on app startup. It does not currently execute background MCP tasks while the app is closed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.onDisconnect,
    required this.onConnect,
    this.onForget,
  });

  final McpConnectionState connection;
  final VoidCallback onDisconnect;
  final VoidCallback onConnect;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = _statusMeta(connection.status, theme);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    connection.url,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(label: label, color: color),
              ],
            ),
            const SizedBox(height: 8),
            if (connection.serverInfo != null)
              Text(
                'server: ${connection.serverInfo!.name} ${connection.serverInfo!.version}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (connection.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                connection.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'tools',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connection.tools.isEmpty
                  ? const <Widget>[_ToolChip(label: 'none')]
                  : connection.tools
                        .map((tool) => _ToolChip(label: tool.name))
                        .toList(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (connection.status == McpConnectionStatus.connected)
                  FilledButton.icon(
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: onConnect,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                if (onForget != null)
                  OutlinedButton.icon(
                    onPressed: onForget,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Forget'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _statusMeta(McpConnectionStatus status, ThemeData theme) {
    switch (status) {
      case McpConnectionStatus.connected:
        return ('connected', ReefPalette.darkSuccess);
      case McpConnectionStatus.connecting:
        return ('connecting', ReefPalette.coral);
      case McpConnectionStatus.error:
        return ('error', theme.colorScheme.error);
      case McpConnectionStatus.disconnected:
        return ('disconnected', theme.colorScheme.onSurfaceVariant);
    }
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _EmptyConnectionsCard extends StatelessWidget {
  const _EmptyConnectionsCard({required this.onConnect});

  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No MCP servers connected.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an SSE endpoint to inspect server/tool metadata and connection status.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link),
              label: const Text('Connect Now'),
            ),
          ],
        ),
      ),
    );
  }
}
