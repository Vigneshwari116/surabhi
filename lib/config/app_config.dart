import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surabhi/config/sales_database.dart';

class AppConfig {
  /// Single shop — no server sync or multi-branch.
  static const bool offlineOnly = true;

  /// When false (Surabhi default), bill save and daily-total push skip VPS HTTP.
  static const bool useServerApi = false;

  @visibleForTesting
  static bool? useServerApiOverride;

  static bool get useServerApiEnabled =>
      useServerApiOverride ?? useServerApi;

  static String? _locationCode;

  static bool get isLocationSet =>
      _locationCode != null && _locationCode!.isNotEmpty;

  static String get locationCode {
    if (_locationCode == null) {
      throw StateError('Location not set — user must log in first');
    }
    return SalesDatabase.normalizeLocationCode(_locationCode!);
  }

  static String get expectedGstDbName => '${locationCode}_gst';

  static String get displayLocationName =>
      displayLocationNameFor(locationCode);

  static String displayLocationNameFor(String code) {
    switch (code) {
      case 'main':
        return 'Surabhi';
      default:
        return code;
    }
  }

  static Future<void> loadFromPrefs() async {
    var prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('location_code');
    if (stored == null) {
      _locationCode = null;
      return;
    }
    final normalized = _normalizeLocationCode(stored);
    _locationCode = normalized;
    if (normalized != stored) {
      await prefs.setString('location_code', normalized);
    }
  }

  static Future<void> setLocation(String code) async {
    final normalized = SalesDatabase.normalizeLocationCode(code);
    var prefs = await SharedPreferences.getInstance();
    await prefs.setString('location_code', normalized);
    _locationCode = normalized;
  }

  static String _normalizeLocationCode(String code) {
    return SalesDatabase.normalizeLocationCode(code);
  }

  static Future<void> clearLocation() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.remove('location_code');
    _locationCode = null;
  }
}
