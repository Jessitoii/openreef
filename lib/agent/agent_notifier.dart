abstract class AgentNotifier {
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  });
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
