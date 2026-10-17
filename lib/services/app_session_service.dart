import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/db/summary_db.dart';
import 'package:surabhi/services/location_bill_detail_seed_service.dart';
import 'package:surabhi/services/location_seed_service.dart';
import 'package:surabhi/services/legacy_pdf_master_groups_service.dart';
import 'package:surabhi/services/old_sales_import_service.dart';
import 'package:surabhi/services/session_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    final role = await SessionService.getRole();
    if (role != SessionRole.staff) {
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
      await LegacyPdfMasterGroupsService.ensureOnStaffLogin();
      await OldSalesImportService.runOnceIfNeeded();
    } catch (_) {
      // Login must succeed even if the local database is temporarily unavailable.
    }
  }

  static Future<void> onLogout() async {
    try {
      await LocalDb.instance.close();
    } catch (_) {
      // Ignore close errors during logout.
    }
  }
}
