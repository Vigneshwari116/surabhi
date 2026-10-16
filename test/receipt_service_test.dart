import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/receipt_service.dart';

const _cols = ReceiptService.thermalContentColumns;

SaleBill _sampleBill() {
  return SaleBill(
    billNo: 133,
    location: 'Surabhi',
    billDate: DateTime(2026, 10, 13),
    paymentMode: 'UPI',
    customerName: '',
    mobile: '',
    items: [
      BillItem(particular: 'Shirt', qty: 1, rate: 50),
    ],
    totalQty: 1,
    totalAmount: 47.62,
    totalCgst: 1.19,
    totalSgst: 1.19,
    totalIgst: 0,
    grandTotal: 50,
  );
}

void main() {
  test('header shows Surabhi Exports centered with address', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final text = lines.join('\n');

    expect(text, contains('SURABHI EXPORTS'));
    expect(text, contains('THARGUPET'));
    expect(text, contains('29ACDPJ2452J1ZK'));
    expect(text, contains('BILL NO:133'));
    expect(text, contains('13/10/2026'));
    expect(text, isNot(contains('DATE:')));
    _expectLinesWithinWidth(lines);

    final title = lines.first;
    final gstinLine = lines.firstWhere((line) => line.contains('GSTIN:'));
    _expectCentered(title);
    _expectCentered(gstinLine);
  });

  test('item table includes SNO and GROUP columns on each row', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final header = lines.firstWhere((line) => line.contains('GROUP'));
    final itemLine = lines.firstWhere(
      (line) => line.trimLeft().startsWith('1') && line.contains('50.00'),
    );

    expect(header.length, _cols);
    expect(itemLine.length, _cols);
    expect(header.substring(0, 3), 'SNO');
    expect(header.substring(3, 14).trim(), 'GROUP');
    expect(itemLine.substring(3, 14).trim(), 'Shirt');

    _expectLinesWithinWidth(lines);
  });

  test('group column fits GENTS WEAR without truncation', () {
    final bill = SaleBill(
      billNo: 239,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 16),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'GENTS WEAR', qty: 4, rate: 23),
      ],
      totalQty: 4,
      totalAmount: 88,
      totalCgst: 2,
      totalSgst: 2,
      totalIgst: 0,
      grandTotal: 92,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final itemLine = lines.firstWhere((line) => line.trimLeft().startsWith('1'));
    expect(itemLine.substring(3, 14).trim(), 'GENTS WEAR');
    _expectLinesWithinWidth(lines);
  });

  test('receipt shows per-item gst line with separated cgst and sgst', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    expect(text, contains('CGST% 2.5  SGST% 2.5'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('TOTAL PCS'));
    expect(text, isNot(contains('EXCHANGE ONLY 3 DAYS')));
  });

  test('separator lines are exactly content width', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final dashes = lines.where((line) => line == '-' * _cols).toList();
    expect(dashes, isNotEmpty);
    for (final line in dashes) {
      expect(line.length, _cols);
    }
  });
}

void _expectLinesWithinWidth(List<String> lines) {
  for (final line in lines) {
    expect(
      line.length,
      lessThanOrEqualTo(_cols),
      reason: 'Line exceeds thermal width: "$line"',
    );
  }
}

void _expectCentered(String line) {
  expect(line.length, _cols);
  final trimmed = line.trim();
  final start = line.indexOf(trimmed);
  final end = start + trimmed.length;
  final leftPad = start;
  final rightPad = line.length - end;
  expect((leftPad - rightPad).abs(), lessThanOrEqualTo(1));
}
