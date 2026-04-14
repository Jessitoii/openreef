import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_auth_models.dart';
import 'package:openreef/mcp/mcp_connector_bootstrapper.dart';
import 'package:openreef/mcp/mcp_connector_credential_store.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_endpoint_policy.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_oauth_bridge.dart';
import 'package:openreef/mcp/mcp_oauth_service.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/mcp/mcp_sse_transport.dart';
import 'package:openreef/mcp/mcp_transport.dart';

typedef McpTransportFactory = McpTransport Function(
  Uri endpoint, {
  Map<String, String> headers,
  McpHeadersProvider? headersProvider,
});

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
    this.enabled = true,
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
  final bool enabled;

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
    bool? enabled,
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
      enabled: enabled ?? this.enabled,
    );
  }
}

class McpConnectionsController {
  McpConnectionsController({
    required McpConnectionStore store,
    required McpRuntimeCoordinator runtimeCoordinator,
    required McpSecretStore secretStore,
    McpClientInfo clientInfo = const McpClientInfo(
      name: 'OpenReef',
      version: '1.0.0+1',
    ),
    bool autoConnectPersisted = true,
    McpTransportFactory? transportFactory,
    ConnectorBootstrapper? bootstrapper,
    McpOAuthService? oauthService,
  }) : _store = store,
       _runtimeCoordinator = runtimeCoordinator,
       _credentialStore = SecureConnectorCredentialStore(secretStore),
       _clientInfo = clientInfo,
       _autoConnectPersisted = autoConnectPersisted,
       _bootstrapper = bootstrapper ?? PresetConnectorBootstrapper(),
       _oauthService =
           oauthService ??
           McpOAuthService(
             credentialStore: SecureConnectorCredentialStore(secretStore),
           ),
       _transportFactory =
           transportFactory ??
           ((endpoint, {headers = const <String, String>{}, headersProvider}) =>
               McpSseTransport(
                 sseEndpoint: endpoint,
                 headers: headers,
                 headersProvider: headersProvider,
               ));

  final McpConnectionStore _store;
  final McpRuntimeCoordinator _runtimeCoordinator;
  final ConnectorCredentialStore _credentialStore;
  final McpClientInfo _clientInfo;
  final bool _autoConnectPersisted;
  final ConnectorBootstrapper _bootstrapper;
  final McpOAuthService _oauthService;
  final McpTransportFactory _transportFactory;
  final ValueNotifier<List<McpConnectionState>> _connections =
      ValueNotifier<List<McpConnectionState>>(const <McpConnectionState>[]);
  final Map<String, _McpConnectionSession> _sessions =
      <String, _McpConnectionSession>{};
  final Map<String, McpPersistedEndpoint> _persistedEndpoints =
      <String, McpPersistedEndpoint>{};
  final Map<String, bool> _enabledBySourceId = <String, bool>{};
  final Map<String, String> _liveSourceIdsByRuntimeUrl = <String, String>{};
  final Map<String, _McpOAuthPendingFlow> _pendingOAuthFlows =
      <String, _McpOAuthPendingFlow>{};
  StreamSubscription<McpOAuthCallbackPayload>? _oauthCallbackSubscription;
  bool _initialized = false;
  bool _oauthBridgeInitialized = false;
  int _liveSourceCounter = 0;

  ValueListenable<List<McpConnectionState>> get connections => _connections;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _ensureOAuthBridge();
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
          enabled: _enabledBySourceId[endpoint.id] ?? true,
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

  Future<void> _ensureOAuthBridge() async {
    if (_oauthBridgeInitialized) {
      return;
    }
    await McpOAuthBridge.instance.initialize();
    _oauthCallbackSubscription = McpOAuthBridge.instance.callbacks.listen(
      (payload) async {
        try {
          await handleOAuthCallback(payload.uri);
        } catch (error) {
          debugPrint('[MCP] oauth callback handling failed: $error');
        }
      },
    );
    _oauthBridgeInitialized = true;
  }

  void dispose() {
    unawaited(_oauthCallbackSubscription?.cancel());
    _oauthCallbackSubscription = null;
    for (final session in _sessions.values) {
      session.isActive = false;
      unawaited(session.messageSubscription?.cancel());
      unawaited(session.client.close());
    }
    _sessions.clear();
  }

