import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'package:surabhi/config/location_codes.dart';

/// Single active SQLite file for all Surabhi sales bills and ledger data.
class SalesDatabase {
  static const String activeLocationCode = activeSalesLocationCode; // main

  /// Fixed filename — never `win1_sales.db` etc.
  static const String salesDbFileName = 'main_sales.db';

  static const String summaryDbFileName = 'sales_summary.db';

  /// Resolves the path to the active sales database under app support.
  static Future<String> salesDbPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return join(supportDir.path, salesDbFileName);
  }

  /// Legacy per-code filenames (e.g. win1_sales.db) are not opened by the app.
  static bool isLegacySalesDbFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower == salesDbFileName) {
      return false;
    }
    return lower.endsWith('_sales.db');
  }

  /// Maps display names / legacy codes to the single active location code.
  static String normalizeLocationCode(String codeOrName) {
    final trimmed = codeOrName.trim();
    if (trimmed.isEmpty) {
      return activeLocationCode;
    }
    switch (trimmed.toLowerCase()) {
      case 'surabhi':
      case 'main':
      case 'win1':
      case 'win2':
      case 'win3':
      case 'win4':
        return activeLocationCode;
      default:
        return locationCodeFromDisplayName(trimmed);
    }
  }
}
