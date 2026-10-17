import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/data/old_sales_import_v2_rows.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/db/summary_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/utils/bill_gst_totals.dart';

/// One-time import of legacy sales rows (surabhi_old_sales_import2.pdf).
class OldSalesImportReport {
  final int billsImported;
  final int billsSkipped;
  final int rowsImported;
  final int rowsSkipped;
  final List<int> blankPaymentBillNos;
  final List<int> skippedExistingBillNos;
  final String? backupPath;

  const OldSalesImportReport({
    required this.billsImported,
    required this.billsSkipped,
    required this.rowsImported,
    required this.rowsSkipped,
    required this.blankPaymentBillNos,
    required this.skippedExistingBillNos,
    this.backupPath,
  });

  bool get shouldShowUi =>
      billsImported > 0 ||
      billsSkipped > 0 ||
      rowsSkipped > 0 ||
      blankPaymentBillNos.isNotEmpty;

  String toDisplayText() {
    final blank = blankPaymentBillNos.isEmpty
        ? 'none'
        : '${blankPaymentBillNos.length} bills (${_shortList(blankPaymentBillNos)})';
    final skippedBills = skippedExistingBillNos.isEmpty
        ? 'none'
        : skippedExistingBillNos.join(', ');
    final backup = backupPath == null ? '' : '\nBackup: $backupPath';
    return 'Old sales import (v2)\n'
        'Bills imported: $billsImported\n'
        'Bills skipped (bill no. already exists): $billsSkipped — $skippedBills\n'
        'Rows imported: $rowsImported\n'
        'Rows skipped (broken row in file): $rowsSkipped\n'
        'Blank payment mode (default applied): $blank$backup';
  }

  static String _shortList(List<int> values) {
    if (values.length <= 12) {
      return values.join(', ');
    }
    return '${values.take(12).join(', ')}, ...';
  }

  Map<String, dynamic> toJson() => {
        'billsImported': billsImported,
        'billsSkipped': billsSkipped,
        'rowsImported': rowsImported,
        'rowsSkipped': rowsSkipped,
        'blankPaymentBillNos': blankPaymentBillNos,
        'skippedExistingBillNos': skippedExistingBillNos,
        'backupPath': backupPath,
      };

  factory OldSalesImportReport.fromJson(Map<String, dynamic> json) {
    return OldSalesImportReport(
      billsImported: (json['billsImported'] as num?)?.toInt() ?? 0,
      billsSkipped: (json['billsSkipped'] as num?)?.toInt() ?? 0,
      rowsImported: (json['rowsImported'] as num?)?.toInt() ?? 0,
      rowsSkipped: (json['rowsSkipped'] as num?)?.toInt() ?? 0,
      blankPaymentBillNos: (json['blankPaymentBillNos'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList(growable: false) ??
          const [],
      skippedExistingBillNos:
          (json['skippedExistingBillNos'] as List<dynamic>?)
                  ?.map((e) => (e as num).toInt())
                  .toList(growable: false) ??
              const [],
      backupPath: json['backupPath'] as String?,
    );
  }
}

class OldSalesImportService {
  static const _prefDoneKey = 'old_sales_import_v2_done';

  /// App default when legacy file left payment blank.
  static const String defaultPaymentModeWhenBlank = 'UPI';

  /// Table A verification day (11 Oct 2026).
  static final DateTime importDay = DateTime(2026, 10, 11);

  /// Broken row excluded from PDF (bill 7, S.NO 8).
  static const int rowsSkippedInSourceFile = 1;

  static final List<DateTime> summaryRebuildDays = [
    DateTime(2026, 10, 11),
    DateTime(2026, 10, 12),
    DateTime(2026, 10, 13),
    DateTime(2026, 10, 14),
    DateTime(2026, 10, 15),
  ];

  static Future<void> runOnceIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefDoneKey) == true) {
      return;
    }

