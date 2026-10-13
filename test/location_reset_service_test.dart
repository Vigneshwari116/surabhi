import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/services/location_reset_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocationResetService.clearPendingForTesting();
  });

  test('win4 is not an active location code', () {
    expect(isActiveLocationCode('win4'), isFalse);
    expect(allLocationCodes, ['main', 'main', 'main']);
  });

  test('branch labels map to the three active locations', () {
    expect(branchLabelForLocationCode('main'), 'Bommasandra');
    expect(branchLabelForLocationCode('main'), 'Tippasandra');
    expect(branchLabelForLocationCode('main'), 'Grabhivapalya');
  });

  test('hasPendingServerReset tracks queued location codes', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_server_reset_locations', ['main']);

    expect(await LocationResetService.hasPendingServerReset('main'), isTrue);
    expect(await LocationResetService.hasPendingServerReset('main'), isFalse);
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
