import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/esc_pos_receipt_service.dart';
import 'package:surabhi/services/receipt_service.dart';

SaleBill _sampleBill() {
  return SaleBill(
    billNo: 17367,
    location: 'Surabhi',
    billDate: DateTime(2026, 9, 4),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [
      BillItem(qty: 1, rate: 30),
      BillItem(qty: 1, rate: 100),
    ],
    totalQty: 2,
    totalAmount: 123.81,
    totalCgst: 3.25,
    totalSgst: 3.25,
    totalIgst: 0,
    grandTotal: 130,
  );
}

void main() {
  test('esc pos bytes start with init, font A, and bold commands', () {
    final bytes = EscPosReceiptService.buildReceiptBytes(_sampleBill());

    expect(bytes.length, greaterThan(20));
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);
    expect(bytes, contains(0x4D)); // Font select
    expect(bytes, contains(0x32)); // Default line spacing
    expect(bytes, containsAll([0x1B, 0x45, 0x01])); // bold on
    expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x01]); // partial cut
  });

  test('esc pos payload includes receipt text lines', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    final bytes = EscPosReceiptService.buildReceiptBytesFromText(text);
    final payload = String.fromCharCodes(bytes);

    expect(payload, contains('SURABHI EXPORTS'));
    expect(payload, contains('THARGUPET'));
    expect(payload, contains('BILL NO:17367'));
    expect(payload, contains('GRAND TOTAL'));
    expect(payload, contains('THANK YOU VISIT AGAIN'));
  });

  test('esc pos does not set GS L/GS W print area that wraps columns early', () {
    final bytes = EscPosReceiptService.buildReceiptBytes(_sampleBill());

    expect(_containsEscPosCommand(bytes, 0x4C), isFalse); // GS L left margin
    expect(_containsEscPosCommand(bytes, 0x57), isFalse); // GS W print width
  });

  test('esc pos uses hardware center align for GSTIN and thank-you', () {
    final bytes = EscPosReceiptService.buildReceiptBytes(_sampleBill());
    expect(
      _hasCenterAlignBefore(bytes, 'GSTIN:'),
      isTrue,
      reason: 'GSTIN should be printed with ESC a 1 center align',
    );
    expect(
      _hasCenterAlignBefore(bytes, 'THANK YOU VISIT AGAIN'),
      isTrue,
      reason: 'Thank-you footer should be center aligned on thermal',
    );
  });

  test('esc pos lines are padded to exactly 48 characters', () {
    final bytes = EscPosReceiptService.buildReceiptBytesFromText('HELLO');
    final helloIndex = bytes.indexOf('H'.codeUnitAt(0));
    final lineEnd = bytes.indexOf(0x0A, helloIndex);

    expect(lineEnd, helloIndex + 48);
    expect(
      String.fromCharCodes(bytes.sublist(helloIndex, helloIndex + 5)),
      'HELLO',
    );

    final longLine = 'X' * 60;
    final longBytes = EscPosReceiptService.buildReceiptBytesFromText(longLine);
    final xStart = longBytes.indexOf('X'.codeUnitAt(0));
    var xRun = 0;
    for (var i = xStart; i < longBytes.length && longBytes[i] == 'X'.codeUnitAt(0); i++) {
      xRun++;
    }

    expect(xRun, 48);
  });
}

bool _hasCenterAlignBefore(List<int> bytes, String text) {
  final marker = text.codeUnits;
  for (var i = 0; i <= bytes.length - marker.length; i++) {
    var matches = true;
    for (var j = 0; j < marker.length; j++) {
      if (bytes[i + j] != marker[j]) {
        matches = false;
        break;
      }
    }
    if (!matches) {
      continue;
    }
    final searchStart = (i - 12).clamp(0, i);
    for (var k = searchStart; k < i; k++) {
      if (k + 2 < bytes.length &&
          bytes[k] == 0x1B &&
          bytes[k + 1] == 0x61 &&
          bytes[k + 2] == 0x01) {
        return true;
      }
    }
  }
  return false;
}

bool _containsEscPosCommand(List<int> bytes, int commandByte) {
  for (var index = 0; index < bytes.length - 1; index++) {
    if (bytes[index] == 0x1D && bytes[index + 1] == commandByte) {
      return true;
    }
  }
  return false;
}
