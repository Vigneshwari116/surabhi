import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/services/receipt_service.dart';

SaleBill _sampleBill() {
  return SaleBill(
    billNo: 16133,
    location: 'Surabhi',
    billDate: DateTime(2026, 9, 5),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [BillItem(particular: 'Shirt', qty: 1, rate: 1000)],
    totalQty: 1,
    totalAmount: 952.38,
    totalCgst: 24,
    totalSgst: 24,
    totalIgst: 0,
    grandTotal: 1000,
  );
}

Printer _printer({
  required String name,
  String url = '',
  bool isDefault = false,
  bool isAvailable = true,
}) {
  return Printer(
    name: name,
    url: url,
    isDefault: isDefault,
    isAvailable: isAvailable,
  );
}

void main() {
  test('name and mobile lines are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final nameIndex = lines.indexWhere((line) => line.startsWith('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.startsWith('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);
    expect(lines[mobileIndex + 1], startsWith('----'));
  });

  test('receipt footer lines are present after grand total', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill());
    final text = lines.join('\n');

    expect(text, contains('TERMS AND CONDITION'));
    expect(text, contains('AMOUNT NOT REFUND'));
    expect(text, contains('THANK YOU VISIT AGAIN'));
    expect(text, isNot(contains('EXCHANGE ONLY 3 DAYS')));

    final grandTotalIndex = text.lastIndexOf('GRAND TOTAL');
    final footerIndex = text.indexOf('TERMS AND CONDITION');
    expect(footerIndex, greaterThan(grandTotalIndex));
  });

  test('thermal pdf uses 66mm page width and dynamic height', () async {
    final bill = _sampleBill();
    final receiptLines = ReceiptService.buildReceiptLines(bill);
    final bytes = await BillPrintService.buildPdfBytes(bill);
    final pageFormat = BillPrintService.pageFormatForBill(bill);
    final pdfText = String.fromCharCodes(bytes);

    expect(bytes, isNotEmpty);
    expect(pdfText, contains('/MediaBox'));
    final mediaBoxMatch =
        RegExp(r'/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(pdfText);
    expect(mediaBoxMatch, isNotNull);
    final pageWidthPt = double.parse(mediaBoxMatch!.group(1)!);
    final pageHeightPt = double.parse(mediaBoxMatch.group(2)!);

    final expectedWidthPt =
        BillPrintService.thermalPdfPageWidthMm * PdfPageFormat.mm;
    expect(pageWidthPt, closeTo(pageFormat.width, 1.0));
    expect(pageWidthPt, closeTo(expectedWidthPt, 1.5));

    var expectedHeightMm = BillPrintService.thermalPdfMarginTopMm +
        BillPrintService.thermalPdfMarginBottomMm;
    for (final line in receiptLines) {
      final trimmed = line.trim();
      if (trimmed == ReceiptService.businessName) {
        expectedHeightMm += BillPrintService.thermalHeaderLineSpacingMm;
      } else if (trimmed.startsWith('GRAND TOTAL')) {
        expectedHeightMm += BillPrintService.thermalGrandTotalLineSpacingMm;
      } else {
        expectedHeightMm += BillPrintService.thermalLineSpacingMm;
      }
    }
    final actualHeightMm = pageHeightPt / PdfPageFormat.mm;
    expect(actualHeightMm, closeTo(expectedHeightMm, 1.0));
  });

  group('resolveTargetPrinter', () {
    test('exact name match', () {
      final printers = [
        _printer(name: 'Kitchen'),
        _printer(name: 'RP3200', url: 'winspool'),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: 'RP3200',
      );

      expect(resolved?.name, 'RP3200');
    });

    test('fuzzy name match when exact name missing', () {
      final printers = [
        _printer(name: 'TVS RP3200 Series'),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: 'rp3200',
      );

      expect(resolved?.name, 'TVS RP3200 Series');
    });
  });
}
