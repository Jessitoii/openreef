import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_transport.dart';

class McpSseTransport implements McpTransport {
  McpSseTransport({
    required Uri sseEndpoint,
    Uri? postEndpoint,
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    McpHeadersProvider? headersProvider,
  })  : _sseEndpoint = sseEndpoint,
        _postEndpoint = postEndpoint,
        _httpClient = httpClient ?? HttpClient(),
        _headers = headers,
        _headersProvider = headersProvider;

  final Uri _sseEndpoint;
  final HttpClient _httpClient;
  final Map<String, String> _headers;
  final McpHeadersProvider? _headersProvider;
  final StreamController<McpTransportMessage> _messagesController =
      StreamController<McpTransportMessage>.broadcast();

  Uri? _postEndpoint;
  HttpClientRequest? _activeSseRequest;
  HttpClientResponse? _activeSseResponse;
  StreamSubscription<String>? _lineSubscription;
  int _nextId = 0;
  bool _isClosed = false;
  final StringBuffer _dataBuffer = StringBuffer();
  String _currentEvent = 'message';

  @override
  Stream<McpTransportMessage> get messages => _messagesController.stream;

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw const McpTransportException('transport_closed');
    }
    if (_activeSseResponse != null) {
      return;
    }

    final request = await _httpClient.getUrl(_sseEndpoint);
    _activeSseRequest = request;
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    final headers = <String, String>{..._headers};
    if (_headersProvider != null) {
      headers.addAll(await _headersProvider.call());
    }
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw McpTransportException(
        'http_status:${response.statusCode}:${response.reasonPhrase}',
      );
    }

    final contentType = response.headers.contentType;
    if (contentType?.mimeType != 'text/event-stream') {
      throw const McpTransportException('invalid_sse_content_type');
    }

    _activeSseResponse = response;
    _lineSubscription = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: _messagesController.addError,
          onDone: _handleStreamDone,
          cancelOnError: true,
        );
  }

  void _handleLine(String line) {
    if (line.isEmpty) {
      _emitEvent();
      return;
    }
    if (line.startsWith(':')) {
      return;
    }
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
      return;
    }
    if (line.startsWith('data:')) {
      if (_dataBuffer.isNotEmpty) {
        _dataBuffer.writeln();
      }
      _dataBuffer.write(line.substring(5).trimLeft());
    }
  }

  void _emitEvent() {
    if (_dataBuffer.isEmpty) {
      _currentEvent = 'message';
      return;
    }

    final message = McpTransportMessage.fromRaw(
      event: _currentEvent,
      data: _dataBuffer.toString(),
    );
    _updatePostEndpointFromMessage(message);
    _messagesController.add(message);
    _dataBuffer.clear();
    _currentEvent = 'message';
  }

  void _updatePostEndpointFromMessage(McpTransportMessage message) {
    if (message.event != 'endpoint') {
      return;
    }

    final uri = _parseEndpointAnnouncement(message);
    if (uri != null) {
      _postEndpoint = uri;
    }
  }

  Uri? _parseEndpointAnnouncement(McpTransportMessage message) {
    final json = message.jsonRpcMessage;
    if (json != null) {
      final candidate = json['uri'] ?? json['endpoint'];
      if (candidate is String && candidate.isNotEmpty) {
        return _sseEndpoint.resolve(candidate);
      }
    }

    final data = message.data.trim();
    if (data.isEmpty) {
      return null;
    }
    return _sseEndpoint.resolve(data);
  }

  void _handleStreamDone() {
    _activeSseRequest = null;
    _activeSseResponse = null;
    _lineSubscription = null;
  }

  Uri get _resolvedPostEndpoint {
    final endpoint = _postEndpoint;
    if (endpoint == null) {
      throw const McpTransportException('missing_post_endpoint');
    }
    return endpoint;
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

    final request = await _httpClient.postUrl(_resolvedPostEndpoint);
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
    await _lineSubscription?.cancel();
    _activeSseRequest?.abort();
    _httpClient.close(force: true);
    await _messagesController.close();
  }
}
