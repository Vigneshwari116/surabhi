import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart' as db;
import 'package:surabhi/models/ledger_summary.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/services/location_bill_detail_seed_service.dart';
import 'package:surabhi/services/location_seed_service.dart';
import 'package:surabhi/services/summary_update_service.dart';

class LocalLedgerEntry {
  final String localId;
  final int billNo;
  final String location;
  final String date;
  final String customerName;
  final String mobile;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;
  final double pcs;
  final String syncStatus;
  final String groupSummary;

  LocalLedgerEntry({
    required this.localId,
    required this.billNo,
    required this.location,
    required this.date,
    required this.customerName,
    required this.mobile,
    required this.paymentMode,
    required this.total,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
    required this.pcs,
    required this.syncStatus,
    this.groupSummary = '',
  });
}

class LedgerRepository {
  static Future<
      ({List<LocalLedgerEntry> entries, LedgerSummary summary})> getLedger({
    required String location,
    String? from,
    String? to,
  }) async {
    try {
      if (AppConfig.isLocationSet) {
        await db.LocalDb.instance.initialize();
        await LocationSeedService.ensureLocationSeeded(AppConfig.locationCode);
        await LocationBillDetailSeedService.ensureLocationSeeded(
          AppConfig.locationCode,
        );
      }

      final rows = await db.LocalDb.instance.getLedgerEntries(
        location,
        from: from,
        to: to,
      );

      final entries = rows
          .map(
            (row) => LocalLedgerEntry(
              localId: row.localId,
              billNo: row.billNo,
              location: row.location,
              date: row.billDate,
              customerName: row.customerName,
              mobile: row.mobile,
              paymentMode: row.paymentMode,
              total: row.totalAmount,
              cgst: row.totalCgst,
              sgst: row.totalSgst,
              igst: row.totalIgst,
              grandTotal: row.grandTotal,
              pcs: row.totalQty,
              syncStatus: row.syncStatus,
              groupSummary: row.groupSummary,
            ),
          )
          .toList(growable: false);

      return (
        entries: entries,
        summary: _buildSummary(entries),
      );
    } catch (_) {
      return (
        entries: <LocalLedgerEntry>[],
        summary: LedgerSummary(
          total: 0,
          cgst: 0,
          sgst: 0,
          igst: 0,
          grandTotal: 0,
          totalPcs: 0,
        ),
      );
    }
  }

  static Future<SaleBill?> getBillByLocalId({
    required String location,
    required String localId,
  }) async {
    try {
      await db.LocalDb.instance.initialize();
      final fromActiveDb = await db.LocalDb.instance.getBillByLocalId(localId);
      if (fromActiveDb != null) {
        return fromActiveDb;
      }
    } catch (_) {
      // Best-effort read.
    }
    return null;
  }

  static Future<void> softDeleteBill(String localId) async {
    final bill = await db.LocalDb.instance.getBillByLocalId(localId);
    await db.LocalDb.instance.markBillDeleted(localId);
    if (bill != null) {
      await SummaryUpdateService.onBillDeleted(bill);
    }
  }

  static LedgerSummary _buildSummary(List<LocalLedgerEntry> entries) {
    var total = 0.0;
    var cgst = 0.0;
    var sgst = 0.0;
    var igst = 0.0;
    var grandTotal = 0.0;
    var totalPcs = 0.0;

    for (var entry in entries) {
      total += entry.total;
      cgst += entry.cgst;
      sgst += entry.sgst;
      igst += entry.igst;
      grandTotal += entry.grandTotal;
      totalPcs += entry.pcs;
    }

    return LedgerSummary(
      total: total,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      grandTotal: grandTotal,
      totalPcs: totalPcs,
    );
  }
}
