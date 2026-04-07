import 'dart:math';

import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';

class McpEndpointNormalizationResult {
  const McpEndpointNormalizationResult({
    required this.endpoint,
    required this.secrets,
    required this.isLossless,
  });

  final McpPersistedEndpoint endpoint;
  final McpEndpointSecrets secrets;
  final bool isLossless;
}

class McpEndpointPolicy {
  static const Set<String> _allowedSchemes = <String>{'https'};
  static final RegExp _secretKeyPattern = RegExp(
    r'(token|secret|password|passwd|authorization|auth|bearer|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|pat)',
    caseSensitive: false,
  );

  static Uri validatePersistedUri(String rawUrl) {
    final uri = Uri.parse(rawUrl.trim());
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      throw const McpTransportException('unsafe_endpoint_scheme');
    }
    if (!uri.hasAuthority || uri.host.trim().isEmpty) {
      throw const McpTransportException('invalid_endpoint_host');
    }
    return uri;
  }

  static McpEndpointNormalizationResult normalizeForPersistence({
    required String id,
    required String rawUrl,
    required bool trusted,
    required McpPersistedEndpointMigrationState migrationState,
    required DateTime createdAt,
    required DateTime persistedAt,
  }) {
    final trimmed = rawUrl.trim();
    final uri = validatePersistedUri(trimmed);
    final querySegments = parseQuerySegments(uri.query);
    final publicSegments = <McpQuerySegment>[];
    final secretSegments = <McpQuerySegment>[];
    for (final segment in querySegments) {
      if (isSecretQueryKey(segment.key)) {
        secretSegments.add(segment);
      } else {
        publicSegments.add(segment);
      }
    }

    final secrets = McpEndpointSecrets(
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      secretQuerySegments: secretSegments,
    );
    final endpoint = McpPersistedEndpoint(
      id: id,
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      publicQuerySegments: publicSegments,
      trusted: trusted,
      secretRef: secrets.hasSecrets ? id : null,
      requiresSecret: secrets.hasSecrets,
      migrationState: migrationState,
      createdAt: createdAt,
      persistedAt: persistedAt,
    );
    final originalWithoutFragment = stripFragment(trimmed);
    final rebuilt = endpoint.buildRuntimeUri(secrets: secrets);
    return McpEndpointNormalizationResult(
      endpoint: endpoint,
      secrets: secrets,
      isLossless: rebuilt == originalWithoutFragment,
    );
  }

  static List<McpQuerySegment> parseQuerySegments(String rawQuery) {
    if (rawQuery.isEmpty) {
      return const <McpQuerySegment>[];
    }
    final pairs = rawQuery.split('&');
    final segments = <McpQuerySegment>[];
    for (var index = 0; index < pairs.length; index++) {
      final pair = pairs[index];
      if (pair.isEmpty) {
        continue;
      }
      final separator = pair.indexOf('=');
      if (separator == -1) {
        segments.add(
          McpQuerySegment(index: index, key: Uri.decodeQueryComponent(pair)),
        );
        continue;
      }
      segments.add(
        McpQuerySegment(
          index: index,
          key: Uri.decodeQueryComponent(pair.substring(0, separator)),
          value: Uri.decodeQueryComponent(pair.substring(separator + 1)),
        ),
      );
    }
    return List<McpQuerySegment>.unmodifiable(segments);
  }

  static bool isSecretQueryKey(String key) {
    return _secretKeyPattern.hasMatch(key);
  }

  static void validateNegotiatedPostEndpoint({
    required Uri sseEndpoint,
    required Uri postEndpoint,
  }) {
    if (!postEndpoint.hasAuthority || postEndpoint.host.trim().isEmpty) {
      throw const McpTransportException('invalid_negotiated_post_endpoint');
    }
    final sseScheme = sseEndpoint.scheme.toLowerCase();
    final postScheme = postEndpoint.scheme.toLowerCase();
    if (sseScheme == 'https' && postScheme != 'https') {
      throw const McpTransportException('unsafe_negotiated_post_endpoint');
    }
    if (sseScheme != postScheme) {
      throw const McpTransportException('mismatched_negotiated_scheme');
    }
    if (!_sameOrigin(sseEndpoint, postEndpoint)) {
      throw const McpTransportException(
        'cross_origin_negotiated_post_endpoint',
      );
    }
  }

  static String stripFragment(String rawUrl) {
    final hashIndex = rawUrl.indexOf('#');
    if (hashIndex == -1) {
      return rawUrl;
    }
    return rawUrl.substring(0, hashIndex);
  }

  static String generateStableId({Random? random}) {
    final value = (random ?? Random.secure()).nextInt(1 << 32);
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'mcp_${micros.toRadixString(16)}_${value.toRadixString(16)}';
  }

  static bool _sameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        _effectivePort(left) == _effectivePort(right);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme.toLowerCase()) {
      'https' => 443,
      'http' => 80,
      _ => -1,
    };
  }
}
