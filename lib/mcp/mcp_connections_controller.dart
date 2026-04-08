import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_endpoint_policy.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_sse_transport.dart';
import 'package:openreef/mcp/mcp_transport.dart';

typedef McpTransportFactory = McpTransport Function(Uri endpoint);

enum McpConnectionStatus { disconnected, connecting, connected, error }

class McpConnectionState {
  const McpConnectionState({
    required this.url,
    required this.status,
    this.serverInfo,
    this.tools = const <McpTool>[],
    this.errorMessage,
    this.persisted = false,
    this.endpointId,
    this.trusted = false,
    this.requiresManualSecretEntry = false,
    this.runtimeSourceId,
    this.importedToolIds = const <String>[],
  });

  final String url;
  final McpConnectionStatus status;
  final McpServerInfo? serverInfo;
  final List<McpTool> tools;
  final String? errorMessage;
  final bool persisted;
  final String? endpointId;
  final bool trusted;
  final bool requiresManualSecretEntry;
  final String? runtimeSourceId;
  final List<String> importedToolIds;

  bool get saved => persisted;
  bool get connected => status == McpConnectionStatus.connected;
  int get importedToolCount => importedToolIds.length;
  bool get toolsImportedIntoRuntime => importedToolCount > 0;

  McpConnectionState copyWith({
    McpConnectionStatus? status,
    McpServerInfo? serverInfo,
    List<McpTool>? tools,
    String? errorMessage,
    bool? persisted,
    String? endpointId,
    bool? trusted,
    bool? requiresManualSecretEntry,
    String? runtimeSourceId,
    List<String>? importedToolIds,
  }) {
    return McpConnectionState(
      url: url,
      status: status ?? this.status,
      serverInfo: serverInfo ?? this.serverInfo,
      tools: tools ?? this.tools,
      errorMessage: errorMessage,
      persisted: persisted ?? this.persisted,
      endpointId: endpointId ?? this.endpointId,
      trusted: trusted ?? this.trusted,
      requiresManualSecretEntry:
          requiresManualSecretEntry ?? this.requiresManualSecretEntry,
      runtimeSourceId: runtimeSourceId ?? this.runtimeSourceId,
      importedToolIds: importedToolIds ?? this.importedToolIds,
    );
  }
}

class McpConnectionsController {
  McpConnectionsController({
    required McpConnectionStore store,
    required McpRuntimeCoordinator runtimeCoordinator,
    McpClientInfo clientInfo = const McpClientInfo(
      name: 'OpenReef',
      version: '1.0.0+1',
    ),
    bool autoConnectPersisted = true,
    McpTransportFactory? transportFactory,
  }) : _store = store,
       _runtimeCoordinator = runtimeCoordinator,
       _clientInfo = clientInfo,
       _autoConnectPersisted = autoConnectPersisted,
       _transportFactory =
           transportFactory ??
           ((endpoint) => McpSseTransport(sseEndpoint: endpoint));

  final McpConnectionStore _store;
  final McpRuntimeCoordinator _runtimeCoordinator;
  final McpClientInfo _clientInfo;
  final bool _autoConnectPersisted;
  final McpTransportFactory _transportFactory;
  final ValueNotifier<List<McpConnectionState>> _connections =
      ValueNotifier<List<McpConnectionState>>(const <McpConnectionState>[]);
  final Map<String, _McpConnectionSession> _sessions =
      <String, _McpConnectionSession>{};
  final Map<String, McpPersistedEndpoint> _persistedEndpoints =
      <String, McpPersistedEndpoint>{};
  final Map<String, String> _liveSourceIdsByRuntimeUrl = <String, String>{};
  bool _initialized = false;
  int _liveSourceCounter = 0;

