import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/bill_repository.dart';
import 'package:surabhi/screen/bill_item.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

SaleBill _sampleBill({int billNo = 1, double rate = 100}) {
  return SaleBill(
    billNo: billNo,
    location: 'Surabhi',
    billDate: DateTime(2026, 9, 3),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [BillItem(qty: 1, rate: rate)],
    totalQty: 1,
    totalAmount: rate,
    totalCgst: 2.5,
    totalSgst: 2.5,
    totalIgst: 0,
    grandTotal: rate + 5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('bill_repository_test_');
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

  test('offline save uses next free bill number when number is taken', () async {
    final bill = _sampleBill();
    await LocalDb.instance.insertPendingBill(bill);

    final updated = _sampleBill(rate: 137);
    final result = await BillRepository.saveBill(updated);

    expect(result.ok, isTrue);
    expect(result.data, 2);

    final stored = await LocalDb.instance.getBillByNumber(
      location: 'Surabhi',
      billNo: 2,
    );
    expect(stored?.bill.totalAmount, 137);

    final original = await LocalDb.instance.getBillByNumber(
      location: 'Surabhi',
      billNo: 1,
    );
    expect(original?.bill.totalAmount, 100);
  });
}
