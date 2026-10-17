import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:surabhi/models/ledger_summary.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/screen/sales_ledger_screen.dart';

LedgerSummary _summary() {
  return LedgerSummary(
    total: 1000,
    cgst: 25,
    sgst: 25,
    igst: 0,
    grandTotal: 1050,
    totalPcs: 10,
  );
}

LocalLedgerEntry _entry(int billNo) {
  return LocalLedgerEntry(
    localId: 'id-$billNo',
    billNo: billNo,
    location: 'Surabhi',
    date: '2026-10-16',
    customerName: 'Customer',
    mobile: '9999999999',
    paymentMode: 'CASH',
    total: 500,
    cgst: 12.5,
    sgst: 12.5,
    igst: 0,
    grandTotal: 525,
    pcs: 2,
    syncStatus: 'synced',
    groupSummary: 'SHIRT, T/JEANS',
  );
}

Future<void> _pumpLedger(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  await tester.pumpWidget(
    MaterialApp(
      home: SalesLedgerScreen(
        location: 'Surabhi',
        autoRefreshOnOpen: false,
        loadLedgerOverride: () async => (
          entries: [_entry(7)],
          summary: _summary(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectGrandTotalHeaderFullyVisible(
  WidgetTester tester,
  double viewportWidth,
) {
  final header = find.byKey(const Key('ledger_grand_total_header'));
  expect(header, findsOneWidget);
  final rect = tester.getRect(header);
  expect(
    rect.right,
    lessThanOrEqualTo(viewportWidth),
    reason: 'GRAND TOTAL header right=${rect.right} exceeds $viewportWidth',
  );
  expect(rect.left, greaterThanOrEqualTo(0));
}

void main() {
  testWidgets('GRAND TOTAL header visible without horizontal scroll at 1920',
      (tester) async {
    await _pumpLedger(tester, 1920);
    _expectGrandTotalHeaderFullyVisible(tester, 1920);
  });

  testWidgets('GRAND TOTAL header visible without horizontal scroll at 1366',
      (tester) async {
    await _pumpLedger(tester, 1366);
    _expectGrandTotalHeaderFullyVisible(tester, 1366);
  });

  testWidgets('GRAND TOTAL header visible without horizontal scroll at 1260',
      (tester) async {
    await _pumpLedger(tester, 1260);
    _expectGrandTotalHeaderFullyVisible(tester, 1260);
  });

  testWidgets('narrow window can scroll horizontally to GRAND TOTAL header',
      (tester) async {
    await _pumpLedger(tester, 900);

    final header = find.byKey(const Key('ledger_grand_total_header'));
    expect(header, findsOneWidget);

    var rect = tester.getRect(header);
    if (rect.right > 900) {
      final horizontalScroll = find.byKey(
        const Key('report_table_horizontal_scroll'),
      );
      expect(horizontalScroll, findsOneWidget);
      final scrollable = find.descendant(
        of: horizontalScroll,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable.first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      rect = tester.getRect(header);
    }

    expect(rect.right, lessThanOrEqualTo(900 + 2));
    expect(find.byKey(const Key('report_table_horizontal_scroll')), findsOneWidget);
    expect(find.byKey(const Key('report_table_vertical_scroll')), findsOneWidget);
  });
}
