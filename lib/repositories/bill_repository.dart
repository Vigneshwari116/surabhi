import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/models/save_bill_result.dart';
import 'package:surabhi/services/print_log_service.dart';
import 'package:surabhi/services/summary_update_service.dart';

class BillRepository {
  static Future<int> getNextBillNumber(String location) async {
    return LocalDb.instance.getNextBillNumber(location);
  }

  static Future<SaleBill?> getBillByNumber({
    required String location,
    required int billNo,
  }) async {
    final stored = await LocalDb.instance.getBillByNumber(
      location: location,
      billNo: billNo,
    );
    return stored?.bill;
  }

  static Future<SaleBill?> getPreviousBill({
    required String location,
    required int beforeBillNo,
  }) async {
    final stored = await LocalDb.instance.getPreviousBill(
      location: location,
      beforeBillNo: beforeBillNo,
    );
    return stored?.bill;
  }

  static Future<SaleBill?> getNextBill({
    required String location,
    required int afterBillNo,
  }) async {
    final stored = await LocalDb.instance.getNextBill(
      location: location,
      afterBillNo: afterBillNo,
    );
    return stored?.bill;
  }

  static Future<SaveBillResult> saveBill(
    SaleBill bill, {
    String? updateLocalId,
  }) async {
    final timings = SaveStepTimings(billNo: bill.billNo, scope: 'repository');
    await PrintLogService.append('save repository start billNo=${bill.billNo}');

    SaleBill? previous;
    try {
      final billToSave = await timings.timeAsync('numbering', () async {
        var resolved = bill;
        if (updateLocalId != null) {
          previous = await LocalDb.instance.getBillByLocalId(updateLocalId);
        } else {
          final existingId = await LocalDb.instance.findLocalIdByBillNo(
            location: bill.location,
            billNo: bill.billNo,
          );
          if (existingId != null) {
            previous = await LocalDb.instance.getBillByLocalId(existingId);
            final freeNo = await LocalDb.instance.findNextFreeBillNo(
              bill.location,
              startingAt: bill.billNo,
            );
            if (freeNo != bill.billNo) {
              resolved = SaleBill(
                billNo: freeNo,
                location: bill.location,
                billDate: bill.billDate,
                paymentMode: bill.paymentMode,
                customerName: bill.customerName,
                mobile: bill.mobile,
                items: bill.items,
                totalQty: bill.totalQty,
                totalAmount: bill.totalAmount,
                totalCgst: bill.totalCgst,
                totalSgst: bill.totalSgst,
                totalIgst: bill.totalIgst,
                grandTotal: bill.grandTotal,
                deleted: bill.deleted,
              );
            }
          }
        }
        return resolved;
      });

      await timings.timeAsync(
        'persist_local',
        () => LocalDb.instance.persistBill(
          billToSave,
          updateLocalId: updateLocalId,
          syncStatus: kLocalBillSyncStatus,
        ),
      );

      await timings.timeAsync(
        'ledger_posting',
        () => SummaryUpdateService.onBillSaved(
          previous: previous,
          current: billToSave,
        ),
      );

      await timings.finish();
      return SaveBillResult.success(billToSave.billNo);
    } catch (_) {
      await timings.finish();
      return SaveBillResult.failure('Could not save bill locally.');
    }
  }
}
