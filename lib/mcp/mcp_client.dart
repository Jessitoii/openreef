import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_transport.dart';

class McpClient {
  McpClient(this._transport);

  final McpTransport _transport;
  bool _connected = false;
  bool _initialized = false;

  Stream<McpTransportMessage> get messages => _transport.messages;

  Future<void> connect() async {
    if (_connected) {
      return;
    }
    await _transport.connect();
    _connected = true;
  }

  Future<McpInitializeResult> initialize({
    required McpClientInfo clientInfo,
    String protocolVersion = '2024-11-05',
    Map<String, Object?> capabilities = const <String, Object?>{},
  }) async {
    await connect();
    final response = await _transport.sendRequest(
      'initialize',
      params: <String, Object?>{
        'protocolVersion': protocolVersion,
        'clientInfo': clientInfo.toJson(),
        'capabilities': capabilities,
      },
    );

    final initializeResult = McpInitializeResult.fromJson(
      response.resultAsMap(),
    );
    await _transport.sendNotification('notifications/initialized');
    _initialized = true;
    return initializeResult;
  }

  Future<List<McpTool>> listTools() async {
    if (!_initialized) {
      throw const McpProtocolException('client_not_initialized');
    }

    final response = await _transport.sendRequest('tools/list');
    final result = response.resultAsMap();
    final tools = result['tools'];
    if (tools is! List) {
      throw const McpProtocolException('missing_tools_list');
    }

    return tools
        .whereType<Map>()
        .map((json) => McpTool.fromJson(json.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<void> close() async {
    _connected = false;
    _initialized = false;
    await _transport.close();
  }
}
