import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
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

void main() {
  test('name and mobile lines are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill()).split('\n');
    final nameIndex = lines.indexWhere((line) => line.startsWith('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.startsWith('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);
    expect(lines[mobileIndex + 1], startsWith('----'));
  });

  test('receipt footer lines are present after grand total', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());

    expect(text, contains('TERMS AND CONDITION'));
    expect(text, contains('AMOUNT NOT REFUND'));
    expect(text, contains('THANK YOU VISIT AGAIN'));

    final grandTotalIndex = text.lastIndexOf('GRAND TOTAL');
    final footerIndex = text.indexOf('TERMS AND CONDITION');
    expect(footerIndex, greaterThan(grandTotalIndex));
  });

  test('bill pdf matches bar-and-rest 78mm thermal layout', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == 'assets/fonts/consolas.ttf') {
        return Uint8List.fromList([0, 1, 2, 3]);
      }
      return null;
    });

    final bill = _sampleBill();
    final bytes = await BillPrintService.buildDesktopPdfBytes(bill);
    final pdfText = String.fromCharCodes(bytes);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(500));
    expect(pdfText, contains('/MediaBox'));
    expect(pdfText, contains('SURABHI EXPORTS'));
    expect(pdfText, contains('GRAND TOTAL'));

    final pageFormat = BillPrintService.pageFormatForBill(bill);
    expect(pageFormat.width, closeTo(78 * PdfPageFormat.mm, 1.0));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
}
