import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart';

import 'package:surabhi/config/sales_database.dart';

/// Append-only diagnostic log for bill print / 777 flow (no customer data).
class PrintLogService {
  static const String fileName = 'print_log.txt';
  static const int _maxLines = 500;

  static Future<File> _logFile() async {
    final dbPath = await SalesDatabase.salesDbPath();
    return File(join(dirname(dbPath), fileName));
  }

  static Future<void> append(String message) async {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final line = '$timestamp $message';
    try {
      final file = await _logFile();
      final existing = await file.exists() ? await file.readAsLines() : <String>[];
      final lines = [...existing, line];
      final trimmed = lines.length > _maxLines
          ? lines.sublist(lines.length - _maxLines)
          : lines;
      await file.writeAsString('${trimmed.join('\n')}\n');
    } catch (_) {
      // Logging must not break printing.
    }
  }
}
