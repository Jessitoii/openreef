import 'package:openreef/mcp/mcp_auth_models.dart';

abstract class ConnectorBootstrapper {
  Future<McpConnectorRuntimeBootstrap> bootstrap({
    required String connectorId,
    required McpConnectorCredential credential,
  });
}

class PresetConnectorBootstrapper implements ConnectorBootstrapper {
  @override
  Future<McpConnectorRuntimeBootstrap> bootstrap({
    required String connectorId,
    required McpConnectorCredential credential,
  }) async {
    final runtimeUrl = _resolveRuntimeUrl(
      connectorId: connectorId,
      credential: credential,
    );
    final headers = <String, String>{
      if (credential.accessToken.isNotEmpty)
        'Authorization': 'Bearer ${credential.accessToken}',
    };
    return McpConnectorRuntimeBootstrap(
      runtimeUrl: runtimeUrl,
      headers: headers,
      authMode: credential.credentialType.name,
      connectorId: connectorId,
    );
  }

  Uri _resolveRuntimeUrl({
    required String connectorId,
    required McpConnectorCredential credential,
  }) {
    switch (connectorId) {
      case 'github':
        return Uri.parse(
          credential.runtimeUrl?.trim().isNotEmpty == true
              ? credential.runtimeUrl!.trim()
              : 'https://api.githubcopilot.com/mcp/',
        );
      case 'home_assistant':
        final baseUrl = credential.baseUrl?.trim();
        if (baseUrl == null || baseUrl.isEmpty) {
          final runtimeUrl = credential.runtimeUrl?.trim();
          if (runtimeUrl != null && runtimeUrl.isNotEmpty) {
            return Uri.parse(runtimeUrl);
          }
          throw const McpBootstrapException('missing_base_url');
        }
        return Uri.parse(baseUrl.endsWith('/api/mcp')
            ? baseUrl
            : '${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/mcp');
      default:
        final runtimeUrl = credential.runtimeUrl?.trim();
        if (runtimeUrl == null || runtimeUrl.isEmpty) {
          throw McpBootstrapException('provider_runtime_unconfigured:$connectorId');
        }
        return Uri.parse(runtimeUrl);
    }
  }
}

class McpBootstrapException implements Exception {
  const McpBootstrapException(this.code);

  final String code;

  @override
  String toString() => 'McpBootstrapException: $code';
}
