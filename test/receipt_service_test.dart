import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/receipt_service.dart';

const _paperWidth = 48;
const _margin = 8;
const _contentStart = _margin;

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
  test('header shows Surabhi Exports and Thargupet address', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill()).split('\n');
    final text = lines.join('\n');

    expect(text, contains('SURABHI EXPORTS'));
    expect(text, contains('THARGUPET'));
    expect(text, contains('29ACDPJ2452J1ZK'));
    expect(text, contains('BILL NO:133'));
    expect(text, contains('DATE:13/10/2026'));
    _expectLinesWithinThermalWidth(text);
    _expectBalancedMargins(text);
  });

  test('item table includes particular column aligned under headers', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill()).split('\n');
    final header = lines.firstWhere((line) => line.contains('PARTICULAR'));
    final itemLine = lines.firstWhere(
      (line) => line.contains('Shirt') && line.contains('50.00'),
    );

    expect(header.length, _paperWidth);
    expect(itemLine.length, _paperWidth);
    expect(header.trim(), contains('SNO'));
    expect(header.trim(), contains('PARTICULAR'));
    expect(header.trim(), contains('RATE'));
    expect(header.trim(), contains('QTY'));
    expect(header.trim(), contains('AMOUNT'));

    expect(itemLine.substring(_contentStart, _contentStart + 3).trim(), '1');
    expect(
      itemLine.substring(_contentStart + 3, _contentStart + 14).trim(),
      'Shirt',
    );
    expect(
      itemLine.substring(_contentStart + 14, _contentStart + 20).trim(),
      '50',
    );
    expect(
      itemLine.substring(_contentStart + 20, _contentStart + 24).trim(),
      '1',
    );
    expect(itemLine.substring(_contentStart + 24).trim(), '50.00');

    _expectLinesWithinThermalWidth(lines.join('\n'));
    _expectBalancedMargins(lines.join('\n'));
  });

  test('receipt shows per-item gst line', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    expect(text, contains('CGST% 2.5SGST% 2.5'));
    expect(text, contains('GRAND TOTAL'));
  });
}

void _expectLinesWithinThermalWidth(String text) {
  for (final line in text.split('\n')) {
    expect(
      line.length,
      lessThanOrEqualTo(_paperWidth),
      reason: 'Line exceeds thermal width: "$line"',
    );
  }
}

void _expectBalancedMargins(String text) {
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      continue;
    }
    expect(line.length, _paperWidth);
    expect(line.substring(0, _margin), equals(' ' * _margin));
    expect(line.substring(_paperWidth - _margin), equals(' ' * _margin));
  }
}
