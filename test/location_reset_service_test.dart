import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/config/sales_database.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/location_reset_service.dart';
import 'package:surabhi/services/session_service.dart';

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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('location_reset_test_');
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
    final file = File(join(tempDir.path, SalesDatabase.salesDbFileName));
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('only main is an active location code', () {
    expect(isActiveLocationCode('main'), isTrue);
    expect(isActiveLocationCode('win1'), isFalse);
    expect(isActiveLocationCode('win4'), isFalse);
    expect(allLocationCodes, ['main']);
  });

  test('branch label maps to Surabhi Export', () {
    expect(branchLabelForLocationCode('main'), 'Surabhi Export');
  });

  test('reset clears local bills and bill session', () async {
    final location = AppConfig.displayLocationName;
    final bill = SaleBill(
      billNo: 1,
      location: location,
      billDate: DateTime(2026, 9, 1),
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
    await LocalDb.instance.insertBill(bill, syncStatus: 'local');
    await SessionService.saveBillSession(
      location: location,
      billNo: 5,
      billDate: DateTime.now(),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: const [],
      billSaved: false,
    );

    final result = await LocationResetService.resetCurrentLocation(
      locationDisplayName: location,
      password: 'SURABHI',
    );

    expect(result.ok, isTrue);
    expect(result.localCleared, isTrue);

    final stored = await LocalDb.instance.getBillByNumber(
      location: location,
      billNo: 1,
    );
    expect(stored, isNull);
    expect(await LocalDb.instance.getNextBillNumber(location), 1);
    expect(await SessionService.loadBillSession(), isNull);
  });
}
