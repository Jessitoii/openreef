import 'dart:convert';
import 'dart:io';

import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';

import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/triggers/trigger_native_sync.dart';
import 'package:openreef/triggers/trigger_polling_policy.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:path/path.dart' as p;

List<NativeToolHandler> createMvpNativeToolHandlers({
  required DeviceVolumeAdapter volumeAdapter,
  required ClipboardAdapter clipboardAdapter,
  required BatteryAdapter batteryAdapter,
  required ContactAdapter contactAdapter,
  required DraftMessageAdapter draftMessageAdapter,
  required FlashlightAdapter flashlightAdapter,
  required DndAdapter dndAdapter,
  required LocationAdapter locationAdapter,
  required MapsAdapter mapsAdapter,
  required TtsAdapter ttsAdapter,
  required NotificationAdapter notificationAdapter,
  required AppLauncherAdapter appLauncherAdapter,
  required ShareAdapter shareAdapter,
  required SemanticMemoryRetriever memoryRetriever,
  required MemoryStorage memoryStorage,
  required SettingsController settingsController,
  required TriggerNativeSync triggerNativeSync,
  required TriggerSystem triggerSystem,
  required TriggerRepository triggerRepository,
}) {
  return <NativeToolHandler>[
    VolumeSetToolHandler(volumeAdapter),
    ClipboardReadToolHandler(clipboardAdapter),
    ClipboardWriteToolHandler(clipboardAdapter),
    BatteryInfoToolHandler(batteryAdapter),
    ContactReadToolHandler(contactAdapter),
    ContactCreateToolHandler(contactAdapter),
    SmsDraftToolHandler(draftMessageAdapter),
    EmailDraftToolHandler(draftMessageAdapter),
    FlashlightToggleToolHandler(flashlightAdapter),
    DndSetToolHandler(dndAdapter),
    LocationGetToolHandler(locationAdapter),
    MapsNavigateToolHandler(mapsAdapter),
    RegexEvalToolHandler(),
    MathEvalToolHandler(),
    TtsSpeakToolHandler(ttsAdapter),
    MemorySaveToolHandler(memoryStorage: memoryStorage),
    MemorySearchToolHandler(memoryRetriever),
    NotifyToolHandler(notificationAdapter),
    AppOpenToolHandler(appLauncherAdapter),
    ShareToolHandler(shareAdapter),
    FileReadToolHandler(),
    FileWriteToolHandler(),
    SettingsReadToolHandler(settingsController),
    SettingsWriteToolHandler(settingsController, triggerNativeSync),
    TriggerCreateToolHandler(
      triggerSystem,
      triggerRepository,
      triggerNativeSync,
    ),
    TriggerListToolHandler(triggerSystem, settingsController),
    TriggerRemoveToolHandler(
      triggerSystem,
      triggerRepository,
      triggerNativeSync,
    ),
    AlarmSetToolHandler(triggerSystem, triggerRepository, triggerNativeSync),
    CronAddToolHandler(triggerSystem, triggerRepository, triggerNativeSync),
    CronListToolHandler(triggerSystem),
    CronRemoveToolHandler(
      triggerSystem,
      triggerRepository,
      triggerNativeSync,
    ),
  ];
}

