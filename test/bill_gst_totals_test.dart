import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/utils/bill_gst_totals.dart';

void main() {
  void expectPartsSumToGrand(BillGstTotals totals) {
    final sum = roundGstMoney(
      totals.totalAmount +
          totals.totalCgst +
          totals.totalSgst +
          totals.totalIgst,
    );
    expect(sum, roundGstMoney(totals.grandTotal));
  }

  test('30 x 2 → 57.14 / 1.43 / 1.43 / 60.00', () {
    final totals = computeBillGstTotalsFromItems([
      BillItem(qty: 2, rate: 30),
    ]);
    expect(totals.totalAmount, 57.14);
    expect(totals.totalCgst, 1.43);
    expect(totals.totalSgst, 1.43);
    expect(totals.grandTotal, 60);
    expectPartsSumToGrand(totals);
  });

  test('100 grand → 95.24 / 2.38 / 2.38 / 100.00', () {
    final totals = computeBillGstTotalsFromItems([
      BillItem(qty: 1, rate: 100),
    ]);
    expect(totals.totalAmount, 95.24);
    expect(totals.totalCgst, 2.38);
    expect(totals.totalSgst, 2.38);
    expect(totals.grandTotal, 100);
    expectPartsSumToGrand(totals);
  });

  test('7067 grand → 6730.48 / 168.26 / 168.26 / 7067.00', () {
    final totals = computeBillGstTotalsFromItems([
      BillItem(qty: 1, rate: 7067),
    ]);
    expect(totals.totalAmount, 6730.48);
    expect(totals.totalCgst, 168.26);
    expect(totals.totalSgst, 168.26);
    expect(totals.grandTotal, 7067);
    expectPartsSumToGrand(totals);
  });
}
