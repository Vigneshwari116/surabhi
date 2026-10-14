import 'package:shared_preferences/shared_preferences.dart';

import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/services/location_seed_service.dart';

/// Line-item CSV import is disabled for the single-location Surabhi build.
class LocationBillDetailSeedService {
  static const _seedVersion = '1';
  static final Map<String, Future<void>> _activeSeeds = {};

  static Future<void> ensureAllLocationsSeeded() async {
    for (final code in allLocationCodes) {
      await ensureLocationSeeded(code);
    }
  }

  static Future<void> ensureLocationSeeded(String locationCode) async {
    if (!isActiveLocationCode(locationCode)) {
      return;
    }

    await LocationSeedService.ensureLocationSeeded(locationCode);

    final running = _activeSeeds[locationCode];
    if (running != null) {
      await running;
      return;
    }

    final task = _markSeedComplete(locationCode);
    _activeSeeds[locationCode] = task;
    try {
      await task;
    } finally {
      _activeSeeds.remove(locationCode);
    }
  }

  static Future<void> _markSeedComplete(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final seedKey = 'location_bill_detail_seed_${locationCode}_v$_seedVersion';
    await prefs.setBool(seedKey, true);
  }
}
