import 'dart:convert';
import 'dart:io';

import 'package:openreef/triggers/trigger_codec.dart';
import 'package:openreef/triggers/trigger_models.dart';

class TriggerRepository {
  TriggerRepository({
    required File file,
    TriggerCodec codec = const TriggerCodec(),
  }) : _file = file,
       _codec = codec;

  final File _file;
  final TriggerCodec _codec;

  Future<List<TriggerConfig>> loadAll() async {
    if (!await _file.exists()) {
      return const <TriggerConfig>[];
    }
    final rawJson = await _file.readAsString();
    return _codec.decodeAll(rawJson);
  }

  Future<void> saveAll(List<TriggerConfig> triggers) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_codec.encodeAll(triggers)),
      flush: true,
    );
  }

  Future<void> upsert(TriggerConfig trigger) async {
    final existing = await loadAll();
    final next = <TriggerConfig>[
      ...existing.where((item) => item.id != trigger.id),
      trigger,
    ]..sort((left, right) => left.id.compareTo(right.id));
    await saveAll(next);
  }

  Future<bool> remove(String triggerId) async {
    final existing = await loadAll();
    final next = existing.where((item) => item.id != triggerId).toList();
    if (next.length == existing.length) {
      return false;
    }
    await saveAll(next);
    return true;
  }
}
