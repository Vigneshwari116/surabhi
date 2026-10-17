import 'package:flutter/foundation.dart';
import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/services/daily_total_service.dart';
import 'package:surabhi/services/print_log_service.dart';
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
    final timings = SaveStepTimings(billNo: bill.billNo, scope: 'repository');
    await PrintLogService.append('save repository start billNo=${bill.billNo}');

    final SalesApiResult<int> apiResult;
    if (AppConfig.useServerApiEnabled) {
      final saveApi = saveBillApiOverride ?? SalesApi.saveBill;
      apiResult = await timings.timeAsync('save_api', () => saveApi(bill));
    } else {
      await PrintLogService.append(
        'save scope=repository billNo=${bill.billNo} step=save_api skipped (useServerApi=false) 0ms',
      );
      apiResult = SalesApiResult.failure('local-only');
    }
    final syncStatus = apiResult.ok ? 'synced' : 'pending';

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
          syncStatus: syncStatus,
        ),
      );

      await timings.timeAsync(
        'ledger_posting',
        () => SummaryUpdateService.onBillSaved(
          previous: previous,
          current: billToSave,
        ),
      );

      await timings.timeAsync('daily_total', () async {
        DailyTotalService.pushBillDelta(current: billToSave, previous: previous);
      });

      await timings.finish();
      return SalesApiResult.success(billToSave.billNo);
    } catch (_) {
      await timings.finish();
      if (apiResult.ok) {
        return apiResult;
      }
      return SalesApiResult.failure('Could not save bill locally.');
    }
  }
}
