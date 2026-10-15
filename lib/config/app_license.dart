/// Application license window — app stops after the validity period.
class AppLicense {
  /// License period starts on this date (inclusive).
  static final DateTime validFrom = DateTime(2026, 10, 15);

  /// Number of days the app may run from [validFrom].
  static const int validityDays = 60;

  /// First instant when the app is no longer allowed to run.
  static final DateTime validUntil =
      validFrom.add(const Duration(days: validityDays));

  static bool get isValid {
    final now = DateTime.now();
    return !now.isBefore(validFrom) && now.isBefore(validUntil);
  }

  static String get expiryMessage {
    final expiryDay = validUntil.subtract(const Duration(days: 1));
    final day = expiryDay.day.toString().padLeft(2, '0');
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[expiryDay.month - 1];
    return 'This app license expired on $day-$month-${expiryDay.year}. '
        'Please contact support.';
  }
}
