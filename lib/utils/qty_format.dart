/// Formats piece counts: whole numbers without ".0", up to two decimals when fractional.
String formatPcs(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  final fixed = value.toStringAsFixed(2);
  if (fixed.endsWith('0')) {
    return fixed.substring(0, fixed.length - 1);
  }
  return fixed;
}
