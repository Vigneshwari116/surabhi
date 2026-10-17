import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/services/location_reset_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocationResetService.clearPendingForTesting();
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

  test('hasPendingServerReset tracks queued location codes', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_server_reset_locations', ['main']);

    expect(await LocationResetService.hasPendingServerReset('main'), isTrue);
    expect(await LocationResetService.hasPendingServerReset('win1'), isFalse);
  });

  test('ensureServerResetBeforeSync blocks while offline reset is queued',
      () async {
    SharedPreferences.setMockInitialValues({
      'pending_server_reset_locations': ['main'],
    });
    LocationResetService.isDeviceOnlineOverride = () async => false;

    final message = await LocationResetService.ensureServerResetBeforeSync(
      'Surabhi',
    );

    expect(message, LocationResetService.pendingResetOfflineMessage);
  });
}
