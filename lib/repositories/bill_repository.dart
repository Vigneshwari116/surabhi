import 'package:flutter/foundation.dart';
import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/services/daily_total_service.dart';
import 'package:surabhi/services/summary_update_service.dart';

class BillRepository {
  /// When set (tests only), replaces [SalesApi.saveBill] for faster, offline saves.
  @visibleForTesting
  static Future<SalesApiResult<int>> Function(SaleBill bill)?
      saveBillApiOverride;

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

  static Future<SalesApiResult<int>> saveBill(
    SaleBill bill, {
    String? updateLocalId,
  }) async {
    final saveApi = saveBillApiOverride ?? SalesApi.saveBill;
    final apiResult = await saveApi(bill);
    final syncStatus = apiResult.ok ? 'synced' : 'pending';

    SaleBill? previous;
    try {
      var billToSave = bill;
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
            billToSave = SaleBill(
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

      await LocalDb.instance.persistBill(
        billToSave,
        updateLocalId: updateLocalId,
        syncStatus: syncStatus,
      );

      await SummaryUpdateService.onBillSaved(
        previous: previous,
        current: billToSave,
      );
      DailyTotalService.pushBillDelta(current: billToSave, previous: previous);
      return SalesApiResult.success(billToSave.billNo);
    } catch (_) {
      if (apiResult.ok) {
        return apiResult;
      }
      return SalesApiResult.failure('Could not save bill locally.');
    }
  }
}
