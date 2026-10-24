/// Display formatting for ledger GROUP column (comma-separated item groups).
class LedgerGroupDisplay {
  /// Target width so two typical names fit on one line, e.g. "GENTS WEAR, SHIRT".
  static const int maxCharsPerLine = 20;

  static String formatForDisplay(String groupSummary) {
    if (groupSummary.trim().isEmpty) {
      return '—';
    }
    return lines(groupSummary).join('\n');
  }

  /// Splits only after ", " between groups; never breaks inside a group name.
  static List<String> lines(String groupSummary) {
    final trimmed = groupSummary.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final parts = trimmed.split(', ');
    final result = <String>[];
    var current = '';

    for (final part in parts) {
      if (part.isEmpty) {
        continue;
      }
      final candidate = current.isEmpty ? part : '$current, $part';
      if (candidate.length <= maxCharsPerLine) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) {
        result.add(current);
      }
      current = part;
    }

    if (current.isNotEmpty) {
      result.add(current);
    }
    return result;
  }
}
