import 'package:surabhi/db/local_db.dart';

/// Ensures item groups referenced in the legacy sales PDF exist in master.
class LegacyPdfMasterGroupsService {
  static const List<String> _requiredCanonicalUpper = ['SHIRT', 'T/JEANS'];

  /// Canonical name used when inserting a missing group (no duplicate casing).
  static const Map<String, String> _insertNameWhenMissing = {
    'SHIRT': 'Shirt',
    'T/JEANS': 'T/JEANS',
  };

  /// Runs on every staff login. Idempotent; never renames or removes groups.
  static Future<void> ensureOnStaffLogin() async {
    await LocalDb.instance.initialize();
    for (final upper in _requiredCanonicalUpper) {
      await _ensureGroup(upper);
    }
  }

  static Future<void> _ensureGroup(String upper) async {
    final names = await LocalDb.instance.listMasterItemNames();
    final exists = names.any((name) => name.toUpperCase() == upper);
    if (exists) {
      return;
    }

    final insertName = _insertNameWhenMissing[upper] ?? upper;
    try {
      await LocalDb.instance.insertMasterItem(insertName);
    } catch (_) {
      // Another login or import may have inserted concurrently.
    }
  }
}
