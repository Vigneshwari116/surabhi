/// Thermal receipt / PDF layout constants in one place.
class ReceiptLayout {
  /// Printable roll width (mm).
  static const double pageWidthMm = 66.0;

  static const double marginLeftMm = 2.0;
  static const double marginRightMm = 6.0;

  static const double contentWidthMm =
      pageWidthMm - marginLeftMm - marginRightMm;

  /// Monospace text receipt (ESC/POS) — 48 columns with 8-char side margins.
  static const int paperColumns = 48;
  static const int textContentColumns = 32;
  static const int textMarginColumns =
      (paperColumns - textContentColumns) ~/ 2;

  /// Item table: SNO 2 | GROUP 8 | RATE 5 | QTY 3 | AMOUNT 7 with 1-col gaps.
  static const int columnCount = 29;
  static const int columnGap = 1;
  static const int snoWidth = 2;
  static const int groupWidth = 8;
  static const int rateWidth = 5;
  static const int qtyWidth = 3;
  static const int amountWidth = 7;

  /// Courier Bold character width ≈ 0.6 × font size (pt).
  static const double courierBoldCharWidthFactor = 0.6;

  static const double _mmPerPoint = 25.4 / 72.0;

  /// Body font size (pt) so [columnCount] monospace columns fit [contentWidthMm].
  static double bodyFontSizePt({double safetyMarginPt = 0.2}) {
    final maxSize = contentWidthMm /
        (columnCount * courierBoldCharWidthFactor * _mmPerPoint);
    final rounded = (maxSize - safetyMarginPt).floorToDouble();
    if (rounded < 6) {
      return 6;
    }
    return rounded;
  }
}
