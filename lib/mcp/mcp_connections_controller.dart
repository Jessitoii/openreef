import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_sse_transport.dart';

enum McpConnectionStatus { disconnected, connecting, connected, error }

class McpConnectionState {
  const McpConnectionState({
    required this.url,
    required this.status,
    this.serverInfo,
    this.tools = const <McpTool>[],
    this.errorMessage,
    this.persisted = false,
  });

  final String url;
  final McpConnectionStatus status;
  final McpServerInfo? serverInfo;
  final List<McpTool> tools;
  final String? errorMessage;
  final bool persisted;

  McpConnectionState copyWith({
    McpConnectionStatus? status,
    McpServerInfo? serverInfo,
    List<McpTool>? tools,
    String? errorMessage,
    bool? persisted,
  }) {
    return McpConnectionState(
      url: url,
      status: status ?? this.status,
      serverInfo: serverInfo ?? this.serverInfo,
      tools: tools ?? this.tools,
      errorMessage: errorMessage,
      persisted: persisted ?? this.persisted,
    );
  }
}

class McpConnectionsController {
  McpConnectionsController({
    required McpConnectionStore store,
    McpClientInfo clientInfo =
        const McpClientInfo(name: 'OpenReef', version: '1.0.0+1'),
    bool autoConnectPersisted = true,
  })  : _store = store,
        _clientInfo = clientInfo,
        _autoConnectPersisted = autoConnectPersisted;

  final McpConnectionStore _store;
  final McpClientInfo _clientInfo;
  final bool _autoConnectPersisted;
  final ValueNotifier<List<McpConnectionState>> _connections =
      ValueNotifier<List<McpConnectionState>>(const <McpConnectionState>[]);
  final Map<String, _McpConnectionSession> _sessions =
      <String, _McpConnectionSession>{};

  ValueListenable<List<McpConnectionState>> get connections => _connections;

  Future<void> initialize() async {
    final urls = await _store.loadAll();
    if (urls.isEmpty) {
      return;
    }
    for (final url in urls) {
      _upsertState(
        McpConnectionState(
          url: url,
          status: McpConnectionStatus.disconnected,
          persisted: true,
        ),
      );
    }
    if (_autoConnectPersisted) {
      for (final url in urls) {
        await connect(url, persist: true);
      }
    }
  }

  Future<void> connect(String url, {required bool persist}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final existing = _sessions[trimmed];
    if (existing != null) {
      return;
    }

    _upsertState(
      McpConnectionState(
        url: trimmed,
        status: McpConnectionStatus.connecting,
        persisted: persist,
      ),
    );

    final session = _McpConnectionSession(
      transport: McpSseTransport(sseEndpoint: Uri.parse(trimmed)),
    );
    _sessions[trimmed] = session;
    try {
      await session.client.connect();
      await _awaitEndpoint(session, timeout: const Duration(seconds: 4));
      final initResult = await session.client.initialize(
        clientInfo: _clientInfo,
      );
      final tools = await session.client.listTools();

      if (persist) {
        await _store.save(trimmed);
      }

      _upsertState(
        McpConnectionState(
          url: trimmed,
          status: McpConnectionStatus.connected,
          serverInfo: initResult.serverInfo,
          tools: tools,
          persisted: persist,
        ),
      );
    } catch (error) {
      await session.client.close();
      _sessions.remove(trimmed);
      _upsertState(
        McpConnectionState(
          url: trimmed,
          status: McpConnectionStatus.error,
          errorMessage: error.toString(),
          persisted: persist,
        ),
      );
    }
  }

  Future<void> disconnect(
    String url, {
    bool removePersistence = false,
  }) async {
    final trimmed = url.trim();
    final session = _sessions.remove(trimmed);
    await session?.client.close();

    final current = _findState(trimmed);
    final persisted = current?.persisted ?? false;
    if (removePersistence && persisted) {
      await _store.delete(trimmed);
    }

    _upsertState(
      McpConnectionState(
        url: trimmed,
        status: McpConnectionStatus.disconnected,
        persisted: persisted && !removePersistence,
      ),
    );
  }

  Future<void> refresh(String url) async {
    final trimmed = url.trim();
    final session = _sessions[trimmed];
    if (session == null) {
      return;
    }
    try {
      final tools = await session.client.listTools();
      final existing = _findState(trimmed);
      _upsertState(
        (existing ??
                McpConnectionState(
                  url: trimmed,
                  status: McpConnectionStatus.connected,
                ))
            .copyWith(tools: tools),
      );
    } catch (error) {
      _upsertState(
        McpConnectionState(
          url: trimmed,
          status: McpConnectionStatus.error,
          errorMessage: error.toString(),
          persisted: _findState(trimmed)?.persisted ?? false,
        ),
      );
    }
  }

  McpConnectionState? _findState(String url) {
    for (final state in _connections.value) {
      if (state.url == url) {
        return state;
      }
    }
    return null;
  }

  void _upsertState(McpConnectionState state) {
    final current = _connections.value;
    final updated = <McpConnectionState>[];
    var replaced = false;
    for (final entry in current) {
      if (entry.url == state.url) {
        updated.add(state);
        replaced = true;
      } else {
        updated.add(entry);
      }
    }
    if (!replaced) {
      updated.add(state);
    }
    _connections.value = List<McpConnectionState>.unmodifiable(updated);
  }

  Future<void> _awaitEndpoint(
    _McpConnectionSession session, {
    required Duration timeout,
  }) async {
    try {
      await session.transport.messages.firstWhere(
        (message) => message.event == 'endpoint',
      ).timeout(timeout);
    } on TimeoutException {
      // Some servers will accept initialize without an explicit endpoint event.
    }
  }
}

class _McpConnectionSession {
  _McpConnectionSession({
    required this.transport,
  }) : client = McpClient(transport);

  final McpSseTransport transport;
  final McpClient client;
}
