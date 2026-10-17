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
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/services/location_bill_detail_seed_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('bill_detail_seed_test_');
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
    await LocalDb.resetForTesting();
    final file = File(join(tempDir.path, SalesDatabase.salesDbFileName));
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('bill detail seed is a no-op without bundled CSV import', () async {
    await AppConfig.setLocation('main');
    await LocalDb.instance.initialize();
    await LocationSeedService.ensureLocationSeeded('main');
    await LocationBillDetailSeedService.ensureLocationSeeded('main');

    final ledger = await LocalDb.instance.getLedgerEntries(
      displayNameForLocationCode('main'),
      from: '2026-01-17',
      to: '2026-01-17',
    );

    expect(ledger, isEmpty);
  });
}
