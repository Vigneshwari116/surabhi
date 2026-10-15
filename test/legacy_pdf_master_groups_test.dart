import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/services/legacy_pdf_master_groups_service.dart';

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

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('legacy_pdf_groups_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppConfig.setLocation('main');
    await LocalDb.resetForTesting();
    await LocalDb.instance.initialize();
    await LocalDb.instance.insertMasterItem('Shirt');
    await LocalDb.instance.insertMasterItem('PANT');
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('ensure adds T/JEANS once and leaves other groups unchanged', () async {
    await LegacyPdfMasterGroupsService.ensureOnStaffLogin();
    var names = await LocalDb.instance.listMasterItemNames();

    expect(names.where((n) => n.toUpperCase() == 'SHIRT').length, 1);
    expect(names.where((n) => n.toUpperCase() == 'T/JEANS').length, 1);
    expect(names.where((n) => n.toUpperCase() == 'PANT').length, 1);
    expect(names.length, 3);
    expect(names, ['PANT', 'Shirt', 'T/JEANS']);

    await LegacyPdfMasterGroupsService.ensureOnStaffLogin();
    names = await LocalDb.instance.listMasterItemNames();
    expect(names.length, 3);
    expect(names, ['PANT', 'Shirt', 'T/JEANS']);
  });
}
