import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/services/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved bill pdf uses 66mm thermal roll from receipt lines', () async {
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

    final result = await BillPrintService.buildPdfBytes(bill);
    final pageFormat = BillPrintService.pageFormatForBill(bill);

    expect(result, isNotEmpty);
    expect(
      pageFormat.width,
      closeTo(BillPrintService.thermalPdfPageWidthMm * PdfPageFormat.mm, 1.0),
    );
    final pdfText = String.fromCharCodes(result);
    expect(pdfText, contains('SURABHI EXPORTS'));
    expect(pdfText, contains('THANK YOU VISIT AGAIN'));

    final receiptText = ReceiptService.buildReceiptText(bill);
    expect(receiptText, contains('SNO'));
    expect(receiptText, contains('GROUP'));
  });
}
