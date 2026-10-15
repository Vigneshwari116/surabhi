import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/db/summary_db.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/services/old_sales_import_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('old_sales_import_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.setLocation('main');
    await LocalDb.resetForTesting();
    await SummaryDb.resetForTesting();
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await SummaryDb.resetForTesting();
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('import loads table B totals for 13 Oct 2026', () async {
    final report = await OldSalesImportService.runImport();

    expect(report.billsImported, 7);
    expect(report.billsSkipped, 0);
    expect(report.rowsImported, 15);
    expect(report.blankPaymentBillNos, [4, 7]);

    final location = AppConfig.displayLocationName;
    final day = OldSalesImportService.importDay;

    final summary = await AbstractRepository.getSummaryForDateRange(
      location: location,
      fromDate: day,
      toDate: day,
    );
    expect(summary.totalSaleAmount, 12950);
    expect(summary.totalGst, 650);
    expect(summary.totalSaleAmount + summary.totalGst, 13600);
    expect(summary.totalPcs, 18);

    expect(await OldSalesImportService.verifyTableBTotals(location), isTrue);

    await SummaryDb.instance.initialize();
    final summaryPcs = await SummaryDb.instance.getTotalPcsForDay(
      day: '2026-10-13',
      location: location,
    );
    expect(summaryPcs, 18);

    final second = await OldSalesImportService.runImport();
    expect(second.billsImported, 0);
    expect(second.billsSkipped, 7);
    expect(second.rowsImported, 0);
  });
}
