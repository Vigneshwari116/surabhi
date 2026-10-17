import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/sales_database.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/backup_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

SaleBill _sampleBill(int billNo) {
  return SaleBill(
    billNo: billNo,
    location: 'Surabhi',
    billDate: DateTime(2026, 9, 3),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [BillItem(qty: 1, rate: 100)],
    totalQty: 1,
    totalAmount: 100,
    totalCgst: 2.5,
    totalSgst: 2.5,
    totalIgst: 0,
    grandTotal: 105,
  );
}

void main() {
  late Directory supportDir;
  late Directory desktopDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('backup_support_');
    desktopDir = await Directory.systemTemp.createTemp('backup_desktop_');
    PathProviderPlatform.instance = _FakePathProvider(supportDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
    if (await desktopDir.exists()) {
      await desktopDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation('main');
    await LocalDb.resetForTesting();
    final dbPath = p.join(supportDir.path, SalesDatabase.salesDbFileName);
    for (final path in [
      dbPath,
      '$dbPath-wal',
      '$dbPath-shm',
      '$dbPath-journal',
    ]) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await LocalDb.instance.initialize();
    await LocalDb.instance.insertPendingBill(_sampleBill(1));
    await LocalDb.instance.insertPendingBill(_sampleBill(2));
    if (await desktopDir.exists()) {
      for (final entity in desktopDir.listSync()) {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else if (entity is File) {
          await entity.delete();
        }
      }
    }
    final summaryFile = File(p.join(supportDir.path, 'sales_summary.db'));
    if (!await summaryFile.exists()) {
      await summaryFile.writeAsString('summary placeholder');
    }
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  BackupService _service({
    DateTime Function()? now,
    Future<Database> Function()? openDatabase,
  }) {
    return BackupService(
      resolveDesktopDirectory: () async => desktopDir.path,
      now: now,
      openDatabase: openDatabase ?? (() => LocalDb.instance.database),
      countBills: () => LocalDb.instance.countActiveBills(),
    );
  }

  test('two backups create two distinct folders with valid databases', () async {
    var tick = 0;
    final service = _service(
      now: () {
        tick++;
        return DateTime(2026, 10, 16, 14, 35, 20 + tick);
      },
    );

    final first = await service.runBackup(locationName: 'Surabhi');
    final second = await service.runBackup(locationName: 'Surabhi');

    expect(first.ok, isTrue);
    expect(second.ok, isTrue);
    expect(first.folderPath, isNot(equals(second.folderPath)));

    final liveCount = await LocalDb.instance.countActiveBills();

    for (final path in [first.folderPath!, second.folderPath!]) {
      final dir = Directory(path!);
      expect(await dir.exists(), isTrue);

      final dbFile = File(p.join(path, SalesDatabase.salesDbFileName));
      expect(await dbFile.exists(), isTrue);
      expect(await dbFile.length(), greaterThan(0));

      expect(
        File(p.join(path, SalesDatabase.summaryDbFileName)).existsSync(),
        isFalse,
      );

      final backupDb = await openDatabase(dbFile.path);
      final rows = await backupDb.rawQuery(
        'SELECT COUNT(*) AS c FROM bills WHERE deleted = 0',
      );
      final count = Sqflite.firstIntValue(rows) ?? 0;
      await backupDb.close();
      expect(count, liveCount);

      final info = await File(p.join(path, 'backup_info.txt')).readAsString();
      expect(info, contains('Bill count: $liveCount'));
    }
  });

  test('failure reports error and removes empty backup folder', () async {
    final service = BackupService(
      resolveDesktopDirectory: () async => desktopDir.path,
      now: () => DateTime(2026, 10, 16, 9, 0, 0),
      openDatabase: () async {
        throw StateError('db locked');
      },
      countBills: () => LocalDb.instance.countActiveBills(),
    );

    final before = desktopDir.listSync().whereType<Directory>().length;
    final result = await service.runBackup(locationName: 'Surabhi');
    final after = desktopDir.listSync().whereType<Directory>().length;

    expect(result.ok, isFalse);
    expect(result.error, contains('db locked'));
    expect(after, before);
  });
}
