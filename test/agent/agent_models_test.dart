import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';

void main() {
  test('agent message renders prompt segment with role', () {
    const message = AgentMessage(
      role: AgentMessageRole.user,
      content: 'Hello reef',
    );

    expect(message.toPromptSegment(), '[USER] Hello reef');
  });
}
