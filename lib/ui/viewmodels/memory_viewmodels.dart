import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_store_kind.dart';

class MemoryViewModel {
  const MemoryViewModel({
    required this.key, // Only used internally for operations, not displayed
    required this.content,
    required this.storeLabel,
    required this.categoryLabel,
    required this.importanceChips, // e.g. 3 out of 5
    required this.detailsMap,
    required this.createdLabel,
    required this.isExpired,
  });

  final String key;
  final String content;
  final String storeLabel;
  final String categoryLabel;
  final int importanceChips;
  final Map<String, String> detailsMap;
  final String createdLabel;
  final bool isExpired;

  factory MemoryViewModel.fromDomain(MemoryRecord record) {
    String mappedStore = 'System Data';
    switch (record.store) {
      case MemoryStoreKind.shortTerm:
        mappedStore = 'Temporary context';
        break;
      case MemoryStoreKind.longTerm:
        mappedStore = 'Learned memory';
        break;
      case MemoryStoreKind.episodic:
        mappedStore = 'History';
        break;
      case MemoryStoreKind.skillState:
        mappedStore = 'Internal state';
        break;
      case MemoryStoreKind.mcpConnections:
        mappedStore = 'Connection data';
        break;
    }

    final Map<String, String> details = {};
    if (record.metadata.isNotEmpty) {
      for (final entry in record.metadata.entries) {
        details[entry.key] = entry.value.toString();
      }
    }

    final isExpired = record.expiresAt != null && record.expiresAt!.isBefore(DateTime.now());

    return MemoryViewModel(
      key: record.key,
      content: record.content,
      storeLabel: mappedStore,
      categoryLabel: record.category.isNotEmpty ? record.category : 'General',
      importanceChips: record.importance.clamp(1, 5),
      detailsMap: details,
      createdLabel: _formatDate(record.createdAt),
      isExpired: isExpired,
    );
  }

  static String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
