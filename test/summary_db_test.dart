import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/local_credentials.dart';
import 'package:surabhi/db/summary_db.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('summary_db_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await SummaryDb.resetForTesting();
  });

  tearDown(() async {
    await SummaryDb.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('opening summary db twice does not fail when total_pcs exists', () async {
    final path = join(tempDir.path, SummaryDb.dbFileName);
    await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
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
      },
    );

    final db = SummaryDb.instance;
    await db.initialize();
    await db.initialize();

    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 9, 7),
      delta: 100,
      pcsDelta: 2,
    );
    expect(
      await db.getTotalForDay(day: '2026-09-07', location: 'Surabhi'),
      100,
    );
  });

  test('applyBillDelta increments day and month totals', () async {
    final db = SummaryDb.instance;
    await db.initialize();

    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 9, 5),
      delta: 1000,
    );
    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 9, 5),
      delta: 500,
    );

    expect(
      await db.getTotalForDay(day: '2026-09-05', location: 'Surabhi'),
      1500,
    );

    final months = await db.getMonthTotalsForYear(year: 2026, location: 'Surabhi');
    expect(months.single.month, 9);
    expect(months.single.totalAmount, 1500);
  });

  test('applyBillDelta increments pcs totals', () async {
    final db = SummaryDb.instance;
    await db.initialize();

    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 9, 6),
      delta: 500,
      pcsDelta: 12,
    );
    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 9, 6),
      delta: 0,
      pcsDelta: 3,
    );

    final days = await db.getDayTotalsForMonth(
      year: 2026,
      month: 9,
      location: 'Surabhi',
    );
    final day = days.firstWhere((row) => row.day == '2026-09-06');
    expect(day.totalPcs, 15);
  });

  test('applyBillDelta can subtract on edit/delete', () async {
    final db = SummaryDb.instance;
    await db.initialize();

    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 8, 1),
      delta: 800,
    );
    await db.applyBillDelta(
      location: 'Surabhi',
      billDate: DateTime(2026, 8, 1),
      delta: -300,
    );

    expect(
      await db.getTotalForDay(day: '2026-08-01', location: 'Surabhi'),
      500,
    );
  });

  test('summary viewer credentials are accepted', () {
    expect(verifySummaryViewerLogin('SUMMARY', 'summary'), isTrue);
    expect(verifySummaryViewerLogin('summary', 'summary'), isTrue);
    expect(verifySummaryViewerLogin('SUMMARY', 'wrong'), isFalse);
    expect(verifySummaryViewerLogin('admin', 'admin123'), isFalse);
  });
}
