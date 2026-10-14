import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/repositories/daily_total_repository.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    SalesApi.resetClientOverride();
  });

  test('fetchLiveTotals maps server codes to display names', () async {
    SalesApi.clientOverride = MockClient((request) async {
      expect(request.url.path, '/api/daily-totals');
      return http.Response(
        jsonEncode({
          'ok': true,
          'date': '2026-09-08',
          'totals': {'main': 100, 'main': 200, 'main': 50},
        }),
        200,
      );
    });

    final totals = await DailyTotalRepository.fetchLiveTotals(
      date: DateTime(2026, 9, 8),
    );

    expect(totals, isNotNull);
    expect(totals![displayNameForLocationCode('main')], 100);
    expect(totals![displayNameForLocationCode('main')], 200);
    expect(totals![displayNameForLocationCode('main')], 50);
  });

  test('fetchLiveTotals returns null when server is unreachable', () async {
    SalesApi.clientOverride = MockClient((request) async {
      throw http.ClientException('offline');
    });

    final totals = await DailyTotalRepository.fetchLiveTotals();
    expect(totals, isNull);
  });
}
