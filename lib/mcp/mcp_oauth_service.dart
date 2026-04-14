import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:openreef/mcp/mcp_auth_models.dart';
import 'package:openreef/mcp/mcp_connector_credential_store.dart';

class McpOAuthService {
  McpOAuthService({
    required ConnectorCredentialStore credentialStore,
    HttpClient? httpClient,
    DateTime Function()? clock,
    Random? random,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient ?? HttpClient(),
       _clock = clock ?? _defaultClock,
       _random = random ?? Random.secure();

  final ConnectorCredentialStore _credentialStore;
  final HttpClient _httpClient;
  final DateTime Function() _clock;
  final Random _random;

  Future<McpOAuthPendingSession> startAuthorization({
    required String connectorId,
    required Uri authorizationUrl,
    required Uri tokenUrl,
    required String clientId,
    required Uri redirectUri,
    required Uri runtimeUrl,
    required McpConnectorCredentialType credentialType,
    List<String> scopes = const <String>[],
    Duration sessionTtl = const Duration(minutes: 10),
  }) async {
    final codeVerifier = _generateCodeVerifier();
    final state = _generateState();
    final challenge = _generateCodeChallenge(codeVerifier);
    final now = _clock().toUtc();
    final session = McpOAuthPendingSession(
      connectorId: connectorId,
      state: state,
      codeVerifier: codeVerifier,
      authorizationUrl: _buildAuthorizationUrl(
        authorizationUrl: authorizationUrl,
        clientId: clientId,
        redirectUri: redirectUri,
        state: state,
        scopes: scopes,
        codeChallenge: challenge,
      ).toString(),
      tokenUrl: tokenUrl.toString(),
      clientId: clientId,
      redirectUri: redirectUri.toString(),
      createdAt: now,
      expiresAt: now.add(sessionTtl),
      scopes: scopes,
      runtimeUrl: runtimeUrl.toString(),
      credentialType: credentialType,
    );
    await _credentialStore.writePendingSession(session);
    return session;
  }

  Uri _buildAuthorizationUrl({
    required Uri authorizationUrl,
    required String clientId,
    required Uri redirectUri,
    required String state,
    required List<String> scopes,
    required String codeChallenge,
  }) {
    final queryParameters = <String, String>{
      ...authorizationUrl.queryParameters,
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      if (scopes.isNotEmpty) 'scope': scopes.join(' '),
    };
    return authorizationUrl.replace(queryParameters: queryParameters);
  }

  Future<McpOAuthTokenGrant> exchangeCodeForToken({
    required String code,
    required String codeVerifier,
    required Uri tokenUrl,
    required String clientId,
    required Uri redirectUri,
    List<String> scopes = const <String>[],
  }) async {
    return _tokenRequest(
      tokenUrl: tokenUrl,
      form: <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': codeVerifier,
        'client_id': clientId,
        'redirect_uri': redirectUri.toString(),
        if (scopes.isNotEmpty) 'scope': scopes.join(' '),
      },
    );
  }

  Future<McpOAuthTokenGrant> refreshAccessToken({
    required String refreshToken,
    required Uri tokenUrl,
    required String clientId,
    List<String> scopes = const <String>[],
  }) async {
    return _tokenRequest(
      tokenUrl: tokenUrl,
      form: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        if (scopes.isNotEmpty) 'scope': scopes.join(' '),
      },
    );
  }

  Future<McpOAuthTokenGrant> _tokenRequest({
    required Uri tokenUrl,
    required Map<String, String> form,
  }) async {
    final request = await _httpClient.postUrl(tokenUrl);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.write(Uri(queryParameters: form).query);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.ok) {
      throw McpOAuthException('token_exchange_error');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw McpOAuthException('malformed_token_response');
    }
    if (decoded is! Map) {
      throw McpOAuthException('malformed_token_response');
    }
    final map = decoded.cast<String, Object?>();
    if (map['error'] != null) {
      throw McpOAuthException('provider_error:${map['error']}');
    }
    final accessToken = map['access_token'] as String?;
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw McpOAuthException('missing_access_token');
    }
    final refreshToken = map['refresh_token'] as String?;
    final expiresIn = map['expires_in'];
    final expiresAt = expiresIn is num
        ? _clock().toUtc().add(Duration(seconds: expiresIn.toInt()))
        : null;
    final scopeValue = map['scope'];
    final grantedScopes = scopeValue is String && scopeValue.isNotEmpty
        ? scopeValue.split(RegExp(r'\s+')).where((scope) => scope.isNotEmpty).toList(growable: false)
        : const <String>[];
    return McpOAuthTokenGrant(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      scopes: grantedScopes,
      updatedAt: _clock().toUtc(),
    );
  }

  String _generateState() {
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateCodeVerifier() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static DateTime _defaultClock() => DateTime.now().toUtc();
}

class McpOAuthException implements Exception {
  const McpOAuthException(this.code);

  final String code;

  @override
  String toString() => 'McpOAuthException: $code';
}
