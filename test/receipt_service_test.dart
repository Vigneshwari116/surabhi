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
  test('header shows Surabhi Export centered with address', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final text = lines.join('\n');

    expect(text, contains('SURABHI EXPORT'));
    expect(text, contains('OLD THARGUPET'));
    expect(text, contains('T.10, 3RD FLOOR,'));
    expect(text, contains('L N COMPLEX, LAL BUILDING,'));
    expect(text, contains('Bangalore'));
    expect(text, contains('29ACDPJ2452J1ZK'));
    expect(text, contains('BILL NO:133 UPI'));
    expect(text, contains('13/10/2026'));
    expect(text, isNot(contains('DATE:')));
    _expectLinesWithinWidth(lines);
    _expectAddressWordsNotSplit(lines);

    final title = lines.first;
    final gstinLine = lines.firstWhere((line) => line.contains('GSTIN:'));
    _expectCentered(title);
    _expectCentered(gstinLine);
  });

  test('item table has 30 columns with gaps between every column', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final header = lines.firstWhere((line) => line.contains('GROUP'));
    final itemLine = lines.firstWhere(
      (line) => line.contains('SHIRT') && line.contains('50'),
    );

    expect(header.length, _cols);
    expect(itemLine.length, _cols);
    expect(header.substring(0, 2), 'SN');
    expect(header[2], ' ');
    expect(header.substring(3, 13).trim(), 'GROUP');
    expect(header[13], ' ');
    expect(header.substring(14, 19).trim(), 'RATE');
    expect(header[19], ' ');
    expect(header.substring(20, 23).trim(), 'QTY');
    expect(header[23], ' ');
    expect(header.substring(24).trim(), 'AMOUNT');
    expect(itemLine.substring(3, 13).trim(), 'SHIRT');

    _expectLinesWithinWidth(lines);
  });

  test('group column fits GENTS WEAR in ten characters', () {
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
    expect(itemLine.substring(3, 13).trim(), 'GENTS WEAR');
    _expectLinesWithinWidth(lines);
  });

  test('total line labels quantity as TOTAL PCS with two-decimal taxable', () {
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
    expect(totalLine.trimRight(), endsWith('1257.14'));
  });

  test('receipt prints gst percents on tax rows with two decimals', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    expect(text, isNot(contains('CGST 2.5%  SGST 2.5%')));
    expect(text, contains('CGST 2.5%'));
    expect(text, contains('SGST 2.5%'));
    expect(text, contains('1.19'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, isNot(contains('EXCHANGE ONLY 3 DAYS')));
    expect(text, contains('50.00'));
    expect(text, contains('47.62'));

    final gstMatches = 'CGST 2.5%'.allMatches(text).length;
    expect(gstMatches, 1);
  });

  test('bill line omits payment mode when stored value is empty', () {
    final bill = SaleBill(
      billNo: 305,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 17),
      paymentMode: '',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: 'Shirt', qty: 1, rate: 10)],
      totalQty: 1,
      totalAmount: 9.52,
      totalCgst: 0.24,
      totalSgst: 0.24,
      totalIgst: 0,
      grandTotal: 10,
    );
    final billLine = ReceiptService.buildReceiptLines(bill)
        .firstWhere((line) => line.contains('BILL NO:'));
    expect(billLine, contains('BILL NO:305'));
    expect(billLine, isNot(contains('CASH')));
    expect(billLine, isNot(contains('UPI')));
    expect(billLine.trim().length, lessThanOrEqualTo(29));
    expect(billLine, contains('17/10/2026'));
  });

  test('bill line includes payment mode between bill no and date', () {
    final bill = SaleBill(
      billNo: 305,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 17),
      paymentMode: 'UPI',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: 'Shirt', qty: 1, rate: 10)],
      totalQty: 1,
      totalAmount: 9.52,
      totalCgst: 0.24,
      totalSgst: 0.24,
      totalIgst: 0,
      grandTotal: 10,
    );
    final billLine = ReceiptService.buildReceiptLines(bill)
        .firstWhere((line) => line.contains('BILL NO:'));
    expect(billLine.trim(), 'BILL NO:305 UPI    17/10/2026');
    expect(billLine.trim().length, lessThanOrEqualTo(29));
  });

  test('rate 30 qty 2 prints footer block with CGST/SGST below TOTAL PCS',
      () {
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 17),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'Shirt', qty: 2, rate: 30),
      ],
      totalQty: 2,
      totalAmount: 57.14,
      totalCgst: 1.43,
      totalSgst: 1.43,
      totalIgst: 0,
      grandTotal: 60,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final totalIndex = lines.indexWhere((line) => line.contains('TOTAL PCS'));
    final grandIndex = lines.indexWhere((line) => line.contains('GRAND TOTAL'));
    expect(totalIndex, greaterThan(0));
    expect(grandIndex, greaterThan(totalIndex));

    final footerBlock = lines.sublist(totalIndex, grandIndex + 1);
    final footerText = footerBlock.map((l) => l.trimRight()).toList();
    expect(footerText[0], 'TOTAL PCS         2     57.14');
    expect(footerText[1], 'CGST 2.5%                1.43');
    expect(footerText[2], 'SGST 2.5%                1.43');
    expect(footerText[3], '-' * 29);
    expect(footerText[4], 'GRAND TOTAL             60.00');

    final itemEnd = lines.indexWhere((line) => line.contains('SHIRT'));
    final between = lines.sublist(itemEnd + 1, totalIndex);
    expect(between.any((line) => line.contains('CGST')), isFalse);
    expect(between.any((line) => line.contains('SGST')), isFalse);
    _expectLinesWithinWidth(lines);
  });

  test('item with zero gst percent still prints CGST 2.5% on footer', () {
    final bill = SaleBill(
      billNo: 2,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 17),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'Shirt', qty: 1, rate: 30, cgstPct: 0, sgstPct: 0),
      ],
      totalQty: 1,
      totalAmount: 28.57,
      totalCgst: 0.71,
      totalSgst: 0.71,
      totalIgst: 0,
      grandTotal: 30,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final cgstLine = lines.firstWhere((l) => l.contains('CGST 2.5%'));
    final sgstLine = lines.firstWhere((l) => l.contains('SGST 2.5%'));
    expect(cgstLine.trimRight(), endsWith('0.71'));
    expect(sgstLine.trimRight(), endsWith('0.71'));
    expect(cgstLine.indexOf('TOTAL PCS'), lessThan(0));
  });

  test('large gst amounts print with two decimals within column width', () {
    final bill = SaleBill(
      billNo: 99,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 17),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'Coat', qty: 1, rate: 10000),
      ],
      totalQty: 1,
      totalAmount: 9523.81,
      totalCgst: 238.10,
      totalSgst: 238.10,
      totalIgst: 0,
      grandTotal: 10000,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final cgstLine = lines.firstWhere((l) => l.contains('CGST 2.5%'));
    final sgstLine = lines.firstWhere((l) => l.contains('SGST 2.5%'));

    expect(cgstLine.trimRight(), endsWith('238.10'));
    expect(sgstLine.trimRight(), endsWith('238.10'));
    _expectLinesWithinWidth(lines);
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
    final totalPcsIndex = lines.indexWhere((l) => l.contains('TOTAL PCS'));
    final section = lines.sublist(headerIndex, totalPcsIndex);
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

  test('group names are uppercase and truncated to ten characters', () {
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
    expect(text, contains('LONGNAMEIT'));
    expect(text, isNot(contains('longnameitem')));
  });

  test('computed pdf font fits content width for 30 columns', () {
    final fontSize = ReceiptLayout.bodyFontSizePt();
    expect(fontSize, closeTo(9.1, 0.6));

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
    expect(item.substring(14, 19).trim(), '99999');
    expect(item.substring(_amountStart).length, ReceiptLayout.amountWidth);
    _expectLinesWithinWidth(lines);
  });

  test('shop name and grand total emphasis fonts fit content width', () {
    final shopSize =
        ReceiptLayout.shopNameFontSizePt(ReceiptService.businessName);
    expect(
      ReceiptLayout.textWidthMm(ReceiptService.businessName, shopSize),
      lessThanOrEqualTo(ReceiptLayout.contentWidthMm),
    );
    expect(shopSize, closeTo(14.0, 1.5));

    final fonts = ReceiptLayout.grandTotalFontSizes('999999');
    final totalWidth = ReceiptLayout.textWidthMm('GRAND TOTAL', fonts.labelPt) +
        ReceiptLayout.textWidthMm('999999', fonts.amountPt);
    expect(totalWidth, lessThanOrEqualTo(ReceiptLayout.contentWidthMm));
    expect(fonts.amountPt, closeTo(13.0, 1.5));
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
    expect(item.substring(3, 13), '          ');
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

  test('footer grand totals print full amount without digit loss', () {
    const amounts = [9999.99, 10000.00, 12345.67, 1234567.89];
    for (final grand in amounts) {
      final bill = SaleBill(
        billNo: 1,
        location: 'Surabhi',
        billDate: DateTime(2026, 1, 1),
        paymentMode: 'CASH',
        customerName: '',
        mobile: '',
        items: [BillItem(particular: 'X', qty: 1, rate: grand)],
        totalQty: 1,
        totalAmount: grand,
        totalCgst: 0,
        totalSgst: 0,
        totalIgst: 0,
        grandTotal: grand,
      );
      final lines = ReceiptService.buildReceiptLines(bill);
      final grandLine = lines.firstWhere((l) => l.contains('GRAND TOTAL'));
      final expected = grand.toStringAsFixed(2);
      expect(grandLine.trimRight().endsWith(expected), isTrue);
      expect(grandLine.length, lessThanOrEqualTo(29));
    }
  });

  test('TOTAL PCS with 5-digit qty and large taxable fits 29-char footer', () {
    const taxable = 1234567.89;
    final bill = SaleBill(
      billNo: 1,
      location: 'Surabhi',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(particular: 'X', qty: 12345, rate: 100)],
      totalQty: 12345,
      totalAmount: taxable,
      totalCgst: 0,
      totalSgst: 0,
      totalIgst: 0,
      grandTotal: 1234500,
    );
    final lines = ReceiptService.buildReceiptLines(bill);
    final totalLine = lines.firstWhere((l) => l.contains('TOTAL PCS') || l.contains('PCS 12345'));
    expect(totalLine.length, lessThanOrEqualTo(29));
    expect(totalLine.trimRight().endsWith('1234567.89'), isTrue);
    expect(totalLine, contains('12345'));
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
    expect(grandLine.trimRight().endsWith('10.40'), isTrue);
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
  expect(text, contains('T.10, 3RD FLOOR,'));
  expect(text, contains('L N COMPLEX, LAL BUILDING,'));
  expect(text, contains('OLD THARGUPET, Bangalore'));
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