  Future<void> connect(String url, {required bool persist}) async {
    debugPrint('[MCP] connect(url=$url, persist=$persist)');
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

  Future<void> connectManualEndpoint(String url, {bool persist = true}) {
    debugPrint('[MCP] connectManualEndpoint(url=$url, persist=$persist)');
    return connect(url, persist: persist);
  }

  Future<void> connectWithBaseUrlToken({
    required String connectorId,
    required String baseUrl,
    required String token,
    bool persist = true,
  }) async {
    debugPrint(
      '[MCP] connectWithBaseUrlToken(connectorId=$connectorId, baseUrl=$baseUrl, persist=$persist)',
    );
    final trimmedBaseUrl = baseUrl.trim();
    final trimmedToken = token.trim();
    if (trimmedBaseUrl.isEmpty || trimmedToken.isEmpty) {
      throw ArgumentError('baseUrl_and_token_required');
    }
    final runtimeUrl = _homeAssistantRuntimeUrl(trimmedBaseUrl);
    final credential = McpConnectorCredential(
      connectorId: connectorId,
      credentialType: McpConnectorCredentialType.longLivedToken,
      accessToken: trimmedToken,
      baseUrl: trimmedBaseUrl,
      runtimeUrl: runtimeUrl.toString(),
      updatedAt: DateTime.now().toUtc(),
    );
    if (persist) {
      await _credentialStore.writeCredential(credential);
      final endpoint = await _store.saveConnectorEndpoint(
        connectorId: connectorId,
        runtimeUrl: runtimeUrl.toString(),
        trusted: true,
        credentialRef: SecureConnectorCredentialStore.credentialKey(
          connectorId,
        ),
        credentialType: credential.credentialType.name,
      );
      _persistedEndpoints[endpoint.id] = endpoint;
      await _connectProviderEndpoint(
        endpoint: endpoint,
        credential: credential,
        persistAfterConnect: false,
      );
      return;
    }
    await _connectProviderRuntime(
      connectorId: connectorId,
      credential: credential,
      runtimeUrl: runtimeUrl,
      displayUrl: runtimeUrl.toString(),
      persistAfterConnect: false,
      trusted: false,
    );
  }

  Future<void> connectWithToken({
    required String connectorId,
    required String token,
    bool persist = true,
  }) async {
    debugPrint('[MCP] connectWithToken(connectorId=$connectorId, token=***redacted***)');
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError('token_required');
    }
    final runtimeUrl = _runtimeUrlForConnector(connectorId);
    final credential = McpConnectorCredential(
      connectorId: connectorId,
      credentialType: McpConnectorCredentialType.pat,
      accessToken: trimmedToken,
      runtimeUrl: runtimeUrl.toString(),
      updatedAt: DateTime.now().toUtc(),
    );
    if (persist) {
      await _credentialStore.writeCredential(credential);
      final endpoint = await _store.saveConnectorEndpoint(
        connectorId: connectorId,
        runtimeUrl: runtimeUrl.toString(),
        trusted: true,
        credentialRef: SecureConnectorCredentialStore.credentialKey(
          connectorId,
        ),
        credentialType: credential.credentialType.name,
      );
      _persistedEndpoints[endpoint.id] = endpoint;
      await _connectProviderEndpoint(
        endpoint: endpoint,
        credential: credential,
        persistAfterConnect: false,
      );
      return;
    }
    await _connectProviderRuntime(
      connectorId: connectorId,
      credential: credential,
      runtimeUrl: runtimeUrl,
      displayUrl: runtimeUrl.toString(),
      persistAfterConnect: false,
      trusted: false,
    );
  }

  Future<String?> startOAuth(String connectorId) async {
    debugPrint('[MCP] startOAuth(connectorId=$connectorId)');
    final oauthConfig = _oauthConfigForConnector(connectorId);
    if (oauthConfig == null) {
      _upsertState(
        McpConnectionState(
          url: connectorId,
          status: McpConnectionStatus.error,
          errorMessage: 'oauth_not_configured',
          persisted: false,
          endpointId: null,
          trusted: false,
          requiresManualSecretEntry: false,
          runtimeSourceId: connectorId,
          importedToolIds: const <String>[],
          enabled: true,
        ),
      );
      throw UnsupportedError('oauth_not_configured:$connectorId');
    }
    final session = await _oauthService.startAuthorization(
      connectorId: connectorId,
      authorizationUrl: oauthConfig.authorizationUrl,
      tokenUrl: oauthConfig.tokenUrl,
      clientId: oauthConfig.clientId,
      redirectUri: oauthConfig.redirectUri,
      runtimeUrl: oauthConfig.runtimeUrl,
      credentialType: oauthConfig.credentialType,
      scopes: oauthConfig.scopes,
    );
    _pendingOAuthFlows[session.state] = _McpOAuthPendingFlow(
      connectorId: connectorId,
      session: session,
    );
    _upsertState(
      McpConnectionState(
        url: oauthConfig.runtimeUrl.toString(),
        status: McpConnectionStatus.connecting,
        persisted: false,
        endpointId: null,
        trusted: false,
        requiresManualSecretEntry: false,
        runtimeSourceId: connectorId,
        importedToolIds: const <String>[],
        enabled: true,
      ),
    );
    return session.authorizationUrl;
  }

