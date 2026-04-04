import 'package:openreef/memory/memory_fact.dart';

class MemoryTurn {
  MemoryTurn({
    required this.facts,
    required this.hasFailedToolCalls,
    required this.isAmbiguous,
    this.sessionKey,
    DateTime? occurredAt,
  }) : occurredAt = occurredAt ?? DateTime.now();

  final List<MemoryFact> facts;
  final bool hasFailedToolCalls;
  final bool isAmbiguous;
  final String? sessionKey;
  final DateTime occurredAt;
}