  ValueListenable<List<McpConnectionState>> get connections => _connections;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    final result = await _store.loadAll();
    _persistedEndpoints
      ..clear()
      ..addEntries(
        result.endpoints.map(
          (endpoint) =>
              MapEntry<String, McpPersistedEndpoint>(endpoint.id, endpoint),
        ),
      );
    for (final endpoint in result.endpoints) {
      _upsertState(
        McpConnectionState(
          url: endpoint.displayUri,
          status: McpConnectionStatus.disconnected,
          persisted: true,
          endpointId: endpoint.id,
          trusted: endpoint.trusted,
          requiresManualSecretEntry: endpoint.requiresManualSecretEntry,
          runtimeSourceId: endpoint.id,
          importedToolIds: _runtimeCoordinator.importedToolIdsForSource(
            endpoint.id,
          ),
        ),
      );
    }
    if (_autoConnectPersisted) {
      for (final endpoint in result.endpoints) {
        if (!endpoint.canAutoConnect || endpoint.requiresManualSecretEntry) {
          continue;
        }
        await reconnectPersisted(endpoint.id);
      }
    }
  }

  Future<void> connect(String url, {required bool persist}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }
    late final McpEndpointNormalizationResult preview;
    try {
      preview = McpEndpointPolicy.normalizeForPersistence(
        id: 'preview',
        rawUrl: trimmed,
        trusted: false,
        migrationState: McpPersistedEndpointMigrationState.nativeTrusted,
        createdAt: DateTime.now().toUtc(),
        persistedAt: DateTime.now().toUtc(),
      );
    } on Exception catch (error) {
      _upsertState(
        McpConnectionState(
          url: trimmed,
          status: McpConnectionStatus.error,
          errorMessage: error.toString(),
          persisted: false,
        ),
      );
      return;
    }

    await _connectRuntime(
      runtimeUrl: trimmed,
      displayUrl: preview.endpoint.displayUri,
      persistAfterConnect: persist,
      trusted: false,
      requiresManualSecretEntry: false,
    );
  }

  Future<void> reconnectPersisted(String endpointId) async {
    final endpoint = _persistedEndpoints[endpointId];
    if (endpoint == null) {
      return;
    }
    if (endpoint.requiresManualSecretEntry) {
      _runtimeCoordinator.removeSource(endpoint.id);
      _upsertState(
        McpConnectionState(
          url: endpoint.displayUri,
          status: McpConnectionStatus.error,
          errorMessage: 'manual_secret_reentry_required',
          persisted: true,
          endpointId: endpoint.id,
          trusted: endpoint.trusted,
          requiresManualSecretEntry: true,
          runtimeSourceId: endpoint.id,
          importedToolIds: const <String>[],
        ),
      );
      return;
    }

    final runtimeUrl = await _store.resolveRuntimeUrl(endpoint);
    if (runtimeUrl == null || runtimeUrl.trim().isEmpty) {
      _runtimeCoordinator.removeSource(endpoint.id);
      _upsertState(
        McpConnectionState(
          url: endpoint.displayUri,
          status: McpConnectionStatus.error,
          errorMessage: 'missing_secure_secret_material',
          persisted: true,
          endpointId: endpoint.id,
          trusted: endpoint.trusted,
          requiresManualSecretEntry: endpoint.requiresManualSecretEntry,
          runtimeSourceId: endpoint.id,
          importedToolIds: const <String>[],
        ),
      );
      return;
    }

    await _connectRuntime(
      runtimeUrl: runtimeUrl,
      displayUrl: endpoint.displayUri,
      persistedEndpoint: endpoint,
      persistAfterConnect: false,
      trusted: endpoint.trusted,
      requiresManualSecretEntry: endpoint.requiresManualSecretEntry,
    );
  }

  Future<void> disconnect(String url, {bool removePersistence = false}) async {
    final current = _findState(url);
    final sessionKey = _sessionKeyForState(current, fallbackUrl: url);
    final session = _sessions.remove(sessionKey);
    _runtimeCoordinator.removeSource(sessionKey);
    final liveRuntimeUrl = session?.runtimeUrl;
    if (liveRuntimeUrl != null) {
      _liveSourceIdsByRuntimeUrl.remove(liveRuntimeUrl);
    }
    if (session != null) {
      session.isActive = false;
      await session.messageSubscription?.cancel();
      await session.client.close();
    }

    if (removePersistence && current?.endpointId != null) {
      await forgetPersisted(current!.endpointId!);
      return;
    }

    _upsertState(
      McpConnectionState(
        url: current?.url ?? url.trim(),
        status: McpConnectionStatus.disconnected,
        persisted: current?.persisted ?? false,
        endpointId: current?.endpointId,
        trusted: current?.trusted ?? false,
        requiresManualSecretEntry: current?.requiresManualSecretEntry ?? false,
        runtimeSourceId: current?.runtimeSourceId,
        importedToolIds: const <String>[],
      ),
    );
  }

  Future<void> forgetPersisted(String endpointId) async {
    final endpoint = _persistedEndpoints.remove(endpointId);
    if (endpoint == null) {
      return;
    }
    final session = _sessions.remove(endpointId);
    _runtimeCoordinator.removeSource(endpointId);
    final liveRuntimeUrl = session?.runtimeUrl;
    if (liveRuntimeUrl != null) {
      _liveSourceIdsByRuntimeUrl.remove(liveRuntimeUrl);
    }
    if (session != null) {
      session.isActive = false;
      await session.messageSubscription?.cancel();
      await session.client.close();
    }
    await _store.deleteById(endpointId);
    final updated = _connections.value
        .where((state) => state.endpointId != endpointId)
        .toList(growable: false);
    _connections.value = List<McpConnectionState>.unmodifiable(updated);
  }

  Future<void> refresh(String url) async {
    final current = _findState(url);
    final sessionKey = _sessionKeyForState(current, fallbackUrl: url);
    final session = _sessions[sessionKey];
    if (session == null) {
      return;
    }
    try {
      final tools = await session.client.listTools();
      final imported = await _replaceImportedTools(
        session,
        tools: tools,
      );
      final existing = _findState(url);
      _upsertState(
        (existing ??
                McpConnectionState(
                  url: url.trim(),
                  status: McpConnectionStatus.connected,
                ))
            .copyWith(
              tools: tools,
              errorMessage: null,
              importedToolIds: imported.importedToolIds,
            ),
      );
    } catch (error) {
      _runtimeCoordinator.removeSource(sessionKey);
      _upsertState(
        McpConnectionState(
          url: current?.url ?? url.trim(),
          status: McpConnectionStatus.error,
          errorMessage: error.toString(),
          persisted: current?.persisted ?? false,
          endpointId: current?.endpointId,
          trusted: current?.trusted ?? false,
          requiresManualSecretEntry:
              current?.requiresManualSecretEntry ?? false,
          runtimeSourceId: current?.runtimeSourceId,
          importedToolIds: const <String>[],
        ),
      );
    }
  }

  Future<void> _connectRuntime({
    required String runtimeUrl,
    required String displayUrl,
    required bool persistAfterConnect,
    required bool trusted,
    required bool requiresManualSecretEntry,
    McpPersistedEndpoint? persistedEndpoint,
  }) async {
    final provisionalSourceId =
        persistedEndpoint?.id ??
        _liveSourceIdsByRuntimeUrl[runtimeUrl] ??
        _nextLiveSourceId();
    if (_sessions.containsKey(provisionalSourceId)) {
      return;
    }

    _upsertState(
      McpConnectionState(
        url: displayUrl,
        status: McpConnectionStatus.connecting,
        persisted: persistedEndpoint != null || persistAfterConnect,
        endpointId: persistedEndpoint?.id,
        trusted: persistedEndpoint?.trusted ?? trusted,
        requiresManualSecretEntry: requiresManualSecretEntry,
        runtimeSourceId: provisionalSourceId,
        importedToolIds: const <String>[],
      ),
    );

    final transport = _transportFactory(Uri.parse(runtimeUrl));
    final session = _McpConnectionSession(
      sourceId: provisionalSourceId,
      runtimeUrl: runtimeUrl,
      transport: transport,
    );
    try {
      await session.client.connect();
      await _awaitEndpoint(session, timeout: const Duration(seconds: 4));
      final initResult = await session.client.initialize(
        clientInfo: _clientInfo,
      );
      final tools = await session.client.listTools();

      var endpoint = persistedEndpoint;
      if (persistAfterConnect) {
        endpoint = await _store.save(runtimeUrl, trusted: true);
        _persistedEndpoints[endpoint.id] = endpoint;
      }

      final sourceId = endpoint?.id ?? provisionalSourceId;
      session
        ..sourceId = sourceId
        ..persistedEndpoint = endpoint
        ..trusted = endpoint?.trusted ?? trusted
        ..requiresManualSecretEntry =
            endpoint?.requiresManualSecretEntry ?? requiresManualSecretEntry;
      session.messageSubscription = transport.messages.listen((message) {
        final runtimeEvent = _runtimeEventFromMessage(sourceId, message);
        if (runtimeEvent != null) {
          _runtimeCoordinator.emitSourceEvent(runtimeEvent);
        }
      });
      _sessions[sourceId] = session;
      if (endpoint == null) {
        _liveSourceIdsByRuntimeUrl[runtimeUrl] = sourceId;
      } else {
        _liveSourceIdsByRuntimeUrl.remove(runtimeUrl);
      }
      final imported = await _replaceImportedTools(session, tools: tools);
      _upsertState(
        McpConnectionState(
          url: endpoint?.displayUri ?? displayUrl,
          status: McpConnectionStatus.connected,
          serverInfo: initResult.serverInfo,
          tools: tools,
          persisted: endpoint != null,
          endpointId: endpoint?.id,
          trusted: endpoint?.trusted ?? false,
          requiresManualSecretEntry:
              endpoint?.requiresManualSecretEntry ?? requiresManualSecretEntry,
          runtimeSourceId: sourceId,
          importedToolIds: imported.importedToolIds,
        ),
      );
    } catch (error) {
      _runtimeCoordinator.removeSource(provisionalSourceId);
      session.isActive = false;
      await session.messageSubscription?.cancel();
      await session.client.close();
      _upsertState(
        McpConnectionState(
          url: displayUrl,
          status: McpConnectionStatus.error,
          errorMessage: error.toString(),
          persisted: persistedEndpoint != null || persistAfterConnect,
          endpointId: persistedEndpoint?.id,
          trusted: persistedEndpoint?.trusted ?? false,
          requiresManualSecretEntry:
              persistedEndpoint?.requiresManualSecretEntry ??
              requiresManualSecretEntry,
          runtimeSourceId: provisionalSourceId,
          importedToolIds: const <String>[],
        ),
      );
    }
  }

  McpConnectionState? _findState(String urlOrId) {
    for (final state in _connections.value) {
      if (state.url == urlOrId || state.endpointId == urlOrId) {
        return state;
      }
    }
    return null;
  }

  String _sessionKeyForState(
    McpConnectionState? state, {
    required String fallbackUrl,
  }) {
    return state?.runtimeSourceId ?? state?.endpointId ?? fallbackUrl.trim();
  }

  Future<McpImportedToolSnapshot> _replaceImportedTools(
    _McpConnectionSession session, {
    required List<McpTool> tools,
  }) {
    return _runtimeCoordinator.replaceSourceTools(
      binding: McpRuntimeSourceBinding(
        sourceId: session.sourceId,
        client: session.client,
        isActive: () => session.isActive,
        requiresTrust: session.persistedEndpoint != null,
        trusted: session.trusted,
        requiresManualSecretEntry: session.requiresManualSecretEntry,
        hasRequiredSecretMaterial: () => session.hasRequiredSecretMaterial(
          _store,
        ),
      ),
      discoveredTools: tools,
    );
  }

  String _nextLiveSourceId() {
    _liveSourceCounter += 1;
    return 'live-$_liveSourceCounter';
  }

  McpRuntimeEvent? _runtimeEventFromMessage(
    String sourceId,
    McpTransportMessage message,
  ) {
    if (message.event == 'endpoint') {
      return null;
    }
    final json = message.jsonRpcMessage;
    final rawMethod = json?['method'];
    final method = rawMethod is String ? rawMethod.trim() : '';
    final payload = <String, Object?>{
      if (message.data.trim().isNotEmpty) 'rawData': message.data.trim(),
      if (method.isNotEmpty) 'method': method,
    };
    final params = json?['params'];
    if (params is Map) {
      payload['params'] = Map<String, Object?>.from(params);
    }
    final eventName = method.isNotEmpty ? method : message.event;
    if (eventName.isEmpty) {
      return null;
    }
    return McpRuntimeEvent(
      sourceId: sourceId,
      eventName: eventName,
      payload: payload,
      receivedAt: DateTime.now().toUtc(),
      transportEvent: message.event,
    );
  }

  void _upsertState(McpConnectionState state) {
    final current = _connections.value;
    final updated = <McpConnectionState>[];
    var replaced = false;
    for (final entry in current) {
      final sameEndpoint =
          state.endpointId != null &&
          entry.endpointId != null &&
          state.endpointId == entry.endpointId;
      final sameUrl = entry.url == state.url;
      if (sameEndpoint || sameUrl) {
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
      await session.transport.messages
          .firstWhere((message) => message.event == 'endpoint')
          .timeout(timeout);
    } on TimeoutException {
      // Some servers will accept initialize without an explicit endpoint event.
    }
  }
}

class _McpConnectionSession {
  _McpConnectionSession({
    required this.sourceId,
    required this.runtimeUrl,
    required this.transport,
  }) : client = McpClient(transport);

  String sourceId;
  final String runtimeUrl;
  final McpTransport transport;
  final McpClient client;
  McpPersistedEndpoint? persistedEndpoint;
  bool trusted = false;
  bool requiresManualSecretEntry = false;
  bool isActive = true;
  StreamSubscription<McpTransportMessage>? messageSubscription;

  Future<bool> hasRequiredSecretMaterial(McpConnectionStore store) async {
    final endpoint = persistedEndpoint;
    if (endpoint == null || !endpoint.requiresSecret) {
      return true;
    }
    final runtimeUrl = await store.resolveRuntimeUrl(endpoint);
    return runtimeUrl != null && runtimeUrl.trim().isNotEmpty;
  }
}
