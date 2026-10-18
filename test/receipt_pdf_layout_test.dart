import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/services/receipt_layout.dart';
import 'package:surabhi/services/receipt_service.dart';

String _receiptMoney(double value) => NumberFormat('0.00').format(value);

/// Extracts drawn text literals from PDF bytes (raw + FlateDecode streams).
List<String> pdfLiteralStrings(Uint8List bytes) {
  final found = <String>[];
  final raw = String.fromCharCodes(bytes);
  _collectPdfLiterals(raw, found);

  _inflatePdfStreams(bytes, found);
  return found;
}

void _inflatePdfStreams(Uint8List pdf, List<String> out) {
  const stream = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6d]; // stream
  const endStream = [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];
  var index = 0;
  while (index < pdf.length) {
    final start = _indexOfBytes(pdf, stream, index);
    if (start < 0) {
      return;
    }
    var dataStart = start + stream.length;
    while (dataStart < pdf.length &&
        (pdf[dataStart] == 0x0d || pdf[dataStart] == 0x0a)) {
      dataStart++;
    }
    final end = _indexOfBytes(pdf, endStream, dataStart);
    if (end < 0) {
      return;
    }
    var dataEnd = end;
    while (dataEnd > dataStart &&
        (pdf[dataEnd - 1] == 0x0d || pdf[dataEnd - 1] == 0x0a)) {
      dataEnd--;
    }
    if (dataEnd > dataStart) {
      try {
        final inflated = zlib.decode(pdf.sublist(dataStart, dataEnd));
        _collectPdfLiterals(String.fromCharCodes(inflated), out);
      } catch (_) {
        // Ignore non-zlib streams (images, etc.).
      }
    }
    index = end + endStream.length;
  }
}

int _indexOfBytes(Uint8List haystack, List<int> needle, int start) {
  if (needle.isEmpty || start >= haystack.length) {
    return -1;
  }
  final limit = haystack.length - needle.length;
  for (var i = start; i <= limit; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

void _collectPdfLiterals(String haystack, List<String> out) {
  final matches = RegExp(r'\((?:\\.|[^\\)])*\)').allMatches(haystack);
  for (final m in matches) {
    out.add(_decodePdfString(m.group(0)!));
  }
}

String _decodePdfString(String wrapped) {
  var inner = wrapped.substring(1, wrapped.length - 1);
  return inner
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\\', r'\');
}

SaleBill _billWithGrandTotal(double grandTotal, {double taxable = 0}) {
  return SaleBill(
    billNo: 354,
    location: 'Surabhi',
    billDate: DateTime(2026, 1, 28),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [
      BillItem(particular: 'Item', qty: 1, rate: grandTotal),
    ],
    totalQty: 13,
    totalAmount: taxable > 0 ? taxable : grandTotal * 0.95,
    totalCgst: 66.67,
    totalSgst: 66.67,
    totalIgst: 0,
    grandTotal: grandTotal,
  );
}

SaleBill _bill354() {
  return SaleBill(
    billNo: 354,
    location: 'Surabhi',
    billDate: DateTime(2026, 1, 28),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [
      BillItem(particular: 'A', qty: 2, rate: 200),
      BillItem(particular: 'B', qty: 2, rate: 250),
      BillItem(particular: 'C', qty: 5, rate: 300),
      BillItem(particular: 'D', qty: 1, rate: 250),
      BillItem(particular: 'E', qty: 3, rate: 50),
    ],
    totalQty: 13,
    totalAmount: 2666.66,
    totalCgst: 66.67,
    totalSgst: 66.67,
    totalIgst: 0,
    grandTotal: 2800,
  );
}

void main() {
  const footerAmounts = <double>[
    800,
    2800,
    9999.99,
    10000,
    12345.67,
    1234567.89,
  ];

  group('footer receipt text amounts are not truncated', () {
    for (final amount in footerAmounts) {
      test('grand total ${amount.toStringAsFixed(2)} on text line', () {
        final bill = _billWithGrandTotal(amount);
        final lines = ReceiptService.buildReceiptLines(bill);
        final grandLine =
            lines.firstWhere((l) => l.trimLeft().startsWith('GRAND TOTAL'));
        final parsed = ReceiptService.footerAmountAfterLabel(
          grandLine,
          'GRAND TOTAL',
        );
        expect(parsed, _receiptMoney(amount));
        if (_receiptMoney(amount).length > ReceiptLayout.amountWidth) {
          expect(parsed!.length, greaterThan(ReceiptLayout.amountWidth));
        }
        expect(grandLine.length, lessThanOrEqualTo(ReceiptLayout.columnCount));
      });
    }
  });

  group('PDF grand total rendered width and text', () {
    for (final amount in footerAmounts) {
      test('grand total ${amount.toStringAsFixed(2)} fits printable width', () async {
        final bill = _billWithGrandTotal(amount);
        final layout = BillPrintService.grandTotalPdfLayoutForBill(bill);
        final widthMm = BillPrintService.grandTotalPdfLineWidthMm(
          layout.amountText,
          layout.labelPt,
          layout.amountPt,
        );
        expect(
          widthMm,
          lessThanOrEqualTo(ReceiptLayout.contentWidthMm + 0.01),
        );

        final bytes = await BillPrintService.buildPdfBytes(bill);
        final literals = pdfLiteralStrings(bytes);
        expect(literals, contains(layout.amountText));
        if (layout.amountText.length > 6) {
          final truncated = layout.amountText.substring(layout.amountText.length - 6);
          expect(literals, isNot(contains(truncated)));
        }
      });
    }
  });

  test('bill 354 footer lines show full taxable and grand total amounts', () async {
    final bill = _bill354();
    final lines = ReceiptService.buildReceiptLines(bill);

    final totalPcs = lines.firstWhere((l) => l.contains('TOTAL PCS'));
    final cgst = lines.firstWhere(
      (l) => l.trimLeft().startsWith('CGST'),
    );
    final sgst = lines.firstWhere(
      (l) => l.trimLeft().startsWith('SGST'),
    );
    final grand = lines.firstWhere((l) => l.trimLeft().startsWith('GRAND TOTAL'));

    expect(totalPcs.trimRight(), endsWith('2666.66'));
    expect(ReceiptService.footerAmountAfterLabel(cgst, 'CGST 2.5%'), '66.67');
    expect(ReceiptService.footerAmountAfterLabel(sgst, 'SGST 2.5%'), '66.67');
    expect(
      ReceiptService.footerAmountAfterLabel(grand, 'GRAND TOTAL'),
      '2800.00',
    );

    final bodyPt = ReceiptLayout.bodyFontSizePt();
    for (final footer in [totalPcs, cgst, sgst]) {
      expect(
        ReceiptLayout.textWidthMm(footer.trimRight(), bodyPt),
        lessThanOrEqualTo(ReceiptLayout.contentWidthMm),
      );
    }

    final bytes = await BillPrintService.buildPdfBytes(bill);
    final literals = pdfLiteralStrings(bytes);
    expect(literals, contains('2800.00'));
    expect(literals, isNot(contains('800.00')));

    // Printed footer lines for the 2800.00 case (user-visible receipt text).
    // ignore: avoid_print
    print('--- Bill 354 footer lines ---');
    for (final line in [totalPcs, cgst, sgst, grand]) {
      // ignore: avoid_print
      print(line.trimRight());
    }
  });
}
