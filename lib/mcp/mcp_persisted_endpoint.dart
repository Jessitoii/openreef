import 'dart:convert';

enum McpPersistedEndpointMigrationState {
  nativeTrusted,
  migratedLossless,
  manualReentryRequired;

  static McpPersistedEndpointMigrationState fromValue(String value) {
    return McpPersistedEndpointMigrationState.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => McpPersistedEndpointMigrationState.manualReentryRequired,
    );
  }
}

class McpQuerySegment {
  const McpQuerySegment({required this.index, required this.key, this.value});

  factory McpQuerySegment.fromJson(Map<String, Object?> json) {
    return McpQuerySegment(
      index: (json['index'] as num?)?.toInt() ?? 0,
      key: json['key'] as String? ?? '',
      value: json['value'] as String?,
    );
  }

  final int index;
  final String key;
  final String? value;

  Map<String, Object?> toJson() {
    return <String, Object?>{'index': index, 'key': key, 'value': value};
  }
}

class McpEndpointSecrets {
  const McpEndpointSecrets({
    this.userInfo,
    this.secretQuerySegments = const <McpQuerySegment>[],
  });

  factory McpEndpointSecrets.fromJson(Map<String, Object?> json) {
    final rawSegments = json['secretQuerySegments'];
    return McpEndpointSecrets(
      userInfo: json['userInfo'] as String?,
      secretQuerySegments: rawSegments is List
          ? rawSegments
                .whereType<Map>()
                .map(
                  (entry) =>
                      McpQuerySegment.fromJson(entry.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <McpQuerySegment>[],
    );
  }

  final String? userInfo;
  final List<McpQuerySegment> secretQuerySegments;

  bool get hasSecrets =>
      (userInfo != null && userInfo!.isNotEmpty) ||
      secretQuerySegments.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'userInfo': userInfo,
      'secretQuerySegments': secretQuerySegments
          .map((segment) => segment.toJson())
          .toList(growable: false),
    };
  }

  String encode() => jsonEncode(toJson());

  static McpEndpointSecrets decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const McpEndpointSecrets();
    }
    return McpEndpointSecrets.fromJson(decoded.cast<String, Object?>());
  }
}

class McpPersistedEndpoint {
  const McpPersistedEndpoint({
    required this.id,
    required this.scheme,
    required this.host,
    required this.path,
    required this.createdAt,
    required this.persistedAt,
    this.port,
    this.publicQuerySegments = const <McpQuerySegment>[],
    this.trusted = false,
    this.secretRef,
    this.requiresSecret = false,
    this.connectorId,
    this.credentialRef,
    this.credentialType,
    this.migrationState =
        McpPersistedEndpointMigrationState.manualReentryRequired,
  });

  factory McpPersistedEndpoint.fromJson(Map<String, Object?> json) {
    final rawSegments = json['publicQuerySegments'];
    return McpPersistedEndpoint(
      id: json['id'] as String? ?? '',
      scheme: json['scheme'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt(),
      path: json['path'] as String? ?? '',
      publicQuerySegments: rawSegments is List
          ? rawSegments
                .whereType<Map>()
                .map(
                  (entry) =>
                      McpQuerySegment.fromJson(entry.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <McpQuerySegment>[],
      trusted: json['trusted'] as bool? ?? false,
      secretRef: json['secretRef'] as String?,
      requiresSecret: json['requiresSecret'] as bool? ?? false,
      connectorId: json['connectorId'] as String?,
      credentialRef: json['credentialRef'] as String?,
      credentialType: json['credentialType'] as String?,
      migrationState: McpPersistedEndpointMigrationState.fromValue(
        json['migrationState'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      persistedAt:
          DateTime.tryParse(json['persistedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final String scheme;
  final String host;
  final int? port;
  final String path;
  final List<McpQuerySegment> publicQuerySegments;
  final bool trusted;
  final String? secretRef;
  final bool requiresSecret;
  final String? connectorId;
  final String? credentialRef;
  final String? credentialType;
  final McpPersistedEndpointMigrationState migrationState;
  final DateTime createdAt;
  final DateTime persistedAt;

  bool get canAutoConnect =>
      trusted &&
      migrationState !=
          McpPersistedEndpointMigrationState.manualReentryRequired;

  bool get requiresManualSecretEntry =>
      migrationState ==
          McpPersistedEndpointMigrationState.manualReentryRequired ||
      (requiresSecret && (secretRef == null || secretRef!.isEmpty));

  String get storageKey => 'mcp_connection:$id';

  String get displayUri => _buildUri(publicQuerySegments);

  String buildRuntimeUri({McpEndpointSecrets? secrets}) {
    final mergedSegments = <McpQuerySegment>[
      ...publicQuerySegments,
      ...?secrets?.secretQuerySegments,
    ]..sort((left, right) => left.index.compareTo(right.index));
    return _buildUri(mergedSegments, userInfo: secrets?.userInfo);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': 2,
      'id': id,
      'scheme': scheme,
      'host': host,
      'port': port,
      'path': path,
      'publicQuerySegments': publicQuerySegments
          .map((segment) => segment.toJson())
          .toList(growable: false),
      'trusted': trusted,
      'secretRef': secretRef,
      'requiresSecret': requiresSecret,
      'connectorId': connectorId,
      'credentialRef': credentialRef,
      'credentialType': credentialType,
      'migrationState': migrationState.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'persistedAt': persistedAt.toUtc().toIso8601String(),
    };
  }

  String encode() => jsonEncode(toJson());

  String _buildUri(List<McpQuerySegment> querySegments, {String? userInfo}) {
    final buffer = StringBuffer()..write('$scheme://');
    if (userInfo != null && userInfo.isNotEmpty) {
      buffer
        ..write(userInfo)
        ..write('@');
    }
    buffer.write(host);
    if (port != null) {
      buffer
        ..write(':')
        ..write(port);
    }
    if (path.isNotEmpty) {
      buffer.write(path);
    }
    if (querySegments.isNotEmpty) {
      buffer.write('?');
      for (var index = 0; index < querySegments.length; index++) {
        final segment = querySegments[index];
        if (index > 0) {
          buffer.write('&');
        }
        buffer.write(Uri.encodeQueryComponent(segment.key));
        if (segment.value != null) {
          buffer
            ..write('=')
            ..write(Uri.encodeQueryComponent(segment.value!));
        }
      }
    }
    return buffer.toString();
  }
}
