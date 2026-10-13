import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/services/daily_total_service.dart';

class DailyTotalRepository {
  /// Fetches live server totals keyed by display location name (Win1, Win2, Win3).
  /// Returns null when the server cannot be reached.
  static Future<Map<String, double>?> fetchLiveTotals({
    DateTime? date,
  }) async {
    await DailyTotalService.flushPending();

    final result = await SalesApi.getDailyTotals(date: date);
    if (!result.ok || result.data == null) {
      return null;
    }

    final totals = result.data!;
    return {
      for (final code in allLocationCodes)
        displayNameForLocationCode(code): totals[code] ?? 0,
    };
  }
}
