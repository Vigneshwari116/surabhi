import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/receipt_service.dart';

const _cols = ReceiptService.thermalContentColumns;
const _amountStart = 3 + 8 + 6 + 4;

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
    expect(header.substring(3, 11).trim(), 'GROUP');
    expect(itemLine.substring(3, 11).trim(), 'Shirt');

    _expectLinesWithinWidth(lines);
  });

  test('receipt shows per-item gst line with separated cgst and sgst', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    expect(text, contains('CGST% 2.5  SGST% 2.5'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('EXCHANGE ONLY 3 DAYS'));
  });

  test('separator lines are exactly content width', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final dashes = lines.where((line) => line == '-' * _cols).toList();
    expect(dashes, isNotEmpty);
    for (final line in dashes) {
      expect(line.length, _cols);
    }
  });

  test('amount column is right-aligned for large values', () {
    final bill = SaleBill(
      billNo: 99,
      location: 'Surabhi',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'Coat', qty: 1, rate: 99999),
      ],
      totalQty: 1,
      totalAmount: 99999,
      totalCgst: 0,
      totalSgst: 0,
      totalIgst: 0,
      grandTotal: 99999,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final item = lines.firstWhere((line) => line.contains('99999.00'));
    expect(item.substring(_amountStart).trim(), '99999.00');
    _expectLinesWithinWidth(lines);
  });

  test('empty group prints blank spaces keeping columns aligned', () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: '', qty: 2, rate: 100)],
      totalQty: 2,
      totalAmount: 200,
      totalCgst: 5,
      totalSgst: 5,
      totalIgst: 0,
      grandTotal: 200,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final item = lines.firstWhere((line) => line.trimLeft().startsWith('1'));
    expect(item.substring(3, 11), '        ');
    _expectLinesWithinWidth(lines);
  });

  test('bill no and full date stay on one line', () {
    final bill = SaleBill(
      billNo: 18134,
      location: 'Surabhi',
      billDate: DateTime(2024, 6, 10),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: 'Pant', qty: 2, rate: 200)],
      totalQty: 2,
      totalAmount: 400,
      totalCgst: 10,
      totalSgst: 10,
      totalIgst: 0,
      grandTotal: 400,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final billDateLine = lines.firstWhere((line) => line.contains('BILL NO:'));

    expect(billDateLine, contains('10/06/2024'));
    expect(billDateLine, contains('BILL NO:18134'));
    expect(billDateLine.length, lessThanOrEqualTo(_cols));
    expect(billDateLine.trim().length, lessThanOrEqualTo(30));
  });
}

void _expectLinesWithinWidth(List<String> lines) {
  for (final line in lines) {
    expect(
      line.length,
      lessThanOrEqualTo(_cols),
      reason: 'Line exceeds $_cols columns: "$line"',
    );
  }
}

void _expectCentered(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final start = line.indexOf(trimmed);
  final end = start + trimmed.length;
  final leftPad = start;
  final rightPad = line.length - end;
  expect(
    (leftPad - rightPad).abs(),
    lessThanOrEqualTo(1),
    reason: 'Expected centered line: "$line"',
  );
}
