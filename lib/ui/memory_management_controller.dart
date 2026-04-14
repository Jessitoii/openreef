import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/models/embedding_model_manager.dart';

class MemoryFilterState {
  const MemoryFilterState({
    this.store,
    this.category = '',
    this.metadataText = '',
    this.showExpired = true,
    this.search = '',
  });

  final MemoryStoreKind? store;
  final String category;
  final String metadataText;
  final bool showExpired;
  final String search;

  MemoryFilterState copyWith({
    MemoryStoreKind? store,
    String? category,
    String? metadataText,
    bool? showExpired,
    String? search,
    bool clearStore = false,
  }) {
    return MemoryFilterState(
      store: clearStore ? null : store ?? this.store,
      category: category ?? this.category,
      metadataText: metadataText ?? this.metadataText,
      showExpired: showExpired ?? this.showExpired,
      search: search ?? this.search,
    );
  }
}

class MemoryManagementController extends ChangeNotifier {
  static const int _maxVisibleRecords = 300;

  MemoryManagementController({
    required MemoryStorage storage,
    required MemoryIndex memoryIndex,
    EmbeddingModelManager? embeddingModelManager,
  })  : _storage = storage,
        _memoryIndex = memoryIndex,
        _embedder = embeddingModelManager == null
            ? null
            : ManagedSemanticTextEmbedder(embeddingModelManager);

  final MemoryStorage _storage;
  final MemoryIndex _memoryIndex;
  final SemanticTextEmbedder? _embedder;
  final Map<String, MemoryRecord> _recordsByKey = <String, MemoryRecord>{};

  bool _initialized = false;
  bool _loading = false;
  bool _mutating = false;
  String? _errorMessage;
  String? _warningMessage;
  String? _selectedKey;
  MemoryFilterState _filters = const MemoryFilterState();

  bool get isLoading => _loading;
  bool get isMutating => _mutating;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;
  MemoryFilterState get filters => _filters;
  List<MemoryRecord> get allRecords =>
      _recordsByKey.values.toList(growable: false)
        ..sort((left, right) {
          return right.createdAt.compareTo(left.createdAt);
        });

  List<MemoryRecord> get filteredRecords {
    final search = _filters.search.trim().toLowerCase();
    final metadataText = _filters.metadataText.trim().toLowerCase();
    final filtered = allRecords.where((record) {
      if (!_filters.showExpired && record.isExpired) {
        return false;
      }
      if (_filters.store != null && record.store != _filters.store) {
        return false;
      }
      if (_filters.category.trim().isNotEmpty &&
          record.category.toLowerCase() != _filters.category.trim().toLowerCase()) {
        return false;
      }
      if (search.isEmpty) {
        if (metadataText.isEmpty) {
          return true;
        }
        return _metadataText(record).contains(metadataText);
      }
      final combinedMetadata = _metadataText(record);
      return record.key.toLowerCase().contains(search) ||
          record.content.toLowerCase().contains(search) ||
          record.category.toLowerCase().contains(search) ||
          combinedMetadata.contains(search);
    }).toList(growable: false);
    return filtered;
  }

  List<MemoryRecord> get visibleRecords {
    final filtered = filteredRecords;
    if (filtered.length <= _maxVisibleRecords) {
      return filtered;
    }
    return filtered.take(_maxVisibleRecords).toList(growable: false);
  }

  bool get hasMoreThanVisibleLimit => filteredRecords.length > _maxVisibleRecords;

  int get visibleRecordsCount {
    final visible = visibleRecords.length;
    return visible;
  }

