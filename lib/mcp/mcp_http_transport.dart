import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_transport.dart';

class McpHttpTransport implements McpTransport {
  McpHttpTransport({
    required Uri endpoint,
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    McpHeadersProvider? headersProvider,
  })  : _endpoint = endpoint,
        _httpClient = httpClient ?? HttpClient(),
        _headers = headers,
        _headersProvider = headersProvider;

  final Uri _endpoint;
  final HttpClient _httpClient;
  final Map<String, String> _headers;
  final McpHeadersProvider? _headersProvider;
  final StreamController<McpTransportMessage> _messagesController =
      StreamController<McpTransportMessage>.broadcast();

  int _nextId = 0;
  bool _isClosed = false;

  @override
  Stream<McpTransportMessage> get messages => _messagesController.stream;

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw const McpTransportException('transport_closed');
    }
  }

  @override
  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    final request = McpJsonRpcRequest(
      id: ++_nextId,
      method: method,
      params: params,
    );
    final response = await _postJson(request.toJson());
    if (response.isError) {
      throw McpProtocolException(
        'json_rpc_error:${response.error?.code}:${response.error?.message}',
      );
    }
    return response;
  }

  @override
  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    await _postJson(
      McpJsonRpcNotification(method: method, params: params).toJson(),
      expectJsonRpcResponse: false,
    );
  }

  Future<McpJsonRpcResponse> _postJson(
    Map<String, Object?> payload, {
    bool expectJsonRpcResponse = true,
  }) async {
    if (_isClosed) {
      throw const McpTransportException('transport_closed');
    }

    final request = await _httpClient.postUrl(_endpoint);
    request.headers.contentType = ContentType.json;

    final headers = <String, String>{..._headers};
    if (_headersProvider != null) {
      headers.addAll(await _headersProvider.call());
    }
    headers.forEach(request.headers.set);

    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode != HttpStatus.ok) {
      throw McpTransportException(
        'http_status:${response.statusCode}:${response.reasonPhrase}',
      );
    }

    if (!expectJsonRpcResponse) {
      return const McpJsonRpcResponse(id: null);
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const McpProtocolException('invalid_json_response');
    }

    if (decoded is! Map) {
      throw const McpProtocolException('invalid_json_rpc_response');
    }

    final jsonRpcResponse =
        McpJsonRpcResponse.fromJson(decoded.cast<String, Object?>());
    if (jsonRpcResponse.id != payload['id']) {
      throw const McpProtocolException('mismatched_json_rpc_id');
    }

    return jsonRpcResponse;
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _httpClient.close(force: true);
    await _messagesController.close();
  }
}
