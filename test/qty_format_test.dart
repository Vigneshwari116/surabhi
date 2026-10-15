import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/utils/qty_format.dart';

void main() {
  test('formatPcs shows whole numbers without decimal suffix', () {
    expect(formatPcs(132), '132');
    expect(formatPcs(132.0), '132');
  });

  test('formatPcs keeps fractional quantities to two decimals', () {
    expect(formatPcs(1.5), '1.5');
    expect(formatPcs(2.25), '2.25');
  });
}