  Future<void> handleOAuthCallback(Uri callbackUri) async {
    debugPrint('[MCP] handleOAuthCallback(uri=$callbackUri)');
    final code = callbackUri.queryParameters['code'];
    final state = callbackUri.queryParameters['state'];
    if (code == null || state == null || code.trim().isEmpty || state.trim().isEmpty) {
      throw ArgumentError('oauth_callback_missing_code_or_state');
    }
    final flow = _pendingOAuthFlows.remove(state);
    if (flow == null) {
      throw StateError('oauth_state_mismatch');
    }
    if (flow.session.isExpired) {
      await _credentialStore.deletePendingSession(state);
      _upsertState(
        McpConnectionState(
          url: flow.session.runtimeUrl,
          status: McpConnectionStatus.error,
          errorMessage: 'expired_session',
          persisted: false,
          endpointId: null,
          trusted: false,
          requiresManualSecretEntry: false,
          runtimeSourceId: flow.connectorId,
          importedToolIds: const <String>[],
          enabled: true,
        ),
      );
      throw StateError('oauth_session_expired');
    }
    final pendingSession = await _credentialStore.readPendingSession(state);
    if (pendingSession == null || pendingSession.state != state) {
      _upsertState(
        McpConnectionState(
          url: flow.session.runtimeUrl,
          status: McpConnectionStatus.error,
          errorMessage: 'oauth_session_missing',
          persisted: false,
          endpointId: null,
          trusted: false,
          requiresManualSecretEntry: false,
          runtimeSourceId: flow.connectorId,
          importedToolIds: const <String>[],
          enabled: true,
        ),
      );
      throw StateError('oauth_session_missing');
    }
    late final McpOAuthTokenGrant tokenGrant;
    try {
      tokenGrant = await _oauthService.exchangeCodeForToken(
        code: code,
        codeVerifier: pendingSession.codeVerifier,
        tokenUrl: Uri.parse(pendingSession.tokenUrl),
        clientId: pendingSession.clientId,
        redirectUri: Uri.parse(pendingSession.redirectUri),
        scopes: pendingSession.scopes,
      );
    } catch (error) {
      _upsertState(
        McpConnectionState(
          url: pendingSession.runtimeUrl,
          status: McpConnectionStatus.error,
          errorMessage: error is McpOAuthException
              ? error.code
              : error.toString(),
          persisted: false,
          endpointId: null,
          trusted: false,
          requiresManualSecretEntry: false,
          runtimeSourceId: pendingSession.connectorId,
          importedToolIds: const <String>[],
          enabled: true,
        ),
      );
      rethrow;
    }
    await _credentialStore.deletePendingSession(state);
    final credential = McpConnectorCredential(
      connectorId: pendingSession.connectorId,
      credentialType: pendingSession.credentialType,
      accessToken: tokenGrant.accessToken,
      refreshToken: tokenGrant.refreshToken ?? pendingSession.refreshToken,
      expiresAt: tokenGrant.expiresAt,
      scopes: tokenGrant.scopes.isNotEmpty ? tokenGrant.scopes : pendingSession.scopes,
      runtimeUrl: pendingSession.runtimeUrl,
      authorizationUrl: pendingSession.authorizationUrl,
      tokenUrl: pendingSession.tokenUrl,
      clientId: pendingSession.clientId,
      updatedAt: tokenGrant.updatedAt,
    );
    await _credentialStore.writeCredential(credential);
    final runtimeUrl = Uri.parse(pendingSession.runtimeUrl);
    final endpoint = await _store.saveConnectorEndpoint(
      connectorId: pendingSession.connectorId,
      runtimeUrl: runtimeUrl.toString(),
      trusted: true,
      credentialRef: SecureConnectorCredentialStore.credentialKey(
        pendingSession.connectorId,
      ),
      credentialType: credential.credentialType.name,
    );
    _persistedEndpoints[endpoint.id] = endpoint;
    await _connectProviderEndpoint(
      endpoint: endpoint,
      credential: credential,
      persistAfterConnect: false,
    );
  }

