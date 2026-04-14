import 'dart:convert';

enum McpConnectorCredentialType {
  oauth2,
  pat,
  apiKey,
  longLivedToken,
  manualEndpoint,
}

class McpConnectorCredential {
  const McpConnectorCredential({
    required this.connectorId,
    required this.credentialType,
    required this.accessToken,
    required this.updatedAt,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const <String>[],
    this.baseUrl,
    this.runtimeUrl,
    this.authorizationUrl,
    this.tokenUrl,
    this.clientId,
  });

  factory McpConnectorCredential.fromJson(Map<String, Object?> json) {
    final rawScopes = json['scopes'];
    return McpConnectorCredential(
      connectorId: json['connectorId'] as String? ?? '',
      credentialType: McpConnectorCredentialType.values.firstWhere(
        (candidate) => candidate.name == (json['credentialType'] as String? ?? ''),
        orElse: () => McpConnectorCredentialType.manualEndpoint,
      ),
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      scopes: rawScopes is List
          ? rawScopes.whereType<String>().toList(growable: false)
          : const <String>[],
      baseUrl: json['baseUrl'] as String?,
      runtimeUrl: json['runtimeUrl'] as String?,
      authorizationUrl: json['authorizationUrl'] as String?,
      tokenUrl: json['tokenUrl'] as String?,
      clientId: json['clientId'] as String?,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String connectorId;
  final McpConnectorCredentialType credentialType;
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String> scopes;
  final String? baseUrl;
  final String? runtimeUrl;
  final String? authorizationUrl;
  final String? tokenUrl;
  final String? clientId;
  final DateTime updatedAt;

  bool get hasRefreshToken => refreshToken != null && refreshToken!.isNotEmpty;

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return !expiry.isAfter(DateTime.now().toUtc());
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'connectorId': connectorId,
      'credentialType': credentialType.name,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'scopes': scopes,
      'baseUrl': baseUrl,
      'runtimeUrl': runtimeUrl,
      'authorizationUrl': authorizationUrl,
      'tokenUrl': tokenUrl,
      'clientId': clientId,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  String encode() => jsonEncode(toJson());
}

class McpOAuthPendingSession {
  const McpOAuthPendingSession({
    required this.connectorId,
    required this.state,
    required this.codeVerifier,
    required this.authorizationUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.redirectUri,
    required this.createdAt,
    required this.expiresAt,
    required this.scopes,
    required this.runtimeUrl,
    required this.credentialType,
    this.refreshToken,
  });

  factory McpOAuthPendingSession.fromJson(Map<String, Object?> json) {
    final rawScopes = json['scopes'];
    return McpOAuthPendingSession(
      connectorId: json['connectorId'] as String? ?? '',
      state: json['state'] as String? ?? '',
      codeVerifier: json['codeVerifier'] as String? ?? '',
      authorizationUrl: json['authorizationUrl'] as String? ?? '',
      tokenUrl: json['tokenUrl'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      redirectUri: json['redirectUri'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      scopes: rawScopes is List
          ? rawScopes.whereType<String>().toList(growable: false)
          : const <String>[],
      runtimeUrl: json['runtimeUrl'] as String? ?? '',
      credentialType: McpConnectorCredentialType.values.firstWhere(
        (candidate) => candidate.name == (json['credentialType'] as String? ?? ''),
        orElse: () => McpConnectorCredentialType.oauth2,
      ),
      refreshToken: json['refreshToken'] as String?,
    );
  }

  final String connectorId;
  final String state;
  final String codeVerifier;
  final String authorizationUrl;
  final String tokenUrl;
  final String clientId;
  final String redirectUri;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> scopes;
  final String runtimeUrl;
  final McpConnectorCredentialType credentialType;
  final String? refreshToken;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'connectorId': connectorId,
      'state': state,
      'codeVerifier': codeVerifier,
      'authorizationUrl': authorizationUrl,
      'tokenUrl': tokenUrl,
      'clientId': clientId,
      'redirectUri': redirectUri,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'scopes': scopes,
      'runtimeUrl': runtimeUrl,
      'credentialType': credentialType.name,
      'refreshToken': refreshToken,
    };
  }

  String encode() => jsonEncode(toJson());
}

class McpOAuthTokenGrant {
  const McpOAuthTokenGrant({
    required this.accessToken,
    required this.updatedAt,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const <String>[],
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String> scopes;
  final DateTime updatedAt;
}

class McpConnectorRuntimeBootstrap {
  const McpConnectorRuntimeBootstrap({
    required this.runtimeUrl,
    required this.headers,
    required this.authMode,
    required this.connectorId,
  });

  final Uri runtimeUrl;
  final Map<String, String> headers;
  final String authMode;
  final String connectorId;
}
