import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/sales_database.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/services/location_seed_service.dart';

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
    tempDir = await Directory.systemTemp.createTemp('location_seed_test_');
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

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.clearLocation();
    final file = File(join(tempDir.path, SalesDatabase.salesDbFileName));
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('marks seed complete without importing legacy win CSV data', () async {
    await LocationSeedService.ensureLocationSeeded('main');
    await LocationSeedService.ensureLocationSeeded('main');

    final ledger = await LedgerRepository.getLedger(
      location: displayNameForLocationCode('main'),
      from: '2026-01-01',
      to: '2026-01-02',
    );

    expect(ledger.entries, isEmpty);
    expect(ledger.summary.grandTotal, 0);
  });

  test('abstract summary stays empty when no bills exist', () async {
    await LocationSeedService.ensureLocationSeeded('main');

    final summary = await AbstractRepository.getSummaryForLocationCode(
      locationCode: 'main',
      fromDate: DateTime(2026, 1, 1),
      toDate: DateTime(2026, 1, 1),
    );

    expect(summary.totalSaleAmount, 0);
    expect(summary.totalGst, 0);
  });
}
