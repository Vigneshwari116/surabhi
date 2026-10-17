import 'package:surabhi/utils/bill_gst_totals.dart';

class BillItem {
  final String particular;
  final double qty;
  final double rate;

  final double cgstPct;
  final double sgstPct;
  final double igstPct;

  BillItem({
    this.particular = '',
    required this.qty,
    required this.rate,
    this.cgstPct = 2.5,
    this.sgstPct = 2.5,
    this.igstPct = 0,
  });

  double get totalTaxPct {
    return cgstPct + sgstPct + igstPct;
  }

  double get grossAmt {
    return qty * rate;
  }

  BillGstTotals get _lineGst => gstTotalsForItem(this);

  double get amount => _lineGst.totalAmount;

  double get taxableAmt => amount;

  double get totalTax => grossAmt - amount;

  double get cgst => _lineGst.totalCgst;

  double get sgst => _lineGst.totalSgst;

  double get igst => _lineGst.totalIgst;

  double get netAmt {
    return grossAmt;
  }

  BillItem copyWith({
    String? particular,
    double? qty,
    double? rate,
    double? cgstPct,
    double? sgstPct,
    double? igstPct,
  }) {
    return BillItem(
      particular: particular ?? this.particular,
      qty: qty ?? this.qty,
      rate: rate ?? this.rate,
      cgstPct: cgstPct ?? this.cgstPct,
      sgstPct: sgstPct ?? this.sgstPct,
      igstPct: igstPct ?? this.igstPct,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'particular': particular,
      'qty': qty,
      'rate': rate,
      'cgstPct': cgstPct,
      'sgstPct': sgstPct,
      'igstPct': igstPct,
    };
  }

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      particular: json['particular'] as String? ?? '',
      qty: (json['qty'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
      cgstPct: (json['cgstPct'] as num?)?.toDouble() ?? 2.5,
      sgstPct: (json['sgstPct'] as num?)?.toDouble() ?? 2.5,
      igstPct: (json['igstPct'] as num?)?.toDouble() ?? 0,
    );
  }
}
