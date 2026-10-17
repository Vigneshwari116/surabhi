import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/bill_repository.dart';
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

SaleBill _minimalBill({required int billNo, required String location}) {
  final item = BillItem(particular: 'Shirt', qty: 1, rate: 100);
  return SaleBill(
    billNo: billNo,
    location: location,
    billDate: OldSalesImportService.importDay,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('next_bill_number_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppConfig.setLocation('main');
    await LocalDb.resetForTesting();
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('next bill number is 8 after bills 1-7, then 9 after save', () async {
    final location = AppConfig.displayLocationName;

    for (var billNo = 1; billNo <= 7; billNo++) {
      await LocalDb.instance.insertBill(
        _minimalBill(billNo: billNo, location: location),
        syncStatus: 'synced',
      );
    }

    await LocalDb.instance.refreshNextBillNoFromBills(location);
    expect(await BillRepository.getNextBillNumber(location), 8);

    final newBill = _minimalBill(billNo: 1, location: location);
    final result = await BillRepository.saveBill(newBill);
    expect(result.ok, isTrue);
    expect(result.billNo, 8);

    expect(await BillRepository.getNextBillNumber(location), 9);
  });
}
