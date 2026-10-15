import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/receipt_layout.dart';
import 'package:surabhi/services/receipt_service.dart';

const _cols = ReceiptService.thermalContentColumns;
const _gap = ReceiptLayout.columnGap;
const _amountStart = ReceiptLayout.snoWidth +
    _gap +
    ReceiptLayout.groupWidth +
    _gap +
    ReceiptLayout.rateWidth +
    _gap +
    ReceiptLayout.qtyWidth +
    _gap;

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
    expect(text, contains('T.10, 3RD FLOOR'));
    expect(text, contains('29ACDPJ2452J1ZK'));
    expect(text, contains('BILL NO:133'));
    expect(text, contains('13/10/2026'));
    expect(text, isNot(contains('DATE:')));
    _expectLinesWithinWidth(lines);
    _expectAddressWordsNotSplit(lines);

    final title = lines.first;
    final gstinLine = lines.firstWhere((line) => line.contains('GSTIN:'));
    _expectCentered(title);
    _expectCentered(gstinLine);
  });

  test('item table has 29 columns with gaps between every column', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final header = lines.firstWhere((line) => line.contains('GROUP'));
    final itemLine = lines.firstWhere(
      (line) => line.contains('SHIRT') && line.contains('50'),
    );

    expect(header.length, _cols);
    expect(itemLine.length, _cols);
    expect(header.substring(0, 2), 'SN');
    expect(header[2], ' ');
    expect(header.substring(3, 11).trim(), 'GROUP');
    expect(header[11], ' ');
    expect(header.substring(12, 17).trim(), 'RATE');
    expect(header[17], ' ');
    expect(header.substring(18, 21).trim(), 'QTY');
    expect(header[21], ' ');
    expect(header.substring(22).trim(), 'AMOUNT');
    expect(itemLine.substring(3, 11).trim(), 'SHIRT');

    _expectLinesWithinWidth(lines);
  });

  test('total line labels quantity as TOTAL PCS with whole numbers', () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'Shirt', qty: 132, rate: 10),
      ],
      totalQty: 132,
      totalAmount: 1257.14,
      totalCgst: 31.43,
      totalSgst: 31.43,
      totalIgst: 0,
      grandTotal: 1320,
    );
    final lines = ReceiptService.buildReceiptLines(bill);
    final totalLine = lines.firstWhere((line) => line.contains('TOTAL PCS'));
    expect(totalLine, contains('132'));
    expect(totalLine, contains('1257'));
    expect(totalLine, isNot(contains('.')));
  });

  test('receipt prints gst line once without decimals on money columns', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    expect(text, contains('CGST% 2.5  SGST% 2.5'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('EXCHANGE ONLY 3 DAYS'));
    expect(text, contains('50'));
    expect(text, contains('48'));
    expect(text, isNot(contains('50.00')));
    expect(text, isNot(contains('47.62')));

    final gstMatches = 'CGST% 2.5'.allMatches(text).length;
    expect(gstMatches, 1);
  });

  test('item section has one separator after header and one after last item', () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'A', qty: 1, rate: 10),
        BillItem(particular: 'B', qty: 1, rate: 20),
      ],
      totalQty: 2,
      totalAmount: 30,
      totalCgst: 1,
      totalSgst: 1,
      totalIgst: 0,
      grandTotal: 32,
    );
    final lines = ReceiptService.buildReceiptLines(bill);
    final headerIndex = lines.indexWhere((l) => l.contains('GROUP'));
    final gstIndex = lines.indexWhere((l) => l.contains('CGST%'));
    final section = lines.sublist(headerIndex, gstIndex);
    final dashLines =
        section.where((line) => line == '-' * _cols).toList(growable: false);
    expect(dashLines.length, 2);
    expect(section.where((l) => l.trimLeft().startsWith('1 ')).length, 1);
    expect(section.where((l) => l.trimLeft().startsWith('2 ')).length, 1);
  });

  test('separator lines are exactly content width', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final dashes = lines.where((line) => line == '-' * _cols).toList();
    expect(dashes, isNotEmpty);
    for (final line in dashes) {
      expect(line.length, _cols);
    }
  });

  test('group names are uppercase and truncated to eight characters', () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'longnameitem', qty: 1, rate: 10),
      ],
      totalQty: 1,
      totalAmount: 9.52,
      totalCgst: 0.24,
      totalSgst: 0.24,
      totalIgst: 0,
      grandTotal: 10,
    );

    final text = ReceiptService.buildReceiptText(bill);
    expect(text, contains('LONGNAME'));
    expect(text, isNot(contains('longnameitem')));
  });

  test('computed pdf font fits content width for 29 columns', () {
    final fontSize = ReceiptLayout.bodyFontSizePt();
    expect(fontSize, closeTo(9.0, 0.6));

    final charWidthMm =
        fontSize * ReceiptLayout.courierBoldCharWidthFactor * (25.4 / 72);
    final totalMm = charWidthMm * ReceiptLayout.columnCount;
    expect(totalMm, lessThanOrEqualTo(ReceiptLayout.contentWidthMm));
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
    final item = lines.firstWhere((line) => line.trimLeft().startsWith('1'));
    expect(item.substring(12, 17).trim(), '99999');
    expect(item.substring(_amountStart).length, ReceiptLayout.amountWidth);
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

  test('bill no and full date stay on one line within column width', () {
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
    expect(billDateLine.trim().length, lessThanOrEqualTo(_cols));
  });

  test('grand total uses stored value rounded for print only', () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: 'X', qty: 1, rate: 10.4)],
      totalQty: 1,
      totalAmount: 9.9,
      totalCgst: 0.25,
      totalSgst: 0.25,
      totalIgst: 0,
      grandTotal: 10.4,
    );
    final lines = ReceiptService.buildReceiptLines(bill);
    final grandLine = lines.firstWhere((l) => l.contains('GRAND TOTAL'));
    expect(grandLine.trimRight().endsWith('10'), isTrue);
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

void _expectAddressWordsNotSplit(List<String> lines) {
  final text = lines.join('\n');
  expect(text, contains('T.10, 3RD FLOOR'));
  expect(text, contains('OLD THARGUPET'));
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.contains('3RD') && trimmed.contains('FLOOR')) {
      expect(trimmed, isNot(contains('3RDF')));
      expect(trimmed, isNot(startsWith('FLOOR')));
    }
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
