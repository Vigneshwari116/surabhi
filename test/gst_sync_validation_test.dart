import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/api/sales_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.setLocation('main');
  });

  tearDown(() async {
    await AppConfig.clearLocation();
  });

  test('main session uses main_gst database name', () {
    expect(AppConfig.locationCode, 'main');
    expect(AppConfig.expectedGstDbName, 'main_gst');
  });

  test('rejects GST sync when server returns another location db_name', () {
    expect(SalesApi.isGstDbNameValid('win2_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('main_gst'), isTrue);
  });
}
