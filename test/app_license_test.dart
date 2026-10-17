import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/config/app_license.dart';

void main() {
  test('app license is valid for 60 days from 15-Oct-2026', () {
    expect(AppLicense.validFrom, DateTime(2026, 10, 15));
    expect(AppLicense.validityDays, 60);
    expect(AppLicense.validUntil, DateTime(2026, 12, 14));
    expect(AppLicense.isValid, isTrue);
  });
}
