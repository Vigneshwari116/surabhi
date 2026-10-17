class SaveBillResult {
  final bool ok;
  final int? billNo;
  final String? error;

  const SaveBillResult._({
    required this.ok,
    this.billNo,
    this.error,
  });

  factory SaveBillResult.success(int billNo) =>
      SaveBillResult._(ok: true, billNo: billNo);

  factory SaveBillResult.failure(String message) =>
      SaveBillResult._(ok: false, error: message);

  /// Saved bill number when [ok]; mirrors legacy `data` field name in callers.
  int? get data => billNo;
}

/// Written to `bills.sync_status` for new saves in local-only mode.
const String kLocalBillSyncStatus = 'local';
