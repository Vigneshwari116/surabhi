import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/db/local_db.dart' as db;
import 'package:surabhi/db/location_database.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/services/location_bill_detail_seed_service.dart';
import 'package:surabhi/services/location_seed_service.dart';
import 'package:surabhi/services/summary_update_service.dart';
import 'package:surabhi/services/sync_service.dart';

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
  final String syncStatus;

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
    required this.syncStatus,
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
      final locationCode = locationCodeFromDisplayName(location);
      await LocationSeedService.ensureLocationSeeded(locationCode);
      await LocationBillDetailSeedService.ensureLocationSeeded(locationCode);
      final rows = await LocationDatabase.getLedgerEntries(
        location: location,
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
              syncStatus: row.syncStatus,
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
        ),
      );
    }
  }

  static Future<SaleBill?> getBillByLocalId({
    required String location,
    required String localId,
  }) async {
    if (AppConfig.isLocationSet) {
      try {
        await db.LocalDb.instance.initialize();
        final fromActiveDb = await db.LocalDb.instance.getBillByLocalId(localId);
        if (fromActiveDb != null) {
          return fromActiveDb;
        }
      } catch (_) {
        // Fall through to per-location file read.
      }
    }

    final locationCode = locationCodeFromDisplayName(location);
    return LocationDatabase.getBillByLocalId(
      locationCode: locationCode,
      localId: localId,
    );
  }

  static Future<void> softDeleteBill(String localId) async {
    final bill = await db.LocalDb.instance.getBillByLocalId(localId);
    await db.LocalDb.instance.markBillDeleted(localId);
    if (bill != null) {
      await SummaryUpdateService.onBillDeleted(bill);
    }
  }

  static Future<void> refreshFromServer({required String location}) async {
    await SyncService.instance.pullAdminUpdates(location);
  }

  static LedgerSummary _buildSummary(List<LocalLedgerEntry> entries) {
    var total = 0.0;
    var cgst = 0.0;
    var sgst = 0.0;
    var igst = 0.0;
    var grandTotal = 0.0;

    for (var entry in entries) {
      total += entry.total;
      cgst += entry.cgst;
      sgst += entry.sgst;
      igst += entry.igst;
      grandTotal += entry.grandTotal;
    }

    return LedgerSummary(
      total: total,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      grandTotal: grandTotal,
    );
  }
}
