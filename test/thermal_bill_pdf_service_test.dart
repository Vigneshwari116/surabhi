import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/thermal_bill_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == 'assets/fonts/consolas.ttf') {
        return Uint8List.fromList([0, 1, 2, 3]);
      }
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('thermal pdf uses 78mm roll width like bar-and-rest-correct-', () async {
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

    final result = await ThermalBillPdfService.buildPdfWithFormat(bill);

    expect(result.bytes, isNotEmpty);
    expect(
      result.format.width,
      closeTo(78 * PdfPageFormat.mm, 1.0),
    );
    final pdfText = String.fromCharCodes(result.bytes);
    expect(pdfText, contains('SURABHI EXPORTS'));
    expect(pdfText, contains('THANK YOU VISIT AGAIN'));
  });
}
