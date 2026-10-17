import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:surabhi/screen/sales_bill_screen.dart';
import 'package:surabhi/services/session_service.dart';
import 'package:surabhi/utils/system_clock.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

String _displayDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

SaleBill _savedBill({
  required int billNo,
  required DateTime billDate,
}) {
  return SaleBill(
    billNo: billNo,
    location: AppConfig.displayLocationName,
    billDate: billDate,
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

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/main_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> tearDownBillScreen(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(seconds: 2));
}

Future<void> pumpBillScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const MaterialApp(
      home: SalesBillScreen(
        initialBillNo: 1,
        calendarCheckInterval: Duration(seconds: 1),
      ),
    ),
  );

  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const Key('bill_date_display')).evaluate().isNotEmpty) {
      break;
    }
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sales_bill_date_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    SystemClock.reset();
    await AppConfig.setLocation('main');
    await SessionService.clearBillSession();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    SystemClock.reset();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  testWidgets('yesterday draft opens with today bill date', (tester) async {
    final today = DateTime(2026, 10, 17, 10, 0);
    SystemClock.now = () => today;

    await SessionService.saveBillSession(
      location: AppConfig.displayLocationName,
      billNo: 1,
      billDate: DateTime(2026, 10, 16),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(qty: 1, rate: 50)],
      billSaved: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SalesBillScreen(
          calendarCheckInterval: Duration(seconds: 1),
        ),
      ),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('bill_date_display')).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(
      find.byKey(const Key('bill_date_display')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('bill_date_display'))).data,
      _displayDate(today),
    );

    await tearDownBillScreen(tester);
  });

  testWidgets('unsaved bill date rolls forward on timer when day changes',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 23, 0);
    SystemClock.now = () => clock;

    await pumpBillScreen(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('bill_date_display'))).data,
      _displayDate(clock),
    );

    clock = DateTime(2026, 10, 18, 0, 30);
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.widget<Text>(find.byKey(const Key('bill_date_display'))).data,
      _displayDate(clock),
    );

    await tearDownBillScreen(tester);
  });

  test('previous bill keeps its saved date when loaded', () async {
    final oldDate = DateTime(2026, 1, 15);
    await LocalDb.instance.insertPendingBill(
      _savedBill(billNo: 1, billDate: oldDate),
    );

    final previous = await BillRepository.getPreviousBill(
      location: AppConfig.displayLocationName,
      beforeBillNo: 2,
    );

    expect(previous, isNotNull);
    expect(previous!.billDate.year, oldDate.year);
    expect(previous.billDate.month, oldDate.month);
    expect(previous.billDate.day, oldDate.day);
  });

  test('bill saved after midnight is stored with the new calendar date', () async {
    var clock = DateTime(2026, 10, 17, 23, 55);
    SystemClock.now = () => clock;

    clock = DateTime(2026, 10, 18, 0, 5);
    final bill = _savedBill(billNo: 1, billDate: clock);
    final result = await BillRepository.saveBill(bill);
    expect(result.ok, isTrue);

    final stored = await LocalDb.instance.getBillByNumber(
      location: AppConfig.displayLocationName,
      billNo: 1,
    );
    expect(stored, isNotNull);
    expect(stored!.bill.billDate.year, 2026);
    expect(stored.bill.billDate.month, 10);
    expect(stored.bill.billDate.day, 18);
  });
}
