import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/screen/sales_ledger_screen.dart';

void main() {
  testWidgets('long group name does not overlap mobile column', (tester) async {
    const longGroup = 'GENTS WEAR';
    final entry = LocalLedgerEntry(
      localId: 'id-1',
      billNo: 42,
      location: 'Surabhi',
      date: '2026-10-15',
      customerName: 'Test',
      mobile: '9876543210',
      paymentMode: 'CASH',
      total: 500,
      cgst: 12.5,
      sgst: 12.5,
      igst: 0,
      grandTotal: 525,
      pcs: 2,
      syncStatus: 'synced',
      groupSummary: longGroup,
    );

    await tester.binding.setSurfaceSize(const Size(900, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Surabhi',
          autoRefreshOnOpen: false,
          loadLedgerOverride: () async => (
            entries: [entry],
            summary: LedgerSummary(
              total: 500,
              cgst: 12.5,
              sgst: 12.5,
              igst: 0,
              grandTotal: 525,
              totalPcs: 2,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(longGroup), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);

    final groupFinder = find.text(longGroup);
    final mobileFinder = find.text('9876543210');
    final groupBox = tester.getRect(groupFinder);
    final mobileBox = tester.getRect(mobileFinder);

    expect(
      groupBox.right,
      lessThanOrEqualTo(mobileBox.left + 1),
      reason: 'GROUP text should not extend into MOBILE column',
    );
  });
}
