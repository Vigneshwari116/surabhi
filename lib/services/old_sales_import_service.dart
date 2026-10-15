import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/db/summary_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/screen/bill_item.dart';

/// One-time import of legacy sales rows (surabhi_old_sales_import.pdf).
class OldSalesImportReport {
  final int billsImported;
  final int billsSkipped;
  final int rowsImported;
  final List<int> blankPaymentBillNos;
  final String? backupPath;

  const OldSalesImportReport({
    required this.billsImported,
    required this.billsSkipped,
    required this.rowsImported,
    required this.blankPaymentBillNos,
    this.backupPath,
  });

  bool get shouldShowUi =>
      billsImported > 0 || billsSkipped > 0 || blankPaymentBillNos.isNotEmpty;

  String toDisplayText() {
    final blank = blankPaymentBillNos.isEmpty
        ? 'none'
        : blankPaymentBillNos.join(', ');
    final backup = backupPath == null ? '' : '\nBackup: $backupPath';
    return 'Old sales import\n'
        'Bills imported: $billsImported\n'
        'Bills skipped: $billsSkipped\n'
        'Rows imported: $rowsImported\n'
        'Blank payment mode (default applied): $blank$backup';
  }

  Map<String, dynamic> toJson() => {
        'billsImported': billsImported,
        'billsSkipped': billsSkipped,
        'rowsImported': rowsImported,
        'blankPaymentBillNos': blankPaymentBillNos,
        'backupPath': backupPath,
      };

  factory OldSalesImportReport.fromJson(Map<String, dynamic> json) {
    return OldSalesImportReport(
      billsImported: (json['billsImported'] as num?)?.toInt() ?? 0,
      billsSkipped: (json['billsSkipped'] as num?)?.toInt() ?? 0,
      rowsImported: (json['rowsImported'] as num?)?.toInt() ?? 0,
      blankPaymentBillNos: (json['blankPaymentBillNos'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList(growable: false) ??
          const [],
      backupPath: json['backupPath'] as String?,
    );
  }
}

class OldSalesImportService {
  static const _prefDoneKey = 'old_sales_import_v1_done';
  static const _prefReportKey = 'old_sales_import_v1_report';

  /// App default when legacy file left payment blank (bills 4 and 7).
  static const String defaultPaymentModeWhenBlank = 'UPI';

  static final DateTime importDay = DateTime(2026, 10, 13);

  static Future<void> runOnceIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefDoneKey) == true) {
      return;
    }