  MemoryRecord? get selectedRecord {
    final key = _selectedKey;
    if (key == null) {
      return null;
    }
    return _recordsByKey[key];
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    _errorMessage = null;
    _warningMessage = null;
    notifyListeners();
    try {
      final report = await _storage.readRecordsWithReport(includeExpired: true);
      final records = report.records;
      _recordsByKey
        ..clear()
        ..addEntries(records.map((record) => MapEntry(record.key, record)));
      if (report.skippedCount > 0) {
        _warningMessage =
            'Skipped ${report.skippedCount} corrupted memory row${report.skippedCount == 1 ? '' : 's'} during load.';
      }
      if (_selectedKey == null || !_recordsByKey.containsKey(_selectedKey)) {
        _selectedKey = _recordsByKey.keys.isNotEmpty
            ? _recordsByKey.keys.first
            : null;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void selectRecord(String? key) {
    if (_selectedKey == key) {
      return;
    }
    _selectedKey = key;
    notifyListeners();
  }

  void updateFilters(MemoryFilterState filters) {
    _filters = filters;
    notifyListeners();
  }

  void resetFilters() {
    _filters = const MemoryFilterState();
    notifyListeners();
  }

  String _metadataText(MemoryRecord record) {
    return record.metadata.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ')
        .toLowerCase();
  }

  Future<void> saveRecord(MemoryRecord record, {MemoryRecord? previousRecord}) async {
    _mutating = true;
    _errorMessage = null;
    _warningMessage = null;
    notifyListeners();
    try {
      final preparedEmbedding = record.store == MemoryStoreKind.longTerm
          ? await _prepareEmbedding(record)
          : null;
      final result = await _storage.saveRecordSafely(
        record,
        previousRecord: previousRecord,
        preparedEmbedding: preparedEmbedding,
        rebuildIndex: record.store == MemoryStoreKind.longTerm ||
                previousRecord?.store == MemoryStoreKind.longTerm
            ? _memoryIndex.rebuild
            : null,
      );
      if (!result.isSuccess) {
        _errorMessage = result.message;
        throw StateError(result.message);
      }
      await reload();
      _selectedKey = record.key;
    } catch (error) {
      _errorMessage ??= error.toString();
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<void> deleteRecord(MemoryRecord record) async {
    _mutating = true;
    _errorMessage = null;
    _warningMessage = null;
    notifyListeners();
    try {
      final result = await _storage.deleteRecordSafely(
        record,
        rebuildIndex: record.store == MemoryStoreKind.longTerm
            ? _memoryIndex.rebuild
            : null,
      );
      if (!result.isSuccess) {
        _errorMessage = result.message;
        throw StateError(result.message);
      }
      await reload();
      if (_selectedKey == record.key) {
        _selectedKey = _recordsByKey.keys.isNotEmpty ? _recordsByKey.keys.first : null;
      }
    } catch (error) {
      _errorMessage ??= error.toString();
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<void> bulkDelete({
    MemoryStoreKind? store,
    String? category,
    bool includeExpired = true,
  }) async {
    _mutating = true;
    _errorMessage = null;
    _warningMessage = null;
    notifyListeners();
    try {
      final scoped = filteredRecords.where((record) {
        if (store != null && record.store != store) {
          return false;
        }
        if (category != null &&
            category.isNotEmpty &&
            record.category != category) {
          return false;
        }
        if (!includeExpired && record.isExpired) {
          return false;
        }
        return true;
      }).toList(growable: false);
      final result = await _storage.deleteRecordsSafely(
        scoped,
        rebuildIndex: scoped.any((record) => record.store == MemoryStoreKind.longTerm)
            ? _memoryIndex.rebuild
            : null,
      );
      if (!result.isSuccess) {
        _errorMessage = result.message;
        throw StateError(result.message);
      }
      await reload();
      _selectedKey = _recordsByKey.keys.isNotEmpty ? _recordsByKey.keys.first : null;
    } catch (error) {
      _errorMessage ??= error.toString();
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<MemoryEmbeddingRecord?> _prepareEmbedding(MemoryRecord record) async {
    final embedder = _embedder;
    if (embedder == null) {
      return null;
    }
    final embedding = await embedder.embedDocument(record.content);
    return MemoryEmbeddingRecord(
      memoryKey: record.key,
      modelId: embedder.modelId,
      embedding: embedding,
      normalizedContent: record.content.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
      updatedAt: DateTime.now().toUtc(),
    );
  }
}
