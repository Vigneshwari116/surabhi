import 'package:intl/intl.dart';

/// Shared two-decimal amount formatting for bills, ledger, and summaries.
String formatMoneyAmount(double value) {
  return NumberFormat('#,##0.00').format(value);
}
