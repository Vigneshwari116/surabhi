import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/services/receipt_service.dart';

void main() {
  test('thermal bill pdf is built from receipt lines at 66mm', () async {
    final bill = SaleBill(
      billNo: 2,
      location: 'Surabhi',
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'CARD',
      customerName: '',
      mobile: '',
      items: [
        BillItem(particular: 'shirt', qty: 45, rate: 34),
      ],
      totalQty: 45,
      totalAmount: 1530,
      totalCgst: 36.5,
      totalSgst: 36.5,
      totalIgst: 0,
      grandTotal: 1530,
    );

    final bytes = await BillPrintService.buildThermalPdfBytes(bill);
    final pageFormat = BillPrintService.pageFormatForBill(bill);
    final lines = ReceiptService.buildReceiptLines(bill);

    expect(bytes, isNotEmpty);
    expect(
      pageFormat.width,
      closeTo(BillPrintService.thermalPdfPageWidthMm * PdfPageFormat.mm, 1.0),
    );
    expect(lines.any((line) => line.contains('shirt')), isTrue);
    expect(lines.any((line) => line.trimLeft().startsWith('1')), isTrue);
    final pdfText = String.fromCharCodes(bytes);
    expect(pdfText, contains('/MediaBox'));
  });
}
