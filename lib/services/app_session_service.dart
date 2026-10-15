import 'dart:async';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/db/summary_db.dart';
import 'package:surabhi/services/location_bill_detail_seed_service.dart';
import 'package:surabhi/services/location_seed_service.dart';
import 'package:surabhi/services/session_service.dart';
import 'package:surabhi/services/old_sales_import_service.dart';
import 'package:surabhi/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    final role = await SessionService.getRole();

    if (role == SessionRole.summaryViewer) {
      try {
        await SummaryDb.instance.initialize();
      } catch (_) {
        // Summary-only login should still open the lightweight screens.
      }
      return;
    }

    if (role == SessionRole.admin) {
      unawaited(_initializeSummaryInBackground());
      return;
    }

    try {
      await LocalDb.instance.initialize();
      await LocationSeedService.ensureLocationSeeded(AppConfig.locationCode);
      await LocationBillDetailSeedService.ensureLocationSeeded(
        AppConfig.locationCode,
      );
      await SummaryDb.instance.initialize();
      await SummaryDb.instance.ensureBootstrapped();
      await OldSalesImportService.runOnceIfNeeded();
    } catch (_) {
      // Login must succeed even if the local database is temporarily unavailable.
    }

    if (!AppConfig.offlineOnly) {
      SyncService.instance.start(location: AppConfig.displayLocationName);
    }
  }

  static Future<void> _initializeSummaryInBackground() async {
    try {
      await SummaryDb.instance.initialize();
      await SummaryDb.instance.ensureBootstrapped();
    } catch (_) {
      // Summary totals are best-effort until bootstrap completes.
    }
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    try {
      await LocalDb.instance.close();
    } catch (_) {
      // Ignore close errors during logout.
    }
  }
}
