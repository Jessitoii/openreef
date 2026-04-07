import 'package:flutter/foundation.dart';

abstract class AgentNotifier {
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  });
}

class DebugPrintAgentNotifier implements AgentNotifier {
  const DebugPrintAgentNotifier();

  @override
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  }) async {
    debugPrint(
      'OpenReef freezeSession sessionKey=$sessionKey reason=$reason title=$title body=$body',
    );
  }
}

class NoopAgentNotifier implements AgentNotifier {
  const NoopAgentNotifier();

  @override
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  }) async {}
}
