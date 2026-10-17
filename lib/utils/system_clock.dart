import 'package:flutter/foundation.dart';

/// Injectable wall clock for production code and tests.
class SystemClock {
  static DateTime Function() now = DateTime.now;

  @visibleForTesting
  static void reset() {
    now = DateTime.now;
  }
}

bool isSameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
