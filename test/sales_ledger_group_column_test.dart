import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:surabhi/models/ledger_summary.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/screen/sales_ledger_screen.dart';
import 'package:surabhi/utils/ledger_group_display.dart';

LedgerSummary _summary() {
  return LedgerSummary(
    total: 500,
    cgst: 12.5,
    sgst: 12.5,
    igst: 0,
    grandTotal: 525,
    totalPcs: 2,
  );
}

LocalLedgerEntry _entry({
  required int billNo,
  required String groupSummary,
  double pcs = 2,
}) {
  return LocalLedgerEntry(
    localId: 'id-$billNo',
    billNo: billNo,
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
    pcs: pcs,
    syncStatus: 'synced',
    groupSummary: groupSummary,
  );
}

Future<void> _pumpLedger(
  WidgetTester tester,
  List<LocalLedgerEntry> entries,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 700));
  await tester.pumpWidget(
    MaterialApp(
      home: SalesLedgerScreen(
        location: 'Surabhi',
        autoRefreshOnOpen: false,
        loadLedgerOverride: () async => (
          entries: entries,
          summary: _summary(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectUniformRowHeights(WidgetTester tester, int billNo) {
  final rowFinder = find.byKey(Key('ledger_row_flex_$billNo'));
  expect(rowFinder, findsOneWidget);

  final renderRow = tester.renderObject<RenderFlex>(rowFinder);
  final heights = <double>[];
  renderRow.visitChildren((child) {
    heights.add((child as RenderBox).size.height);
  });

  expect(heights, isNotEmpty);
  for (final height in heights) {
    expect(height, closeTo(heights.first, 0.5));
  }
}

void main() {
  test('ledger group display wraps only after comma between groups', () {
    expect(
      LedgerGroupDisplay.lines('SHIRT, T/JEANS'),
      ['SHIRT, T/JEANS'],
    );
    expect(
      LedgerGroupDisplay.lines('GENTS WEAR, SHIRT'),
      ['GENTS WEAR, SHIRT'],
    );
    expect(
      LedgerGroupDisplay.lines('GENTS WEAR, SHIRT, T/JEANS, PANT'),
      ['GENTS WEAR, SHIRT', 'T/JEANS, PANT'],
    );
    expect(
      LedgerGroupDisplay.formatForDisplay('SHIRT, T/JEANS'),
      'SHIRT, T/JEANS',
    );
    expect(
      LedgerGroupDisplay.formatForDisplay('SHIRT, T/JEANS').contains('/\n'),
      isFalse,
    );
  });

  testWidgets('long group name does not overlap mobile column', (tester) async {
    const longGroup = 'GENTS WEAR';
    await _pumpLedger(tester, [_entry(billNo: 42, groupSummary: longGroup)]);

    expect(find.text(longGroup), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);

    final groupBox = tester.getRect(find.text(longGroup));
    final mobileBox = tester.getRect(find.text('9876543210'));

    expect(
      groupBox.right,
      lessThanOrEqualTo(mobileBox.left + 1),
      reason: 'GROUP text should not extend into MOBILE column',
    );
  });

  testWidgets('two groups stay on one line with equal row cell heights',
      (tester) async {
    const groups = 'SHIRT, T/JEANS';
    await _pumpLedger(tester, [_entry(billNo: 7, groupSummary: groups)]);

    expect(find.text(groups), findsOneWidget);
    expect(tester.takeException(), isNull);
    _expectUniformRowHeights(tester, 7);
  });

  testWidgets('four groups wrap in GROUP cell with equal row height',
      (tester) async {
    const groups = 'GENTS WEAR, SHIRT, T/JEANS, PANT';
    await _pumpLedger(tester, [_entry(billNo: 8, groupSummary: groups)]);

    expect(find.textContaining('GENTS WEAR, SHIRT'), findsOneWidget);
    expect(find.textContaining('T/JEANS, PANT'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _expectUniformRowHeights(tester, 8);
  });
}
