import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/config/sales_database.dart';
import 'package:surabhi/db/schema_migrations.dart';

Future<String> _salesDbPathForLocationCode(String locationCode) async {
  SalesDatabase.normalizeLocationCode(locationCode);
  return SalesDatabase.salesDbPath();
}

class DaySummaryRow {
  final String location;
  final String day;
  final double totalAmount;
  final double totalPcs;

  const DaySummaryRow({
    required this.location,
    required this.day,
    required this.totalAmount,
    required this.totalPcs,
  });
}

class MonthSummaryRow {
  final String location;
  final int year;
  final int month;
  final double totalAmount;
  final double totalPcs;

  const MonthSummaryRow({
    required this.location,
    required this.year,
    required this.month,
    required this.totalAmount,
    required this.totalPcs,
  });
}

/// Lightweight totals-only database for fast dashboard/abstract views.
class SummaryDb {
  static SummaryDb? _instance;

  Database? _database;
  Future<Database>? _openFuture;

  SummaryDb._();

  static SummaryDb get instance {
    _instance ??= SummaryDb._();
    return _instance!;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _instance?._database?.close();
    _instance?._database = null;
    _instance?._openFuture = null;
    _instance = null;
  }

  static const int _dbVersion = 3;
  static const String dbFileName = 'sales_summary.db';

  Future<void> initialize() async {
    await database;
    await ensureBootstrapped();
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    if (_database != null && !_database!.isOpen) {
      _database = null;
      _openFuture = null;
    }
    _openFuture ??= _openDb().then((db) {
      _database = db;
      return db;
    });
    return _openFuture!;
  }

