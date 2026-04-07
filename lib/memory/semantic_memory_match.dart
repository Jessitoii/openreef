import 'package:openreef/memory/memory_record.dart';

class SemanticMemoryMatch {
  const SemanticMemoryMatch({
    required this.record,
    required this.score,
  });

  final MemoryRecord record;
  final double score;
}
