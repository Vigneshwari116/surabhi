import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:surabhi/config/sales_database.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/utils/system_clock.dart';

class BackupResult {
  final bool ok;
  final String? folderPath;
  final String? error;

  const BackupResult.success(this.folderPath)
      : ok = true,
        error = null;

  const BackupResult.failure(this.error)
      : ok = false,
        folderPath = null;
}

/// Copies [main_sales.db] to a timestamped folder on the Desktop (or Documents).
class BackupService {
  BackupService({
    Future<String> Function()? resolveDesktopDirectory,
    DateTime Function()? now,
    Future<Database> Function()? openDatabase,
    Future<int> Function()? countBills,
  })  : _resolveDesktopDirectory =
            resolveDesktopDirectory ?? _defaultDesktopDirectory,
        _now = now ?? SystemClock.now,
        _openDatabase = openDatabase ?? (() => LocalDb.instance.database),
        _countBills = countBills ?? (() => LocalDb.instance.countActiveBills());

  static final BackupService instance = BackupService();

  final Future<String> Function() _resolveDesktopDirectory;
  final DateTime Function() _now;
  final Future<Database> Function() _openDatabase;
  final Future<int> Function() _countBills;

  static Future<String> _defaultDesktopDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final candidates = <String>[
          p.join(userProfile, 'Desktop'),
          p.join(userProfile, 'OneDrive', 'Desktop'),
        ];
        for (final key in [
          'OneDriveCommercial',
          'OneDrive',
          'OneDriveConsumer',
        ]) {
          final root = Platform.environment[key];
          if (root != null && root.isNotEmpty) {
            candidates.add(p.join(root, 'Desktop'));
          }
        }
        for (final path in candidates) {
          if (await Directory(path).exists()) {
            return path;
          }
        }
      }
    }

    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final desktop = p.join(home, 'Desktop');
        if (await Directory(desktop).exists()) {
          return desktop;
        }
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  String _folderBaseName(DateTime timestamp) {
    final date = DateFormat('yyyy-MM-dd').format(timestamp);
    final time = DateFormat('HH-mm-ss').format(timestamp);
    return 'Surabhi_Backup_${date}_$time';
  }

  Future<Directory> _allocateBackupDirectory(String parentPath, DateTime ts) async {
    final base = _folderBaseName(ts);
    var suffix = 0;
    while (true) {
      final name = suffix == 0 ? base : '${base}_$suffix';
      final dir = Directory(p.join(parentPath, name));
      if (!await dir.exists()) {
        return dir;
      }
      suffix++;
    }
  }

  Future<void> _vacuumInto(Database db, String destPath) async {
    final escaped = destPath.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");
  }

  Future<BackupResult> runBackup({required String locationName}) async {
    Directory? createdDir;
    try {
      final parentPath = await _resolveDesktopDirectory();
      final timestamp = _now();
      createdDir = await _allocateBackupDirectory(parentPath, timestamp);
      await createdDir.create(recursive: true);

      final billCount = await _countBills();
      final db = await _openDatabase();
      final destDb = p.join(createdDir.path, SalesDatabase.salesDbFileName);
      await _vacuumInto(db, destDb);

      final info = [
        'Date: ${DateFormat('yyyy-MM-dd').format(timestamp)}',
        'Time: ${DateFormat('HH:mm:ss').format(timestamp)}',
        'Location: $locationName',
        'Bill count: $billCount',
      ].join('\n');
      await File(p.join(createdDir.path, 'backup_info.txt')).writeAsString(info);

      return BackupResult.success(createdDir.path);
    } catch (e) {
      if (createdDir != null && await createdDir.exists()) {
        try {
          await createdDir.delete(recursive: true);
        } catch (_) {
          // Best-effort cleanup after failure.
        }
      }
      return BackupResult.failure(e.toString());
    }
  }
}