  Future<Database> _openDb() async {
    final supportDir = await getApplicationSupportDirectory();
    final path = join(supportDir.path, dbFileName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 1) {
          await _createSchema(db);
        }
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _ensureTotalPcsColumns(db);
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE summary_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE day_summary (
        location TEXT NOT NULL,
        day TEXT NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0,
        total_pcs REAL NOT NULL DEFAULT 0,
        PRIMARY KEY (location, day)
      )
    ''');

    await db.execute('''
      CREATE TABLE month_summary (
        location TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0,
        total_pcs REAL NOT NULL DEFAULT 0,
        PRIMARY KEY (location, year, month)
      )
    ''');
  }

  Future<void> _ensureTotalPcsColumns(Database db) async {
    await addColumnIfMissing(
      db,
      'day_summary',
      'total_pcs',
      'REAL NOT NULL DEFAULT 0',
    );
    await addColumnIfMissing(
      db,
      'month_summary',
      'total_pcs',
      'REAL NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV2(Database db) async {
    await _ensureTotalPcsColumns(db);
    await _backfillPcsFromLocationBills(db);
  }

  Future<void> _backfillPcsFromLocationBills(Database db) async {
    await db.transaction((txn) async {
      for (final code in allLocationCodes) {
        final bills = await _readBillTotalsFromLocationFile(code);
        for (final bill in bills) {
          if (bill.totalPcs == 0) {
            continue;
          }
          await _applyDeltaInTxn(
            txn,
            location: bill.location,
            billDate: bill.billDate,
            delta: 0,
            pcsDelta: bill.totalPcs,
          );
        }
      }
    });
  }

  Future<bool> _isBootstrapped() async {
    final db = await database;
    final rows = await db.query(
      'summary_meta',
      where: 'key = ?',
      whereArgs: ['bootstrapped'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  Future<void> ensureBootstrapped() async {
    if (await isBootstrapped()) {
      return;
    }

    final db = await database;
    var importedRows = 0;
  var anyLocationDbExists = false;

    await db.transaction((txn) async {
      for (final code in allLocationCodes) {
        final path = await _salesDbPathForLocationCode(code);
        if (await File(path).exists()) {
          anyLocationDbExists = true;
        }

        final bills = await _readBillTotalsFromLocationFile(code);
        importedRows += bills.length;
        for (final bill in bills) {
          await _applyDeltaInTxn(
            txn,
            location: bill.location,
            billDate: bill.billDate,
            delta: bill.grandTotal,
            pcsDelta: bill.totalPcs,
          );
        }
      }

      if (importedRows > 0 || !anyLocationDbExists) {
        await txn.insert(
          'summary_meta',
          {'key': 'bootstrapped', 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @visibleForTesting
  Future<bool> isBootstrapped() => _isBootstrapped();

  static Future<List<({
    String location,
    DateTime billDate,
    double grandTotal,
    double totalPcs,
  })>> _readBillTotalsFromLocationFile(String locationCode) async {
    final path = await _salesDbPathForLocationCode(locationCode);
    if (!await File(path).exists()) {
      return const [];
    }

    final billDb = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final rows = await billDb.query(
        'bills',
        columns: ['location', 'bill_date', 'grand_total', 'total_qty'],
        where: 'deleted = 0',
      );

      return rows
          .map(
            (row) => (
              location: row['location'] as String,
              billDate: _parseBillDate(row['bill_date'] as String),
              grandTotal: (row['grand_total'] as num).toDouble(),
              totalPcs: (row['total_qty'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    } finally {
      await billDb.close();
    }
  }

  Future<void> applyBillDelta({
    required String location,
    required DateTime billDate,
    required double delta,
    double pcsDelta = 0,
  }) async {
    if (delta == 0 && pcsDelta == 0) {
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      await _applyDeltaInTxn(
        txn,
        location: location,
        billDate: billDate,
        delta: delta,
        pcsDelta: pcsDelta,
      );
    });
  }

  Future<void> _applyDeltaInTxn(
    DatabaseExecutor txn, {
    required String location,
    required DateTime billDate,
    required double delta,
    double pcsDelta = 0,
  }) async {
    final day = _dayKey(billDate);
    final year = billDate.year;
    final month = billDate.month;

    final dayRows = await txn.query(
      'day_summary',
      where: 'location = ? AND day = ?',
      whereArgs: [location, day],
      limit: 1,
    );

    final currentDay =
        (dayRows.firstOrNull?['total_amount'] as num?)?.toDouble() ?? 0;
    final currentDayPcs =
        (dayRows.firstOrNull?['total_pcs'] as num?)?.toDouble() ?? 0;
    final nextDay = currentDay + delta;
    final nextDayPcs = currentDayPcs + pcsDelta;
    if (nextDay.abs() < 0.0001 && nextDayPcs.abs() < 0.0001) {
      await txn.delete(
        'day_summary',
        where: 'location = ? AND day = ?',
        whereArgs: [location, day],
      );
    } else {
      await txn.insert(
        'day_summary',
        {
          'location': location,
          'day': day,
          'total_amount': nextDay,
          'total_pcs': nextDayPcs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final monthRows = await txn.query(
      'month_summary',
      where: 'location = ? AND year = ? AND month = ?',
      whereArgs: [location, year, month],
      limit: 1,
    );

    final currentMonth =
        (monthRows.firstOrNull?['total_amount'] as num?)?.toDouble() ?? 0;
    final currentMonthPcs =
        (monthRows.firstOrNull?['total_pcs'] as num?)?.toDouble() ?? 0;
    final nextMonth = currentMonth + delta;
    final nextMonthPcs = currentMonthPcs + pcsDelta;
    if (nextMonth.abs() < 0.0001 && nextMonthPcs.abs() < 0.0001) {
      await txn.delete(
        'month_summary',
        where: 'location = ? AND year = ? AND month = ?',
        whereArgs: [location, year, month],
      );
    } else {
      await txn.insert(
        'month_summary',
        {
          'location': location,
          'year': year,
          'month': month,
          'total_amount': nextMonth,
          'total_pcs': nextMonthPcs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<double> getTotalForDay({
    required String day,
    String? location,
  }) async {
    final db = await database;
    if (location != null) {
      final rows = await db.query(
        'day_summary',
        columns: ['total_amount'],
        where: 'location = ? AND day = ?',
        whereArgs: [location, day],
        limit: 1,
      );
      return (rows.firstOrNull?['total_amount'] as num?)?.toDouble() ?? 0;
    }

    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total FROM day_summary WHERE day = ?',
      [day],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getTodayTotalAllLocations() {
    return getTotalForDay(day: _dayKey(DateTime.now()));
  }

  Future<List<DaySummaryRow>> getDayTotalsForMonth({
    required int year,
    required int month,
    String? location,
  }) async {
    final db = await database;
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';

    final rows = location == null
        ? await db.rawQuery(
            '''
            SELECT day,
                   SUM(total_amount) AS total_amount,
                   SUM(total_pcs) AS total_pcs
            FROM day_summary
            WHERE day LIKE ?
            GROUP BY day
            ORDER BY day DESC
            ''',
            ['$prefix%'],
          )
        : await db.query(
            'day_summary',
            where: 'location = ? AND day LIKE ?',
            whereArgs: [location, '$prefix%'],
            orderBy: 'day DESC',
          );

    return rows
        .map(
          (row) => DaySummaryRow(
            location: location ?? 'ALL',
            day: row['day'] as String,
            totalAmount: (row['total_amount'] as num).toDouble(),
            totalPcs: (row['total_pcs'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<MonthSummaryRow>> getMonthTotalsForYear({
    required int year,
    String? location,
  }) async {
    final db = await database;
    final rows = location == null
        ? await db.rawQuery(
            '''
            SELECT month,
                   SUM(total_amount) AS total_amount,
                   SUM(total_pcs) AS total_pcs
            FROM month_summary
            WHERE year = ?
            GROUP BY month
            ORDER BY month ASC
            ''',
            [year],
          )
        : await db.query(
            'month_summary',
            where: 'location = ? AND year = ?',
            whereArgs: [location, year],
            orderBy: 'month ASC',
          );

    return rows
        .map(
          (row) => MonthSummaryRow(
            location: location ?? 'ALL',
            year: year,
            month: row['month'] as int,
            totalAmount: (row['total_amount'] as num).toDouble(),
            totalPcs: (row['total_pcs'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// Rebuilds day/month summary buckets from live bill rows (grand total + PCS).
  Future<void> rebuildSummariesForDays({
    required String location,
    required Iterable<DateTime> days,
  }) async {
    final db = await database;
    final uniqueDays = days
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList(growable: false);

    final aggregates = await _aggregateBillsByDay(location);
    final monthsToRebuild = <(int, int)>{};

    await db.transaction((txn) async {
      for (final day in uniqueDays) {
        final key = _dayKey(day);
        final totals = aggregates[key] ?? (amount: 0.0, pcs: 0.0);
        monthsToRebuild.add((day.year, day.month));

        if (totals.amount.abs() < 0.0001 && totals.pcs.abs() < 0.0001) {
          await txn.delete(
            'day_summary',
            where: 'location = ? AND day = ?',
            whereArgs: [location, key],
          );
        } else {
          await txn.insert(
            'day_summary',
            {
              'location': location,
              'day': key,
              'total_amount': totals.amount,
              'total_pcs': totals.pcs,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      for (final ym in monthsToRebuild) {
        await _rebuildMonthInTxn(
          txn,
          location: location,
          year: ym.$1,
          month: ym.$2,
        );
      }
    });
  }

  Future<Map<String, ({double amount, double pcs})>> _aggregateBillsByDay(
    String location,
  ) async {
    final code = locationCodeFromDisplayName(location);
    final path = await _salesDbPathForLocationCode(code);
    if (!await File(path).exists()) {
      return {};
    }

    final billDb = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final rows = await billDb.query(
        'bills',
        columns: ['bill_date', 'grand_total', 'total_qty'],
        where: 'deleted = 0 AND location = ?',
        whereArgs: [location],
      );

      final map = <String, ({double amount, double pcs})>{};
      for (final row in rows) {
        final day = row['bill_date'] as String;
        final bucket = map.putIfAbsent(day, () => (amount: 0.0, pcs: 0.0));
        map[day] = (
          amount: bucket.amount + (row['grand_total'] as num).toDouble(),
          pcs: bucket.pcs + (row['total_qty'] as num).toDouble(),
        );
      }
      return map;
    } finally {
      await billDb.close();
    }
  }

  Future<void> _rebuildMonthInTxn(
    Transaction txn, {
    required String location,
    required int year,
    required int month,
  }) async {
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
    final rows = await txn.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0) AS total_amount,
        COALESCE(SUM(total_pcs), 0) AS total_pcs
      FROM day_summary
      WHERE location = ? AND day LIKE ?
      ''',
      [location, '$prefix%'],
    );