class VolumeSetToolHandler implements NativeToolHandler {
  VolumeSetToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'volume_set',
    description: 'Set the device media volume.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'level',
        type: ToolArgumentType.doubleValue,
        minimum: 0,
        maximum: 1,
      ),
    ],
    tags: <String>['android', 'system', 'audio'],
  );

  final DeviceVolumeAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final level = invocation.arguments['level'] as double;
    final normalizedLevel = level.clamp(0.0, 1.0);
    final appliedLevel = await _adapter.setVolumeLevel(normalizedLevel);
    return NativeToolExecutionResult(
      content: 'Volume set to ${(appliedLevel * 100).round()}%.',
      metadata: <String, Object?>{
        'requestedLevel': normalizedLevel,
        'appliedLevel': appliedLevel,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class ClipboardReadToolHandler implements NativeToolHandler {
  ClipboardReadToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'clipboard_read',
    description: 'Read the current clipboard text.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['android', 'system', 'clipboard'],
  );

  final ClipboardAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final text = await _adapter.readClipboardText();
    final hasContent = text != null && text.isNotEmpty;
    return NativeToolExecutionResult(
      content: hasContent ? text : 'Clipboard is empty.',
      metadata: <String, Object?>{
        'hasContent': hasContent,
        'text': text ?? '',
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class ClipboardWriteToolHandler implements NativeToolHandler {
  ClipboardWriteToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'clipboard_write',
    description: 'Write text to the clipboard.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'text', type: ToolArgumentType.string),
    ],
    tags: <String>['android', 'system', 'clipboard'],
  );

  final ClipboardAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final text = (invocation.arguments['text'] as String).trim();
    await _adapter.writeClipboardText(text);
    return NativeToolExecutionResult(
      content: 'Clipboard updated.',
      metadata: <String, Object?>{
        'charactersWritten': text.length,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class BatteryInfoToolHandler implements NativeToolHandler {
  BatteryInfoToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'battery_info',
    description: 'Read the current battery status.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['android', 'system', 'battery'],
  );

  final BatteryAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final snapshot = await _adapter.readBatteryInfo();
    return NativeToolExecutionResult(
      content: 'Battery at ${snapshot.level}% (${snapshot.state.name}).',
      metadata: <String, Object?>{
        'level': snapshot.level,
        'state': snapshot.state.name,
        'isLowPowerMode': snapshot.isLowPowerMode,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class MemorySaveToolHandler implements NativeToolHandler {
  MemorySaveToolHandler({
    required MemoryStorage memoryStorage,
  }) : _memoryStorage = memoryStorage;

  static const ToolManifest _manifest = ToolManifest(
    id: 'memory_save',
    description: 'Save an explicit memory fact.',
    category: 'memory',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'content', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'category', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'importance',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 1,
        maximum: 5,
      ),
      ToolArgumentSpec(
        name: 'key',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['memory', 'save'],
  );

  final MemoryStorage _memoryStorage;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final content = (invocation.arguments['content'] as String).trim();
    final category = (invocation.arguments['category'] as String).trim();
    if (content.isEmpty) {
      throw ArgumentError.value(content, 'content', 'memory_content_empty');
    }
    if (category.isEmpty) {
      throw ArgumentError.value(category, 'category', 'memory_category_empty');
    }
    final importance = (invocation.arguments['importance'] as int?) ?? 4;
    final key = (invocation.arguments['key'] as String?)?.trim();
    final memoryKey = key == null || key.isEmpty
        ? _generateMemoryKey(category, context.now())
        : key;
    final occurredAt = context.now();
    await _memoryStorage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: memoryKey,
        content: content,
        category: category,
        importance: importance,
        metadata: const <String, Object?>{'source': 'tool:memory_save'},
        createdAt: occurredAt,
      ),
    );
    return NativeToolExecutionResult(
      content: 'Memory saved under $memoryKey.',
      metadata: <String, Object?>{
        'key': memoryKey,
        'category': category,
        'importance': importance,
        'executedAt': occurredAt.toIso8601String(),
      },
    );
  }

  String _generateMemoryKey(String category, DateTime now) {
    final normalizedCategory = category
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${normalizedCategory}_${now.microsecondsSinceEpoch}';
  }
}

class MemorySearchToolHandler implements NativeToolHandler {
  MemorySearchToolHandler(this._retriever);

  static const ToolManifest _manifest = ToolManifest(
    id: 'memory_search',
    description: 'Search saved memory semantically.',
    category: 'memory',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'query', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'top_k',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 1,
        maximum: 10,
      ),
    ],
    tags: <String>['memory', 'semantic', 'retrieval'],
  );

  final SemanticMemoryRetriever _retriever;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final query = (invocation.arguments['query'] as String? ?? '').trim();
    final topK = (invocation.arguments['top_k'] as int?) ?? 3;
    final result = await _retriever.search(query: query, limit: topK);

    if (result.isDegraded && !result.hasMatches) {
      return NativeToolExecutionResult(
        content: 'Memory retrieval unavailable.',
        metadata: <String, Object?>{
          'query': query,
          'memory_retrieval_status': result.status.name,
          'memory_retrieval_reason': result.message,
          'embedding_model_id_used': result.modelIdUsed,
          'memory_retrieval_degraded': true,
          'results': const <Object?>[],
          'executedAt': context.now().toIso8601String(),
        },
      );
    }

    if (!result.hasMatches) {
      return NativeToolExecutionResult(
        content: 'No relevant memories found.',
        metadata: <String, Object?>{
          'query': query,
          'memory_retrieval_status': result.status.name,
          'memory_retrieval_reason': result.message,
          'embedding_model_id_used': result.modelIdUsed,
          'results': const <Object?>[],
          'executedAt': context.now().toIso8601String(),
        },
      );
    }

    final results = result.matches
        .map(
          (match) => <String, Object?>{
            'key': match.record.key,
            'category': match.record.category,
            'score': match.score,
            'content': match.record.content,
          },
        )
        .toList(growable: false);
    final lines = results
        .map((match) => '- [${match['category']}] ${match['content']}')
        .join('\n');
    return NativeToolExecutionResult(
      content: lines,
      metadata: <String, Object?>{
        'query': query,
        'results': results,
        'results_json': jsonEncode(results),
        'memory_retrieval_status': result.status.name,
        'memory_retrieval_reason': result.message,
        'embedding_model_id_used': result.modelIdUsed,
        'excluded_cross_model_matches': result.skippedCrossModelCount,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class NotifyToolHandler implements NativeToolHandler {
  NotifyToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'notify',
    description: 'Post a device notification.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'title', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'body', type: ToolArgumentType.string),
    ],
    tags: <String>['android', 'notification'],
  );

  final NotificationAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final title = (invocation.arguments['title'] as String).trim();
    final body = (invocation.arguments['body'] as String).trim();
    final dispatch = await _adapter.showNotification(title: title, body: body);
    return NativeToolExecutionResult(
      content: 'Notification posted: $title',
      metadata: <String, Object?>{
        'notificationId': dispatch.notificationId,
        'dispatchedAt': dispatch.dispatchedAt.toIso8601String(),
      },
    );
  }
}

class AppOpenToolHandler implements NativeToolHandler {
  AppOpenToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'app_open',
    description: 'Open an installed Android app by package name.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'package_name', type: ToolArgumentType.string),
    ],
    tags: <String>['android', 'launch'],
  );

  final AppLauncherAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final packageName = (invocation.arguments['package_name'] as String).trim();
    await _adapter.openApp(packageName);
    return NativeToolExecutionResult(
      content: 'Opened $packageName.',
      metadata: <String, Object?>{
        'packageName': packageName,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class ShareToolHandler implements NativeToolHandler {
  ShareToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'share',
    description: 'Open the share sheet with text.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'text', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'subject',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'share'],
  );

  final ShareAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final text = (invocation.arguments['text'] as String).trim();
    final subject = (invocation.arguments['subject'] as String?)?.trim();
    await _adapter.shareText(text: text, subject: subject);
    return NativeToolExecutionResult(
      content: 'Share sheet opened.',
      metadata: <String, Object?>{
        'charactersShared': text.length,
        'subject': subject ?? '',
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class FileReadToolHandler implements NativeToolHandler {
  static const int _defaultMaxBytes = 16 * 1024;

  static const ToolManifest _manifest = ToolManifest(
    id: 'file_read',
    description: 'Read a local file from an absolute path.',
    category: 'code',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'max_bytes',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 1,
        maximum: 65536,
      ),
    ],
    tags: <String>['file', 'read'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final normalizedPath = _normalizeAbsolutePath(
      invocation.arguments['path'] as String,
    );
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw StateError('file_not_found:$normalizedPath');
    }
    final entityType = await FileSystemEntity.type(normalizedPath);
    if (entityType != FileSystemEntityType.file) {
      throw StateError('invalid_file_target:$normalizedPath');
    }
    final maxBytes =
        (invocation.arguments['max_bytes'] as int?) ?? _defaultMaxBytes;
    final bytes = await file.readAsBytes();
    final truncated = bytes.length > maxBytes;
    final visibleBytes = truncated ? bytes.sublist(0, maxBytes) : bytes;
    final content = utf8.decode(visibleBytes, allowMalformed: true);
    return NativeToolExecutionResult(
      content: content,
      metadata: <String, Object?>{
        'path': normalizedPath,
        'bytesRead': visibleBytes.length,
        'truncated': truncated,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class FileWriteToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'file_write',
    description: 'Write text to a local absolute path.',
    category: 'code',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'content', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'append',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
    ],
    tags: <String>['file', 'write'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final normalizedPath = _normalizeAbsolutePath(
      invocation.arguments['path'] as String,
    );
    final append = invocation.arguments['append'] as bool? ?? false;
    final content = invocation.arguments['content'] as String;
    final parent = Directory(p.dirname(normalizedPath));
    await parent.create(recursive: true);
    final file = File(normalizedPath);
    final entityType = await FileSystemEntity.type(normalizedPath);
    if (entityType == FileSystemEntityType.directory) {
      throw StateError('invalid_file_target:$normalizedPath');
    }
    await file.writeAsString(
      content,
      mode: append ? FileMode.append : FileMode.write,
      flush: true,
    );
    return NativeToolExecutionResult(
      content: append ? 'File appended.' : 'File written.',
      metadata: <String, Object?>{
        'path': normalizedPath,
        'append': append,
        'bytesWritten': utf8.encode(content).length,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class SettingsReadToolHandler implements NativeToolHandler {
  SettingsReadToolHandler(this._controller);

  static const ToolManifest _manifest = ToolManifest(
    id: 'settings_read',
    description: 'Read persisted agent settings.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'key',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['settings'],
  );

  final SettingsController _controller;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final key = (invocation.arguments['key'] as String?)?.trim();
    if (key == null || key.isEmpty) {
      final values = _controller.readAllToolValues();
      return NativeToolExecutionResult(
        content: const JsonEncoder.withIndent('  ').convert(values),
        metadata: <String, Object?>{
          'settings': values,
          'executedAt': context.now().toIso8601String(),
        },
      );
    }
    final value = _controller.readToolValue(key);
    return NativeToolExecutionResult(
      content: '$key=$value',
      metadata: <String, Object?>{
        'key': key,
        'value': value,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class SettingsWriteToolHandler implements NativeToolHandler {
  SettingsWriteToolHandler(this._controller, this._triggerNativeSync);

  static const ToolManifest _manifest = ToolManifest(
    id: 'settings_write',
    description: 'Write a persisted agent setting.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'key', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'string_value',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'bool_value',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'double_value',
        type: ToolArgumentType.doubleValue,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'int_value',
        type: ToolArgumentType.integer,
        isRequired: false,
      ),
    ],
    tags: <String>['settings'],
  );

  final SettingsController _controller;
  final TriggerNativeSync _triggerNativeSync;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final key = (invocation.arguments['key'] as String).trim();
    final value = _extractSettingValue(invocation.arguments, key);
    if (key == 'trigger.mailPollMinutes') {
      final validation = const TriggerPollingPolicy().validateResolvedMinutes(
        value as int,
      );
      if (!validation.isValid) {
        throw ArgumentError(validation.error ?? 'invalid_poll_interval');
      }
    }
    await _controller.writeToolValue(key, value);
    if (key == 'trigger.mailPollMinutes') {
      await _triggerNativeSync.syncGlobalPollMinutes(
        _controller.readToolValue(key) as int,
      );
    }
    final persistedValue = _controller.readToolValue(key);
    return NativeToolExecutionResult(
      content: 'Setting updated: $key=$persistedValue',
      metadata: <String, Object?>{
        'key': key,
        'value': persistedValue,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }

  Object _extractSettingValue(Map<String, Object?> arguments, String key) {
    return switch (key) {
      'theme.mode' || 'voice.ttsEngine' =>
        arguments['string_value'] ??
            (throw ArgumentError('missing_string_value:$key')),
      'voice.wakeWordEnabled' =>
        arguments['bool_value'] ??
            (throw ArgumentError('missing_bool_value:$key')),
      'voice.sensitivity' =>
        arguments['double_value'] ??
            (throw ArgumentError('missing_double_value:$key')),
      'trigger.mailPollMinutes' =>
        arguments['int_value'] ??
            (throw ArgumentError('missing_int_value:$key')),
      _ => throw ArgumentError.value(key, 'key', 'unsupported_setting_key'),
    };
  }
}

class TriggerCreateToolHandler extends _BaseTriggerMutationToolHandler {
  TriggerCreateToolHandler(
    super.triggerSystem,
    super.triggerRepository,
    super.triggerNativeSync,
  );

  static const ToolManifest _manifest = ToolManifest(
    id: 'trigger_create',
    description: 'Create and persist a trigger.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'name', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'prompt', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'kind',
        type: ToolArgumentType.string,
        allowedValues: <Object?>['manual', 'schedule', 'interval', 'boot'],
      ),
      ToolArgumentSpec(
        name: 'id',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'priority',
        type: ToolArgumentType.string,
        isRequired: false,
        allowedValues: <Object?>['low', 'normal', 'high'],
      ),
      ToolArgumentSpec(
        name: 'hour',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 0,
        maximum: 23,
      ),
      ToolArgumentSpec(
        name: 'minute',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 0,
        maximum: 59,
      ),
      ToolArgumentSpec(
        name: 'every_minutes',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 1,
        maximum: 10080,
      ),
      ToolArgumentSpec(
        name: 'requires_user_attention',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'is_expensive',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'enabled',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
    ],
    tags: <String>['trigger', 'schedule', 'interval'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) {
    final trigger = _createTrigger(
      invocation.arguments,
      now: context.now(),
      defaultSurface: 'trigger',
    );
    return registerAndPersist(trigger, context);
  }
}

class TriggerListToolHandler implements NativeToolHandler {
  TriggerListToolHandler(this._triggerSystem, this._settingsController);

  static const ToolManifest _manifest = ToolManifest(
    id: 'trigger_list',
    description: 'List persisted triggers and state.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['trigger', 'list'],
  );

  final TriggerSystem _triggerSystem;
  final SettingsController _settingsController;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final triggers = _triggerSystem.listTriggers()
      ..sort((left, right) => left.id.compareTo(right.id));
    final rows = triggers
        .map(
          (trigger) => _serializeTriggerRow(
            trigger,
            _triggerSystem.stateById(trigger.id),
            settingsController: _settingsController,
          ),
        )
        .toList(growable: false);
    return NativeToolExecutionResult(
      content: rows.isEmpty
          ? 'No triggers registered.'
          : rows
                .map(
                  (row) =>
                      '- ${row['id']} (${row['type']}) enabled=${row['enabled']}',
                )
                .join('\n'),
      metadata: <String, Object?>{
        'triggers': rows,
        'triggers_json': jsonEncode(rows),
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class TriggerRemoveToolHandler extends _BaseTriggerMutationToolHandler {
  TriggerRemoveToolHandler(
    super.triggerSystem,
    super.triggerRepository,
    super.triggerNativeSync,
  );

  static const ToolManifest _manifest = ToolManifest(
    id: 'trigger_remove',
    description: 'Remove a persisted trigger.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'trigger_id', type: ToolArgumentType.string),
    ],
    tags: <String>['trigger', 'remove'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final triggerId = (invocation.arguments['trigger_id'] as String).trim();
    final cancelled = await triggerSystem.cancel(triggerId);
    final removed = await triggerRepository.remove(triggerId);
    if (!cancelled && !removed) {
      throw StateError('unknown_trigger:$triggerId');
    }
    return NativeToolExecutionResult(
      content: 'Removed trigger $triggerId.',
      metadata: <String, Object?>{
        'triggerId': triggerId,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class AlarmSetToolHandler extends _BaseTriggerMutationToolHandler {
  AlarmSetToolHandler(
    super.triggerSystem,
    super.triggerRepository,
    super.triggerNativeSync,
  );

  static const ToolManifest _manifest = ToolManifest(
    id: 'alarm_set',
    description: 'Create a daily exact-time reminder.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'name', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'prompt', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'hour',
        type: ToolArgumentType.integer,
        minimum: 0,
        maximum: 23,
      ),
      ToolArgumentSpec(
        name: 'minute',
        type: ToolArgumentType.integer,
        minimum: 0,
        maximum: 59,
      ),
    ],
    tags: <String>['alarm', 'trigger'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) {
    final trigger = _createTrigger(
      <String, Object?>{
        ...invocation.arguments,
        'kind': 'schedule',
      },
      now: context.now(),
      defaultSurface: 'alarm',
    );
    return registerAndPersist(trigger, context);
  }
}

class CronAddToolHandler extends _BaseTriggerMutationToolHandler {
  CronAddToolHandler(
    super.triggerSystem,
    super.triggerRepository,
    super.triggerNativeSync,
  );

  static const ToolManifest _manifest = ToolManifest(
    id: 'cron_add',
    description: 'Create a recurring interval trigger.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'name', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'prompt', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'every_minutes',
        type: ToolArgumentType.integer,
        minimum: 1,
        maximum: 10080,
      ),
    ],
    tags: <String>['cron', 'trigger'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) {
    final trigger = _createTrigger(
      <String, Object?>{
        ...invocation.arguments,
        'kind': 'interval',
      },
      now: context.now(),
      defaultSurface: 'cron',
    );
    return registerAndPersist(trigger, context);
  }
}

class CronListToolHandler implements NativeToolHandler {
  CronListToolHandler(this._triggerSystem);

  static const ToolManifest _manifest = ToolManifest(
    id: 'cron_list',
    description: 'List recurring interval triggers.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['cron', 'list'],
  );

  final TriggerSystem _triggerSystem;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final rows = _triggerSystem
        .listTriggers()
        .where((trigger) => trigger.type == TriggerType.interval)
        .map(
          (trigger) => _serializeTriggerRow(
            trigger,
            _triggerSystem.stateById(trigger.id),
          ),
        )
        .toList(growable: false);
    return NativeToolExecutionResult(
      content: rows.isEmpty
          ? 'No recurring cron triggers.'
          : rows
                .map(
                  (row) =>
                      '- ${row['id']} every ${row['everyMinutes']}m enabled=${row['enabled']}',
                )
                .join('\n'),
      metadata: <String, Object?>{
        'triggers': rows,
        'triggers_json': jsonEncode(rows),
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class CronRemoveToolHandler extends _BaseTriggerMutationToolHandler {
  CronRemoveToolHandler(
    super.triggerSystem,
    super.triggerRepository,
    super.triggerNativeSync,
  );

  static const ToolManifest _manifest = ToolManifest(
    id: 'cron_remove',
    description: 'Remove a recurring interval trigger.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'trigger_id', type: ToolArgumentType.string),
    ],
    tags: <String>['cron', 'remove'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final triggerId = (invocation.arguments['trigger_id'] as String).trim();
    final trigger = triggerSystem.byId(triggerId);
    if (trigger == null || trigger.type != TriggerType.interval) {
      throw StateError('unknown_cron_trigger:$triggerId');
    }
    await triggerSystem.cancel(triggerId);
    await triggerRepository.remove(triggerId);
    await triggerNativeSync.syncTriggers(triggerSystem.listTriggers());
    return NativeToolExecutionResult(
      content: 'Removed cron trigger $triggerId.',
      metadata: <String, Object?>{
        'triggerId': triggerId,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

abstract class _BaseTriggerMutationToolHandler implements NativeToolHandler {
  _BaseTriggerMutationToolHandler(
    this.triggerSystem,
    this.triggerRepository,
    this.triggerNativeSync,
  );

  final TriggerSystem triggerSystem;
  final TriggerRepository triggerRepository;
  final TriggerNativeSync triggerNativeSync;

  Future<NativeToolExecutionResult> registerAndPersist(
    TriggerConfig trigger,
    ToolExecutionContext context,
  ) async {
    final registration = await triggerSystem.register(trigger);
    if (!registration.isRegistered) {
      throw StateError(registration.error ?? 'trigger_registration_failed');
    }
    await triggerRepository.upsert(trigger);
    await triggerNativeSync.syncTriggers(triggerSystem.listTriggers());
    return NativeToolExecutionResult(
      content: 'Trigger ${trigger.id} created.',
      metadata: <String, Object?>{
        'trigger': _serializeTriggerRow(
          trigger,
          triggerSystem.stateById(trigger.id),
        ),
        'executedAt': context.now().toIso8601String(),
      },
    );
  }

  TriggerConfig _createTrigger(
    Map<String, Object?> arguments, {
    required DateTime now,
    required String defaultSurface,
  }) {
    final kind = TriggerType.values.byName(arguments['kind'] as String);
    final id = ((arguments['id'] as String?)?.trim().isNotEmpty ?? false)
        ? (arguments['id'] as String).trim()
        : _generateTriggerId(
            kind: kind,
            name: (arguments['name'] as String).trim(),
            now: now,
          );
    return TriggerConfig(
      id: id,
      name: (arguments['name'] as String).trim(),
      prompt: (arguments['prompt'] as String).trim(),
      type: kind,
      priority: TriggerPriority.values.byName(
        (arguments['priority'] as String?) ?? 'normal',
      ),
      enabled: arguments['enabled'] as bool? ?? true,
      requiresUserAttention:
          arguments['requires_user_attention'] as bool? ?? false,
      isExpensive: arguments['is_expensive'] as bool? ?? false,
      pollIntervalMinutes: arguments['poll_interval_minutes'] as int?,
      scheduleSpec: kind == TriggerType.schedule
          ? ScheduleTriggerSpec(
              hour: arguments['hour'] as int? ??
                  (throw ArgumentError('missing_hour')),
              minute: arguments['minute'] as int? ??
                  (throw ArgumentError('missing_minute')),
            )
          : null,
      intervalSpec: kind == TriggerType.interval
          ? IntervalTriggerSpec(
              every: Duration(
                minutes: _resolveEveryMinutes(arguments),
              ),
            )
          : null,
      payload: <String, Object?>{
        'surface': defaultSurface,
        'created_at': now.toIso8601String(),
      },
    );
  }

  int _resolveEveryMinutes(Map<String, Object?> arguments) {
    final everyMinutes = arguments['every_minutes'] as int?;
    if (everyMinutes == null) {
      throw ArgumentError('missing_every_minutes');
    }
    final validation = const TriggerPollingPolicy().validateResolvedMinutes(
      everyMinutes,
    );
    if (!validation.isValid) {
      throw ArgumentError(validation.error ?? 'invalid_poll_interval');
    }
    return everyMinutes;
  }

  String _generateTriggerId({
    required TriggerType kind,
    required String name,
    required DateTime now,
  }) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${kind.name}_${slug}_${now.millisecondsSinceEpoch}';
  }
}

class ContactReadToolHandler implements NativeToolHandler {
  ContactReadToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'contact_read',
    description: 'Read matching contacts from the local address book.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'query',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'limit',
        type: ToolArgumentType.integer,
        isRequired: false,
        minimum: 1,
        maximum: 20,
      ),
    ],
    tags: <String>['android', 'contacts', 'communication'],
  );

  final ContactAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final query = (invocation.arguments['query'] as String?)?.trim();
      final limit = (invocation.arguments['limit'] as int?) ?? 5;
      final results = await _adapter.searchContacts(query: query, limit: limit);
      if (results.isEmpty) {
        return NativeToolExecutionResult.success(
          content: 'No matching contacts found.',
          metadata: <String, Object?>{
            'query': query ?? '',
            'count': 0,
            'results': const <Object?>[],
            'executedAt': context.now().toIso8601String(),
          },
        );
      }
      return NativeToolExecutionResult.success(
        content: results.map(_formatContact).join('\n'),
        metadata: <String, Object?>{
          'query': query ?? '',
          'count': results.length,
          'results': results.map(_contactToMap).toList(growable: false),
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class ContactCreateToolHandler implements NativeToolHandler {
  ContactCreateToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'contact_create',
    description: 'Create a new local contact entry.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'display_name', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'phone',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'email',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'contacts', 'communication'],
  );

  final ContactAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final displayName = (invocation.arguments['display_name'] as String).trim();
      final created = await _adapter.createContact(
        displayName: displayName,
        phone: (invocation.arguments['phone'] as String?)?.trim(),
        email: (invocation.arguments['email'] as String?)?.trim(),
      );
      return NativeToolExecutionResult.success(
        content: 'Created contact ${created.displayName}.',
        metadata: <String, Object?>{
          'contact': _contactToMap(created),
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class SmsDraftToolHandler implements NativeToolHandler {
  SmsDraftToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'sms_draft',
    description: 'Open an SMS draft in the default messaging app.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'to',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'body',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'sms', 'communication'],
  );

  final DraftMessageAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      await _adapter.openSmsDraft(
        to: (invocation.arguments['to'] as String?)?.trim(),
        body: (invocation.arguments['body'] as String?)?.trim(),
      );
      return NativeToolExecutionResult.success(
        content: 'Opened an SMS draft.',
        metadata: <String, Object?>{
          'to': invocation.arguments['to'],
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class EmailDraftToolHandler implements NativeToolHandler {
  EmailDraftToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'email_draft',
    description: 'Open an email draft in a mail app.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'to',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'subject',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'body',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'email', 'communication'],
  );

  final DraftMessageAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      await _adapter.openEmailDraft(
        to: (invocation.arguments['to'] as String?)?.trim(),
        subject: (invocation.arguments['subject'] as String?)?.trim(),
        body: (invocation.arguments['body'] as String?)?.trim(),
      );
      return NativeToolExecutionResult.success(
        content: 'Opened an email draft.',
        metadata: <String, Object?>{
          'to': invocation.arguments['to'],
          'subject': invocation.arguments['subject'],
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class FlashlightToggleToolHandler implements NativeToolHandler {
  FlashlightToggleToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'flashlight_toggle',
    description: 'Turn the device flashlight on or off.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'enabled', type: ToolArgumentType.boolean),
    ],
    tags: <String>['android', 'system', 'flashlight'],
  );

  final FlashlightAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final enabled = invocation.arguments['enabled'] as bool;
      final applied = await _adapter.setEnabled(enabled);
      return NativeToolExecutionResult.success(
        content: applied ? 'Flashlight turned on.' : 'Flashlight turned off.',
        metadata: <String, Object?>{
          'enabled': applied,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class DndSetToolHandler implements NativeToolHandler {
  DndSetToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'dnd_set',
    description: 'Set the device Do Not Disturb mode.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'mode',
        type: ToolArgumentType.string,
        allowedValues: <Object?>['all', 'priority_only', 'alarms_only', 'none'],
      ),
    ],
    tags: <String>['android', 'system', 'dnd'],
  );

  final DndAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final mode = switch (invocation.arguments['mode'] as String) {
        'priority_only' => DndMode.priorityOnly,
        'alarms_only' => DndMode.alarmsOnly,
        'none' => DndMode.none,
        _ => DndMode.all,
      };
      final applied = await _adapter.setMode(mode);
      final serialized = _serializeDndMode(applied);
      return NativeToolExecutionResult.success(
        content: 'Do Not Disturb set to $serialized.',
        metadata: <String, Object?>{
          'mode': serialized,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class LocationGetToolHandler implements NativeToolHandler {
  LocationGetToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'location_get',
    description: 'Get the current device location.',
    category: 'location',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'high_accuracy',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'location', 'maps'],
  );

  final LocationAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final snapshot = await _adapter.getCurrentLocation(
        highAccuracy: invocation.arguments['high_accuracy'] as bool? ?? false,
      );
      return NativeToolExecutionResult.success(
        content:
            'Location: ${snapshot.latitude}, ${snapshot.longitude} via ${snapshot.provider}.',
        metadata: <String, Object?>{
          'latitude': snapshot.latitude,
          'longitude': snapshot.longitude,
          'provider': snapshot.provider,
          'timestamp': snapshot.timestamp.toIso8601String(),
          'accuracyMeters': snapshot.accuracyMeters,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class MapsNavigateToolHandler implements NativeToolHandler {
  MapsNavigateToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'maps_navigate',
    description: 'Open turn-by-turn navigation in a maps app.',
    category: 'location',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'query', type: ToolArgumentType.string),
    ],
    tags: <String>['android', 'location', 'maps'],
  );

  final MapsAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final query = (invocation.arguments['query'] as String).trim();
      await _adapter.openNavigation(query: query);
      return NativeToolExecutionResult.success(
        content: 'Opened navigation to $query.',
        metadata: <String, Object?>{
          'query': query,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

class RegexEvalToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'regex_eval',
    description: 'Evaluate a regular expression against input text.',
    category: 'compute',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'pattern', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'input', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'case_sensitive',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
      ToolArgumentSpec(
        name: 'multi_line',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
    ],
    tags: <String>['regex', 'compute'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final pattern = invocation.arguments['pattern'] as String;
    final input = invocation.arguments['input'] as String;
    try {
      final regex = RegExp(
        pattern,
        caseSensitive: invocation.arguments['case_sensitive'] as bool? ?? true,
        multiLine: invocation.arguments['multi_line'] as bool? ?? false,
      );
      final matches = regex.allMatches(input).toList(growable: false);
      return NativeToolExecutionResult.success(
        content: matches.isEmpty
            ? 'No matches found.'
            : 'Found ${matches.length} match${matches.length == 1 ? '' : 'es'}.',
        metadata: <String, Object?>{
          'matchCount': matches.length,
          'matches': matches
              .map(
                (match) => <String, Object?>{
                  'match': match.group(0) ?? '',
                  'groups': List<String?>.generate(
                    match.groupCount,
                    (index) => match.group(index + 1),
                    growable: false,
                  ),
                  'start': match.start,
                  'end': match.end,
                },
              )
              .toList(growable: false),
          'executedAt': context.now().toIso8601String(),
        },
      );
    } on FormatException catch (error) {
      return _nativeFailure(
        ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: 'Invalid regular expression: ${error.message}.',
          innerError: <String, Object?>{'pattern': pattern},
        ),
        context,
      );
    }
  }
}

class MathEvalToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'math_eval',
    description: 'Evaluate a basic arithmetic expression.',
    category: 'compute',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'expression', type: ToolArgumentType.string),
    ],
    tags: <String>['math', 'compute'],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final expression = invocation.arguments['expression'] as String;
    try {
      final value = _MathExpressionParser(expression).parse();
      return NativeToolExecutionResult.success(
        content: 'Expression result: ${_formatNumber(value)}.',
        metadata: <String, Object?>{
          'expression': expression,
          'result': value,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } on FormatException catch (error) {
      return _nativeFailure(
        ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: error.message,
          innerError: <String, Object?>{'expression': expression},
        ),
        context,
      );
    }
  }
}

class TtsSpeakToolHandler implements NativeToolHandler {
  TtsSpeakToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'tts_speak',
    description: 'Speak text aloud with the device TTS engine.',
    category: 'media',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'text', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'interrupt',
        type: ToolArgumentType.boolean,
        isRequired: false,
      ),
    ],
    tags: <String>['android', 'tts', 'media'],
  );

  final TtsAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    try {
      final text = (invocation.arguments['text'] as String).trim();
      await _adapter.speak(
        text: text,
        interrupt: invocation.arguments['interrupt'] as bool? ?? true,
      );
      return NativeToolExecutionResult.success(
        content: 'Speech started for the requested text.',
        metadata: <String, Object?>{
          'text': text,
          'interrupt': invocation.arguments['interrupt'] as bool? ?? true,
          'executedAt': context.now().toIso8601String(),
        },
      );
    } catch (error) {
      return _nativeFailureFromError(error, context);
    }
  }
}

NativeToolExecutionResult _nativeFailureFromError(
  Object error,
  ToolExecutionContext context,
) {
  if (error is ToolExecutionException) {
    return _nativeFailure(error.error, context);
  }
  return _nativeFailure(
    ToolExecutionError(
      code: ToolErrorCode.operationFailed,
      message: error.toString(),
    ),
    context,
  );
}

NativeToolExecutionResult _nativeFailure(
  ToolExecutionError error,
  ToolExecutionContext context,
) {
  return NativeToolExecutionResult.failure(
    error: error,
    metadata: <String, Object?>{
      'executedAt': context.now().toIso8601String(),
    },
  );
}

Map<String, Object?> _contactToMap(ContactRecord contact) {
  return <String, Object?>{
    'displayName': contact.displayName,
    'phoneNumbers': contact.phoneNumbers,
    'emailAddresses': contact.emailAddresses,
  };
}

String _formatContact(ContactRecord contact) {
  final parts = <String>[contact.displayName];
  if (contact.phoneNumbers.isNotEmpty) {
    parts.add('phones: ${contact.phoneNumbers.join(', ')}');
  }
  if (contact.emailAddresses.isNotEmpty) {
    parts.add('emails: ${contact.emailAddresses.join(', ')}');
  }
  return '- ${parts.join(' | ')}';
}

String _serializeDndMode(DndMode mode) {
  return switch (mode) {
    DndMode.all => 'all',
    DndMode.priorityOnly => 'priority_only',
    DndMode.alarmsOnly => 'alarms_only',
    DndMode.none => 'none',
  };
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

class _MathExpressionParser {
  _MathExpressionParser(this._input);

  final String _input;
  int _index = 0;

  double parse() {
    final value = _parseExpression();
    _skipWhitespace();
    if (_index != _input.length) {
      throw FormatException(
        'Invalid expression near "${_input.substring(_index)}".',
      );
    }
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWhitespace();
      if (_consume('+')) {
        value += _parseTerm();
      } else if (_consume('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipWhitespace();
      if (_consume('*')) {
        value *= _parseFactor();
      } else if (_consume('/')) {
        value /= _parseFactor();
      } else if (_consume('%')) {
        value %= _parseFactor();
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipWhitespace();
    if (_consume('-')) {
      return -_parseFactor();
    }
    if (_consume('(')) {
      final value = _parseExpression();
      _skipWhitespace();
      if (!_consume(')')) {
        throw const FormatException('Missing closing parenthesis.');
      }
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipWhitespace();
    final start = _index;
    var hasDecimal = false;
    while (_index < _input.length) {
      final char = _input[_index];
      if (char == '.') {
        if (hasDecimal) {
          break;
        }
        hasDecimal = true;
        _index += 1;
      } else if (_isDigit(char)) {
        _index += 1;
      } else {
        break;
      }
    }
    if (start == _index) {
      throw FormatException(
        'Expected a number near "${_input.substring(_index)}".',
      );
    }
    return double.parse(_input.substring(start, _index));
  }

  bool _consume(String value) {
    if (_index >= _input.length || _input[_index] != value) {
      return false;
    }
    _index += 1;
    return true;
  }

  void _skipWhitespace() {
    while (_index < _input.length && _input[_index].trim().isEmpty) {
      _index += 1;
    }
  }

  bool _isDigit(String value) {
    final codeUnit = value.codeUnitAt(0);
    return codeUnit >= 48 && codeUnit <= 57;
  }
}

String _normalizeAbsolutePath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(rawPath, 'path', 'empty_path');
  }
  if (!p.isAbsolute(trimmed)) {
    throw ArgumentError.value(rawPath, 'path', 'path_must_be_absolute');
  }
  return p.normalize(trimmed);
}

Map<String, Object?> _serializeTriggerRow(
  TriggerConfig trigger,
  TriggerState? state,
  {SettingsController? settingsController}) {
  final resolvedPollMinutes = settingsController == null
      ? (trigger.pollIntervalMinutes ?? trigger.intervalSpec?.every.inMinutes)
      : const TriggerPollingPolicy().resolvePollMinutes(
          trigger,
          settingsController,
        );
  return <String, Object?>{
    'id': trigger.id,
    'name': trigger.name,
    'type': trigger.type.name,
    'priority': trigger.priority.name,
    'enabled': trigger.enabled,
    'hour': trigger.scheduleSpec?.hour,
    'minute': trigger.scheduleSpec?.minute,
    'everyMinutes': trigger.intervalSpec?.every.inMinutes,
    'pollIntervalMinutes': trigger.pollIntervalMinutes,
    'resolvedPollMinutes': resolvedPollMinutes,
    'lastDecision': state?.lastDecision?.name,
    'lastDecisionReason': state?.lastDecisionReason,
    'lastRunAt': state?.lastRunAt?.toIso8601String(),
  };
}