  Future<void> reconnectPersisted(String endpointId) async {
    final endpoint = _persistedEndpoints[endpointId];
    if (endpoint == null) {
      return;
    }
    if (endpoint.connectorId != null) {
      final credential = await _credentialStore.readCredential(endpoint.connectorId!);
      if (credential == null) {
        _upsertState(
          McpConnectionState(
            url: endpoint.displayUri,
            status: McpConnectionStatus.error,
            errorMessage: 'missing_credential',
            persisted: true,
            endpointId: endpoint.id,
            trusted: endpoint.trusted,
            requiresManualSecretEntry: false,
            runtimeSourceId: endpoint.id,
            importedToolIds: const <String>[],
            enabled: false,
          ),
        );
        return;
      }
      final refreshed = await ensureValidToken(endpoint.connectorId!);
      if (refreshed == null) {
        _upsertState(
          McpConnectionState(
            url: endpoint.displayUri,
            status: McpConnectionStatus.error,
            errorMessage: credential.isExpired ? 'expired_token' : 'auth_error',
            persisted: true,
            endpointId: endpoint.id,
            trusted: endpoint.trusted,
            requiresManualSecretEntry: false,
            runtimeSourceId: endpoint.id,
            importedToolIds: const <String>[],
            enabled: false,
          ),
        );
        return;
      }
      await _connectProviderEndpoint(
        endpoint: endpoint,
        credential: refreshed,
        persistAfterConnect: false,
      );
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
          enabled: false,
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
          enabled: false,
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
        enabled: current?.enabled ?? true,
      ),
    );
  }

  Future<void> setEnabled(String urlOrId, bool enabled) async {
    final current = _findState(urlOrId);
    final sourceId = current?.runtimeSourceId ?? current?.endpointId ?? urlOrId;
    _enabledBySourceId[sourceId] = enabled;
    if (!enabled) {
      _runtimeCoordinator.removeSource(sourceId);
      _upsertState(
        (current ??
                McpConnectionState(
                  url: urlOrId.trim(),
                  status: McpConnectionStatus.disconnected,
                ))
            .copyWith(enabled: false, importedToolIds: const <String>[]),
      );
      return;
    }
    if (current == null) {
      return;
    }
    _upsertState(current.copyWith(enabled: true));
    if (current.connected) {
      await refresh(current.url);
    }
  }

  Future<void> forgetPersisted(String endpointId) async {
    final endpoint = _persistedEndpoints.remove(endpointId);
    if (endpoint == null) {
      return;
    }
    if (endpoint.connectorId != null) {
      await _credentialStore.deleteCredential(endpoint.connectorId!);
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
              enabled: current?.enabled ?? true,
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
          enabled: current?.enabled ?? true,
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
    Map<String, String> headers = const <String, String>{},
    McpHeadersProvider? headersProvider,
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
        enabled: _enabledBySourceId[provisionalSourceId] ?? true,
      ),
    );

    final transport = _transportFactory(
      Uri.parse(runtimeUrl),
      headers: headers,
      headersProvider: headersProvider,
    );
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
          enabled: _enabledBySourceId[sourceId] ?? true,
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
          enabled: _enabledBySourceId[provisionalSourceId] ?? true,
        ),
      );
    }
  }

  Future<void> _connectProviderEndpoint({
    required McpPersistedEndpoint endpoint,
    required McpConnectorCredential credential,
    required bool persistAfterConnect,
    McpConnectorRuntimeBootstrap? bootstrapOverride,
  }) async {
    final bootstrap = bootstrapOverride ??
        await _bootstrapper.bootstrap(
          connectorId: endpoint.connectorId!,
          credential: credential,
        );
    await _connectRuntime(
      runtimeUrl: bootstrap.runtimeUrl.toString(),
      displayUrl: endpoint.displayUri,
      persistAfterConnect: persistAfterConnect,
      persistedEndpoint: endpoint,
      trusted: endpoint.trusted,
      requiresManualSecretEntry: false,
      headers: bootstrap.headers,
    );
  }

  Future<void> _connectProviderRuntime({
    required String connectorId,
    required McpConnectorCredential credential,
    required Uri runtimeUrl,
    required String displayUrl,
    required bool persistAfterConnect,
    required bool trusted,
    McpConnectorRuntimeBootstrap? bootstrapOverride,
  }) async {
    final bootstrap = bootstrapOverride ??
        await _bootstrapper.bootstrap(
          connectorId: connectorId,
          credential: credential,
        );
    await _connectRuntime(
      runtimeUrl: runtimeUrl.toString(),
      displayUrl: displayUrl,
      persistAfterConnect: persistAfterConnect,
      trusted: trusted,
      requiresManualSecretEntry: false,
      headers: bootstrap.headers,
    );
  }

  Future<McpConnectorCredential?> ensureValidToken(String connectorId) async {
    final credential = await _credentialStore.readCredential(connectorId);
    if (credential == null) {
      return null;
    }
    if (!credential.isExpired) {
      return credential;
    }
    if (!credential.hasRefreshToken) {
      return null;
    }
    final tokenUrl = credential.tokenUrl != null && credential.tokenUrl!.isNotEmpty
        ? Uri.parse(credential.tokenUrl!)
        : _oauthConfigForConnector(connectorId)?.tokenUrl;
    final clientId = credential.clientId?.trim().isNotEmpty == true
        ? credential.clientId!.trim()
        : _oauthConfigForConnector(connectorId)?.clientId;
    if (tokenUrl == null || clientId == null || clientId.isEmpty) {
      return null;
    }
    try {
      final refreshed = await _oauthService.refreshAccessToken(
        refreshToken: credential.refreshToken!,
        tokenUrl: tokenUrl,
        clientId: clientId,
        scopes: credential.scopes,
      );
      final updated = McpConnectorCredential(
        connectorId: credential.connectorId,
        credentialType: credential.credentialType,
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken ?? credential.refreshToken,
        expiresAt: refreshed.expiresAt,
        scopes: refreshed.scopes.isNotEmpty ? refreshed.scopes : credential.scopes,
        baseUrl: credential.baseUrl,
        runtimeUrl: credential.runtimeUrl,
        authorizationUrl: credential.authorizationUrl,
        tokenUrl: credential.tokenUrl,
        clientId: credential.clientId,
        updatedAt: refreshed.updatedAt,
      );
      await _credentialStore.writeCredential(updated);
      return updated;
    } catch (error) {
      debugPrint('[MCP] ensureValidToken refresh failed for $connectorId: $error');
      await _credentialStore.deleteCredential(connectorId);
      return null;
    }
  }

  _OAuthConnectorConfig? _oauthConfigForConnector(String connectorId) {
    switch (connectorId) {
      case 'github':
        final clientId = const String.fromEnvironment(
          'OPENREEF_GITHUB_OAUTH_CLIENT_ID',
          defaultValue: '',
        );
        if (clientId.trim().isEmpty) {
          return null;
        }
        return _OAuthConnectorConfig(
          authorizationUrl: Uri.parse('https://github.com/login/oauth/authorize'),
          tokenUrl: Uri.parse('https://github.com/login/oauth/access_token'),
          clientId: clientId.trim(),
          redirectUri: Uri.parse('openreef://oauth/callback'),
          runtimeUrl: Uri.parse(
            'https://api.githubcopilot.com/mcp/',
          ),
          credentialType: McpConnectorCredentialType.oauth2,
          scopes: const <String>['read:user', 'repo'],
        );
      default:
        return null;
    }
  }

  Uri _runtimeUrlForConnector(String connectorId) {
    switch (connectorId) {
      case 'github':
        return Uri.parse('https://api.githubcopilot.com/mcp/');
      case 'home_assistant':
        throw ArgumentError('home_assistant_requires_base_url');
      default:
        throw UnsupportedError('connector_runtime_not_configured:$connectorId');
    }
  }

  Uri _homeAssistantRuntimeUrl(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$normalized/api/mcp');
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

class _McpOAuthPendingFlow {
  const _McpOAuthPendingFlow({
    required this.connectorId,
    required this.session,
  });

  final String connectorId;
  final McpOAuthPendingSession session;
}

class _OAuthConnectorConfig {
  const _OAuthConnectorConfig({
    required this.authorizationUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.redirectUri,
    required this.runtimeUrl,
    required this.credentialType,
    required this.scopes,
  });

  final Uri authorizationUrl;
  final Uri tokenUrl;
  final String clientId;
  final Uri redirectUri;
  final Uri runtimeUrl;
  final McpConnectorCredentialType credentialType;
  final List<String> scopes;
}