    final amount = (rows.first['total_amount'] as num?)?.toDouble() ?? 0;
    final pcs = (rows.first['total_pcs'] as num?)?.toDouble() ?? 0;

    if (amount.abs() < 0.0001 && pcs.abs() < 0.0001) {
      await txn.delete(
        'month_summary',
        where: 'location = ? AND year = ? AND month = ?',
        whereArgs: [location, year, month],
      );
      return;
    }

    await txn.insert(
      'month_summary',
      {
        'location': location,
        'year': year,
        'month': month,
        'total_amount': amount,
        'total_pcs': pcs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getTotalPcsForDay({
    required String day,
    String? location,
  }) async {
    final db = await database;
    if (location != null) {
      final rows = await db.query(
        'day_summary',
        columns: ['total_pcs'],
        where: 'location = ? AND day = ?',
        whereArgs: [location, day],
        limit: 1,
      );
      return (rows.firstOrNull?['total_pcs'] as num?)?.toDouble() ?? 0;
    }

    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_pcs), 0) AS total FROM day_summary WHERE day = ?',
      [day],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getRangeTotal({
    required DateTime fromDate,
    required DateTime toDate,
    String? location,
  }) async {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    var total = 0.0;
    var cursor = from;
    while (!cursor.isAfter(to)) {
      total += await getTotalForDay(
        day: _dayKey(cursor),
        location: location,
      );
      cursor = cursor.add(const Duration(days: 1));
    }
    return total;
  }


  static String _dayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime _parseBillDate(String value) {
    final parts = value.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return DateTime.parse(value);
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
