import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/repositories/bill_repository.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bill_tab_order_test_');
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
    await AppConfig.setLocation('main');
    await SessionService.clearBillSession();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await LocalDb.instance.initialize();
    SyncService.instance.start(location: AppConfig.displayLocationName);
    BillRepository.saveBillApiOverride =
        (_) async => SalesApiResult.success(1);
  });

  tearDown(() async {
    BillRepository.saveBillApiOverride = null;
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  Future<void> pumpBill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SalesBillScreen(initialBillNo: 1)),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Tab moves payment to group to rate to qty', (tester) async {
    await pumpBill(tester);

    await tester.tap(find.byKey(const Key('bill_payment_dropdown')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusScope.of(
        tester.element(find.byKey(const Key('bill_group_dropdown'))),
      ).focusedChild,
      isNotNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('bill_rate_field')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('bill_qty_field')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('Shift+Tab moves qty back to rate', (tester) async {
    await pumpBill(tester);

    await tester.tap(find.byKey(const Key('bill_qty_field')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('bill_rate_field')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });
}
