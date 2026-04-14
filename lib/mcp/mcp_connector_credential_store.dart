import 'dart:convert';

import 'package:openreef/mcp/mcp_auth_models.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';

abstract class ConnectorCredentialStore {
  Future<void> writeCredential(McpConnectorCredential credential);

  Future<McpConnectorCredential?> readCredential(String connectorId);

  Future<void> deleteCredential(String connectorId);

  Future<void> writePendingSession(McpOAuthPendingSession session);

  Future<McpOAuthPendingSession?> readPendingSession(String state);

  Future<void> deletePendingSession(String state);
}

class SecureConnectorCredentialStore implements ConnectorCredentialStore {
  SecureConnectorCredentialStore(this._secretStore);

  final McpSecretStore _secretStore;

  static String credentialKey(String connectorId) =>
      'mcp_credential_$connectorId';

  static String pendingSessionKey(String state) => 'mcp_oauth_session_$state';

  @override
  Future<void> writeCredential(McpConnectorCredential credential) async {
    await _secretStore.writeSecret(
      credentialKey(credential.connectorId),
      credential.encode(),
    );
  }

  @override
  Future<McpConnectorCredential?> readCredential(String connectorId) async {
    final raw = await _secretStore.readSecret(credentialKey(connectorId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return McpConnectorCredential.fromJson(
        Map<String, Object?>.from(_decodeJson(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteCredential(String connectorId) async {
    await _secretStore.deleteSecret(credentialKey(connectorId));
  }

  @override
  Future<void> writePendingSession(McpOAuthPendingSession session) async {
    await _secretStore.writeSecret(
      pendingSessionKey(session.state),
      session.encode(),
    );
  }

  @override
  Future<McpOAuthPendingSession?> readPendingSession(String state) async {
    final raw = await _secretStore.readSecret(pendingSessionKey(state));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return McpOAuthPendingSession.fromJson(
        Map<String, Object?>.from(_decodeJson(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deletePendingSession(String state) async {
    await _secretStore.deleteSecret(pendingSessionKey(state));
  }

  Map<String, Object?> _decodeJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    return <String, Object?>{};
  }
}
