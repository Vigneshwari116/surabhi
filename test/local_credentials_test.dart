import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/config/local_credentials.dart';

void main() {
  test('surabhi staff login', () {
    expect(verifyStaffLogin('surabhi', 'surabhi'), isTrue);
    expect(verifyStaffLogin('SURABHI', 'surabhi'), isTrue);
    expect(verifyStaffLogin('surabhi', 'wrong'), isFalse);
    expect(staffLocationCodeForUsername('surabhi'), 'main');
  });

  test('admin login', () {
    expect(verifyAdminLogin('admin', 'admin123'), isTrue);
    expect(verifyAdminLogin('admin', 'wrong'), isFalse);
  });
}
