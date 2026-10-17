import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:surabhi/models/ledger_summary.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/screen/sales_ledger_screen.dart';

LocalLedgerEntry _entry({
  required int billNo,
  required String date,
  required String groupSummary,
}) {
  return LocalLedgerEntry(
    localId: 'id-$billNo',
    billNo: billNo,
    location: 'Surabhi',
    date: date,
    customerName: 'Customer $billNo',
    mobile: '',
    paymentMode: 'CASH',
    total: 100,
    cgst: 2.5,
    sgst: 2.5,
    igst: 0,
    grandTotal: 105,
    pcs: 3,
    syncStatus: 'synced',
    groupSummary: groupSummary,
  );
}

void main() {
  testWidgets('date range shows bill-wise table not day summary list', (tester) async {
    final entries = [
      _entry(billNo: 1, date: '2026-08-30', groupSummary: 'SHIRT'),
      _entry(billNo: 2, date: '2026-08-31', groupSummary: 'PANT'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Surabhi',
          autoRefreshOnOpen: false,
          loadLedgerOverride: () async => (
            entries: entries,
            summary: LedgerSummary(
              total: 200,
              cgst: 5,
              sgst: 5,
              igst: 0,
              grandTotal: 210,
              totalPcs: 6,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('BILLNO'), findsOneWidget);
    expect(find.textContaining('GRAND'), findsOneWidget);
    expect(find.textContaining('TOTAL'), findsWidgets);
    expect(find.text('Customer 1'), findsOneWidget);
    expect(find.text('Customer 2'), findsOneWidget);
    expect(find.text('SHIRT'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Grand total only'), findsNothing);
  });
}
