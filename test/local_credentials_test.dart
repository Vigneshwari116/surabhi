import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/config/local_credentials.dart';

void main() {
  test('staff login accepts surabhi credentials', () {
    expect(verifyStaffLogin('surabhi', 'surabhi'), isTrue);
    expect(verifyStaffLogin('surabhi', 'wrong'), isFalse);
    expect(staffLocationCodeForUsername('surabhi'), 'main');
  });
}
