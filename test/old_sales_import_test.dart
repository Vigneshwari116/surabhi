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
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/old_sales_import_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

SaleBill _seedBill({required int billNo, required String location}) {
  final item = BillItem(particular: 'SHIRT', qty: 1, rate: 100);
  return SaleBill(
    billNo: billNo,
    location: location,
    billDate: DateTime(2026, 10, 13),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [item],
    totalQty: item.qty,
    totalAmount: item.amount,
    totalCgst: item.cgst,
    totalSgst: item.sgst,
    totalIgst: item.igst,
    grandTotal: item.grossAmt,
  );
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
    final dir = await getApplicationSupportDirectory();
    final dbFile = File('${dir.path}/main_sales.db');
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await SummaryDb.resetForTesting();
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('full import matches table A for 11 Oct 2026 and next bill is 239', () async {
    final report = await OldSalesImportService.runImport();

    expect(report.billsImported, 238);
    expect(report.billsSkipped, 0);
    expect(report.rowsImported, 482);
    expect(report.rowsSkipped, 1);
    expect(report.blankPaymentBillNos.length, 173);

    final location = AppConfig.displayLocationName;
    final day = OldSalesImportService.importDay;

    final summary = await AbstractRepository.getSummaryForDateRange(
      location: location,
      fromDate: day,
      toDate: day,
    );
    expect(summary.totalSaleAmount, closeTo(47571.44, 0.01));
    expect(summary.totalGst, closeTo(2378.56, 0.01));
    expect(summary.totalSaleAmount + summary.totalGst, closeTo(49950, 0.01));
    expect(summary.totalPcs, 281);

    expect(await OldSalesImportService.verifyTableBTotals(location), isTrue);

    await SummaryDb.instance.initialize();
    final summaryPcs = await SummaryDb.instance.getTotalPcsForDay(
      day: '2026-10-11',
      location: location,
    );
    expect(summaryPcs, 281);

    final next = await LocalDb.instance.peekNextBillNoFromBills(location);
    expect(next, 239);

    final second = await OldSalesImportService.runImport();
    expect(second.billsImported, 0);
    expect(second.billsSkipped, 238);
    expect(second.rowsImported, 0);
  });

  test('skips existing bill numbers without overwriting', () async {
    final location = AppConfig.displayLocationName;
    for (var n = 1; n <= 7; n++) {
      await LocalDb.instance.insertBill(
        _seedBill(billNo: n, location: location),
        syncStatus: 'synced',
      );
    }

    final report = await OldSalesImportService.runImport();
    expect(report.billsImported, 231);
    expect(report.billsSkipped, 7);
    expect(report.skippedExistingBillNos, [1, 2, 3, 4, 5, 6, 7]);
    expect(report.rowsImported, 462);

    final day = OldSalesImportService.importDay;
    final summary = await AbstractRepository.getSummaryForDateRange(
      location: location,
      fromDate: day,
      toDate: day,
    );
    // Bills 1–7 on 11 Oct are not in DB (skipped); only 8–54 from the file.
    expect(summary.totalPcs, 236);
    expect(summary.totalSaleAmount, closeTo(38809.52, 0.02));
    expect(summary.totalGst, closeTo(1940.48, 0.02));
  });
}