    final report = await runImport();
    await prefs.setBool(_prefDoneKey, true);
    if (report.shouldShowUi) {
      await prefs.setString(_prefReportKey, jsonEncode(report.toJson()));
    }
  }

  static Future<OldSalesImportReport?> consumeReportForUi() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefReportKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    await prefs.remove(_prefReportKey);
    return OldSalesImportReport.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  static Future<OldSalesImportReport> runImport() async {
    await LocalDb.instance.initialize();
    final location = AppConfig.displayLocationName;

    final backupPath = await _backupSalesDatabases();

    await _ensureMasterGroups();

    var billsImported = 0;
    var billsSkipped = 0;
    var rowsImported = 0;
    final blankPaymentBills = <int>[];

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
        continue;
      }

      final items = <BillItem>[];
      for (final row in rows) {
        final groupName = await _resolveGroupName(row.group);
        items.add(
          BillItem(
            particular: groupName,
            qty: row.qty,
            rate: row.rate,
            cgstPct: 2.5,
            sgstPct: 2.5,
            igstPct: 0,
          ),
        );
        rowsImported++;
      }

      final paymentFromFile = rows.first.paymentFromFile;
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
        rowsImported -= items.length;
      }
    }

    await SummaryDb.instance.initialize();
    await SummaryDb.instance.rebuildSummariesForDays(
      location: location,
      days: [importDay],
    );

    await LocalDb.instance.refreshNextBillNoFromBills(location);

    return OldSalesImportReport(
      billsImported: billsImported,
      billsSkipped: billsSkipped,
      rowsImported: rowsImported,
      blankPaymentBillNos: blankPaymentBills,
      backupPath: backupPath,
    );
  }

  /// Verifies table B totals for 13 Oct 2026 after import.
  static Future<bool> verifyTableBTotals(String location) async {
    final summary = await AbstractRepository.getSummaryForDateRange(
      location: location,
      fromDate: importDay,
      toDate: importDay,
    );
    final pcs = await AbstractRepository.getTotalPcsForDateRange(
      location: location,
      fromDate: importDay,
      toDate: importDay,
    );
    final grand = summary.totalSaleAmount + summary.totalGst;
    return summary.totalSaleAmount == 12950 &&
        summary.totalGst == 650 &&
        grand == 13600 &&
        pcs == 18;
  }

  static SaleBill _billFromItems({
    required int billNo,
    required String location,
    required DateTime billDate,
    required String paymentMode,
    required List<BillItem> items,
  }) {
    var totalQty = 0.0;
    var totalAmount = 0.0;
    var totalCgst = 0.0;
    var totalSgst = 0.0;
    var totalIgst = 0.0;
    var grandTotal = 0.0;

    for (final item in items) {
      totalQty += item.qty;
      totalAmount += item.amount;
      totalCgst += item.cgst;
      totalSgst += item.sgst;
      totalIgst += item.igst;
      grandTotal += item.grossAmt;
    }

    return SaleBill(
      billNo: billNo,
      location: location,
      billDate: billDate,
      paymentMode: paymentMode,
      customerName: '',
      mobile: '',
      items: items,
      totalQty: totalQty,
      totalAmount: totalAmount,
      totalCgst: totalCgst,
      totalSgst: totalSgst,
      totalIgst: totalIgst,
      grandTotal: grandTotal,
    );
  }

  static Future<void> _ensureMasterGroups() async {
    final names = await LocalDb.instance.listMasterItemNames();
    final normalized = names.map((n) => n.toUpperCase()).toSet();
    for (final required in ['SHIRT', 'T/JEANS']) {
      if (!normalized.contains(required)) {
        try {
          await LocalDb.instance.insertMasterItem(
            required == 'SHIRT' ? 'Shirt' : 'T/JEANS',
          );
        } catch (_) {
          // Already present with different casing.
        }
      }
    }
  }

  static Future<String> _resolveGroupName(String raw) async {
    final names = await LocalDb.instance.listMasterItemNames();
    final upper = raw.trim().toUpperCase();
    for (final name in names) {
      if (name.toUpperCase() == upper) {
        return name;
      }
    }
    final canonical = raw.trim();
    try {
      await LocalDb.instance.insertMasterItem(canonical);
    } catch (_) {}
    return canonical;
  }

  static Future<String> _backupSalesDatabases() async {
    final supportDir = await getApplicationSupportDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backupDir = Directory(
      p.join(supportDir.path, 'backups', 'pre_old_sales_import_$stamp'),
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

  static Map<int, List<_ImportRow>> _groupRowsByBill() {
    final map = <int, List<_ImportRow>>{};
    for (final row in _cleanedRows) {
      map.putIfAbsent(row.billNo, () => []).add(row);
    }
    return map;
  }

  /// Cleaned rows from surabhi_old_sales_import.pdf (page 2).
  static final List<_ImportRow> _cleanedRows = [
    _ImportRow(1, DateTime(2026, 10, 13, 19, 20, 55), 1, 'SHIRT', 12, 1, 'CASH'),
    _ImportRow(1, DateTime(2026, 10, 13, 19, 20, 55), 2, 'SHIRT', 3, 1, 'CASH'),
    _ImportRow(2, DateTime(2026, 10, 13, 19, 25, 17), 1, 'SHIRT', 120, 1, 'CASH'),
    _ImportRow(2, DateTime(2026, 10, 13, 19, 25, 17), 2, 'SHIRT', 55, 1, 'CASH'),
    _ImportRow(3, DateTime(2026, 10, 13, 19, 27, 34), 1, 'SHIRT', 2322, 1, 'CASH'),
    _ImportRow(3, DateTime(2026, 10, 13, 19, 27, 34), 2, 'SHIRT', 5, 1, 'CASH'),
    _ImportRow(4, DateTime(2026, 10, 13, 19, 28, 15), 1, 'SHIRT', 121, 1, null),
    _ImportRow(4, DateTime(2026, 10, 13, 19, 28, 15), 2, 'SHIRT', 333, 1, null),
    _ImportRow(4, DateTime(2026, 10, 13, 19, 28, 15), 3, 'SHIRT', 77, 1, null),
    _ImportRow(5, DateTime(2026, 10, 13, 20, 0, 42), 1, 'SHIRT', 444, 1, 'CASH'),
    _ImportRow(6, DateTime(2026, 10, 13, 20, 36, 11), 1, 'SHIRT', 5000, 1, 'CASH'),
    _ImportRow(6, DateTime(2026, 10, 13, 20, 36, 11), 2, 'SHIRT', 230, 1, 'CASH'),
    _ImportRow(7, DateTime(2026, 10, 13, 20, 40, 55), 1, 'T/JEANS', 23, 1, null),
    _ImportRow(7, DateTime(2026, 10, 13, 20, 40, 55), 2, 'T/JEANS', 55, 1, null),
    _ImportRow(7, DateTime(2026, 10, 13, 20, 40, 55), 3, 'T/JEANS', 1200, 4, null),
  ];
}

class _ImportRow {
  final int billNo;
  final DateTime dateTime;
  final int sno;
  final String group;
  final double rate;
  final double qty;
  final String? paymentFromFile;

  const _ImportRow(
    this.billNo,
    this.dateTime,
    this.sno,
    this.group,
    this.rate,
    this.qty,
    this.paymentFromFile,
  );
}
