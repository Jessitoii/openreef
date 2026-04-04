import 'package:openreef/mcp/mcp_models.dart';

typedef McpHeadersProvider = Future<Map<String, String>> Function();

abstract class McpTransport {
  Stream<McpTransportMessage> get messages;

  Future<void> connect();

  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  });

  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  });

  Future<void> close();
}
