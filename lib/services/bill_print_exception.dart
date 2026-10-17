class BillPrintException implements Exception {
  final String message;

  const BillPrintException(this.message);

  @override
  String toString() => message;
}
