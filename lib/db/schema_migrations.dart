import 'package:sqflite/sqflite.dart';

/// Adds a column only when it is missing (safe to run on every upgrade step).
Future<void> addColumnIfMissing(
  Database db,
  String table,
  String column,
  String definition,
) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  final exists = cols.any((c) => c['name'] == column);
  if (!exists) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
