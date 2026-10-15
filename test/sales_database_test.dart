import 'package:flutter_test/flutter_test.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/config/sales_database.dart';

void main() {
  test('active sales database filename is main_sales.db', () {
    expect(SalesDatabase.salesDbFileName, 'main_sales.db');
    expect(SalesDatabase.summaryDbFileName, 'sales_summary.db');
    expect(SalesDatabase.activeLocationCode, activeSalesLocationCode);
  });

  test('normalizeLocationCode maps legacy win codes to main', () {
    expect(SalesDatabase.normalizeLocationCode('win1'), 'main');
    expect(SalesDatabase.normalizeLocationCode('WIN2'), 'main');
    expect(SalesDatabase.normalizeLocationCode('Surabhi'), 'main');
    expect(SalesDatabase.normalizeLocationCode('main'), 'main');
  });

  test('isLegacySalesDbFileName flags old per-window files only', () {
    expect(SalesDatabase.isLegacySalesDbFileName('main_sales.db'), isFalse);
    expect(SalesDatabase.isLegacySalesDbFileName('win1_sales.db'), isTrue);
    expect(SalesDatabase.isLegacySalesDbFileName('win3_sales.db'), isTrue);
    expect(SalesDatabase.isLegacySalesDbFileName('sales_summary.db'), isFalse);
  });
}
