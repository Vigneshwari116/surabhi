import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/screen/sales_bill_screen.dart';
import 'package:surabhi/services/session_service.dart';
import 'package:surabhi/services/sync_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'main';

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/main_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sales_bill_overflow_');
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
    await AppConfig.setLocation(_testLocationCode);
    await SessionService.clearBillSession();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
    await LocalDb.instance.initialize();
    await LocalDb.instance.getNextBillNumber(AppConfig.displayLocationName);
    SyncService.instance.start(location: AppConfig.displayLocationName);
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  List<BillItem> billItems(int count) {
    return List.generate(
      count,
      (index) => BillItem(
        particular: 'ITEM ${index + 1}',
        qty: 1,
        rate: 10.0 + index,
      ),
    );
  }

  double maxVerticalListScrollExtent(WidgetTester tester) {
    var maxExtent = 0.0;
    final listViews = tester.widgetList<ListView>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.vertical,
      ),
    );
    for (final listView in listViews) {
      final controller = listView.controller;
      if (controller != null && controller.hasClients) {
        maxExtent = math.max(maxExtent, controller.position.maxScrollExtent);
      }
    }
    return maxExtent;
  }

  Future<void> pumpSalesBillDesktop(
    WidgetTester tester, {
    required List<BillItem> items,
    bool sidebarOpen = false,
  }) async {
    await SessionService.saveBillSession(
      location: AppConfig.displayLocationName,
      billNo: 1,
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'UPI',
      customerName: 'TEST CUSTOMER',
      mobile: '9876543210',
      items: items,
      billSaved: false,
    );

    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SalesBillScreen(),
      ),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty &&
          find.text('GRAND TOTAL').evaluate().isNotEmpty &&
          find.byIcon(Icons.close).evaluate().length >= items.length) {
        break;
      }
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    if (sidebarOpen) {
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.menu_open), findsWidgets);
    }
  }

  testWidgets('sales bill desktop layout has no overflow at 1366x768 with 3 items',
      (tester) async {
    final items = [
      BillItem(particular: 'RICE', qty: 2, rate: 100),
      BillItem(particular: 'WHEAT FLOUR', qty: 1, rate: 250),
      BillItem(particular: 'SUGAR', qty: 3, rate: 45.5),
    ];

    await pumpSalesBillDesktop(tester, items: items);

    expect(find.text('BILL NO:'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await SyncService.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill desktop layout has no overflow with Today Sales panel visible',
      (tester) async {
    final items = [
      BillItem(particular: 'RICE', qty: 2, rate: 100),
      BillItem(particular: 'WHEAT FLOUR', qty: 1, rate: 250),
      BillItem(particular: 'SUGAR', qty: 3, rate: 45.5),
    ];

    await pumpSalesBillDesktop(tester, items: items);

    await tester.tap(find.byKey(const Key('today_sales_button')));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('today_sales_panel')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('today_sales_panel')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await SyncService.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill shows 10 grid rows without vertical scroll at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(tester, items: billItems(10));

    for (var serial = 1; serial <= 10; serial++) {
      expect(find.text('$serial'), findsWidgets);
    }
    expect(maxVerticalListScrollExtent(tester), 0);
    expect(tester.takeException(), isNull);

    await SyncService.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill shows 10 grid rows with sidebar open at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: billItems(10),
      sidebarOpen: true,
    );

    for (var serial = 1; serial <= 10; serial++) {
      expect(find.text('$serial'), findsWidgets);
    }
    expect(maxVerticalListScrollExtent(tester), 0);
    expect(tester.takeException(), isNull);

    await SyncService.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill grid scrolls internally with more than 10 items at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(tester, items: billItems(11));

    expect(maxVerticalListScrollExtent(tester), greaterThan(0));
    expect(find.text('11'), findsNothing);

    final verticalList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalList.first, const Offset(0, -80));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('11'), findsWidgets);
    expect(tester.takeException(), isNull);

    await SyncService.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });
}
