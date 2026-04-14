import 'dart:async';

import 'package:flutter/services.dart';

class McpOAuthCallbackPayload {
  const McpOAuthCallbackPayload({
    required this.uri,
    required this.source,
  });

  final Uri uri;
  final String source;
}

class McpOAuthBridge {
  McpOAuthBridge._({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/mcp_oauth_bridge';
  static final McpOAuthBridge instance = McpOAuthBridge._();

  final MethodChannel _channel;
  final StreamController<McpOAuthCallbackPayload> _callbacks =
      StreamController<McpOAuthCallbackPayload>.broadcast();
  bool _initialized = false;

  Stream<McpOAuthCallbackPayload> get callbacks => _callbacks.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _callbacks.close();
    _initialized = false;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'oauthCallback':
        final arguments = call.arguments;
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        final uriString = map['uri']?.toString();
        final source = map['source']?.toString() ?? 'unknown';
        if (uriString == null || uriString.trim().isEmpty) {
          return null;
        }
        final uri = Uri.tryParse(uriString.trim());
        if (uri == null) {
          return null;
        }
        _callbacks.add(McpOAuthCallbackPayload(uri: uri, source: source));
        return null;
      default:
        return null;
    }
  }
}