    final report = await runImport();
    await prefs.setBool(_prefDoneKey, true);
    if (report.shouldShowUi) {
      developer.log(
        report.toDisplayText(),
        name: 'OldSalesImport',
      );
    }
  }

  static Future<OldSalesImportReport> runImport() async {
    await LocalDb.instance.initialize();
    final location = AppConfig.displayLocationName;

    final backupPath = await _backupSalesDatabases();

    var billsImported = 0;
    var billsSkipped = 0;
    var rowsImported = 0;
    final blankPaymentBills = <int>[];
    final skippedExisting = <int>[];

    final grouped = _groupRowsByBill();
    for (final entry in grouped.entries) {
      final billNo = entry.key;
      final rows = entry.value;
      rows.sort((a, b) => a.sno.compareTo(b.sno));

      final existing = await LocalDb.instance.getBillByNumber(
        location: location,
        billNo: billNo,
      );
      if (existing != null) {
        billsSkipped++;
        skippedExisting.add(billNo);
        continue;
      }

      final items = <BillItem>[];
      for (final row in rows) {
        items.add(
          BillItem(
            particular: row.group,
            qty: row.qty,
            rate: row.rate,
            cgstPct: 2.5,
            sgstPct: 2.5,
            igstPct: 0,
          ),
        );
        rowsImported++;
      }

      final paymentFromFile = rows.first.payment;
      final paymentMode = paymentFromFile ?? defaultPaymentModeWhenBlank;
      if (paymentFromFile == null) {
        blankPaymentBills.add(billNo);
      }

      final billDate = DateTime(
        rows.first.dateTime.year,
        rows.first.dateTime.month,
        rows.first.dateTime.day,
      );

      final bill = _billFromItems(
        billNo: billNo,
        location: location,
        billDate: billDate,
        paymentMode: paymentMode,
        items: items,
      );

      try {
        await LocalDb.instance.insertBill(bill, syncStatus: 'synced');
        billsImported++;
      } catch (_) {
        billsSkipped++;
        skippedExisting.add(billNo);
        rowsImported -= items.length;
      }
    }

    await SummaryDb.instance.initialize();
    await SummaryDb.instance.rebuildSummariesForDays(
      location: location,
      days: summaryRebuildDays,
    );

    await LocalDb.instance.refreshNextBillNoFromBills(location);

    blankPaymentBills.sort();
    skippedExisting.sort();

    return OldSalesImportReport(
      billsImported: billsImported,
      billsSkipped: billsSkipped,
      rowsImported: rowsImported,
      rowsSkipped: rowsSkippedInSourceFile,
      blankPaymentBillNos: blankPaymentBills,
      skippedExistingBillNos: skippedExisting,
      backupPath: backupPath,
    );
  }

  /// Verifies table A totals for [day] (taxable amount, GST, PCS).
  static Future<bool> verifyDayTotals({
    required String location,
    required DateTime day,
    required double expectedTaxable,
    required double expectedGst,
    required double expectedPcs,
  }) async {
    final summary = await AbstractRepository.getSummaryForDateRange(
      location: location,
      fromDate: day,
      toDate: day,
    );
    final grand = summary.totalSaleAmount + summary.totalGst;
    final expectedGrand = expectedTaxable + expectedGst;
    return summary.totalSaleAmount == expectedTaxable &&
        summary.totalGst == expectedGst &&
        grand == expectedGrand &&
        summary.totalPcs == expectedPcs;
  }

  /// Table A row for 11 Oct 2026 (full file, all bills on that date).
  static Future<bool> verifyTableBTotals(String location) {
    return verifyDayTotals(
      location: location,
      day: importDay,
      expectedTaxable: 47557,
      expectedGst: 2393,
      expectedPcs: 281,
    );
  }

  static SaleBill _billFromItems({
    required int billNo,
    required String location,
    required DateTime billDate,
    required String paymentMode,
    required List<BillItem> items,
  }) {
    final totals = computeBillGstTotalsFromItems(items);

    return SaleBill(
      billNo: billNo,
      location: location,
      billDate: billDate,
      paymentMode: paymentMode,
      customerName: '',
      mobile: '',
      items: items,
      totalQty: totals.totalQty,
      totalAmount: totals.totalAmount,
      totalCgst: totals.totalCgst,
      totalSgst: totals.totalSgst,
      totalIgst: totals.totalIgst,
      grandTotal: totals.grandTotal,
    );
  }

  static Future<String> _backupSalesDatabases() async {
    final supportDir = await getApplicationSupportDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backupDir = Directory(
      p.join(supportDir.path, 'backups', 'pre_old_sales_import_v2_$stamp'),
    );
    await backupDir.create(recursive: true);

    await for (final entity in supportDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('_sales.db') || name == SummaryDb.dbFileName) {
        await entity.copy(p.join(backupDir.path, name));
      }
    }

    return backupDir.path;
  }

  static Map<int, List<OldSalesImportV2Row>> _groupRowsByBill() {
    final map = <int, List<OldSalesImportV2Row>>{};
    for (final row in kOldSalesImportV2Rows) {
      map.putIfAbsent(row.billNo, () => []).add(row);
    }
    return map;
  }
}
