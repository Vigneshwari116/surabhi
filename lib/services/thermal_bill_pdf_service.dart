import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/services/receipt_service.dart';

/// 78mm thermal roll PDF — same engine as [Vigneshwari116/bar-and-rest-correct-]
/// (`print_service.dart`: Consolas, dashed rules, `directPrintPdf` to hardware).
class ThermalBillPdfService {
  static const double rollWidthMm = 78.0;

  static const String _addressLine =
      'T.10,3RD FLOOR,LN COMPLEX,OLD THARGUPET,Bangalore';

  static Future<pw.Font> loadReceiptFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/consolas.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Consolas load failed, using Courier: $e');
      return pw.Font.courier();
    }
  }

  static Future<Uint8List> buildPdfBytes(SaleBill bill) async {
    final result = await buildPdfWithFormat(bill);
    return result.bytes;
  }

  static Future<({Uint8List bytes, PdfPageFormat format})> buildPdfWithFormat(
    SaleBill bill,
  ) async {
    final font = await loadReceiptFont();
    final doc = pw.Document();
    final dateText = DateFormat('dd/MM/yyyy').format(bill.billDate);
    final timeText = DateFormat('HH:mm').format(bill.billDate);
    final itemCount = bill.items.length;
    var heightMm = 118.0 + (itemCount * 18.0);
    if (bill.customerName.trim().isNotEmpty || bill.mobile.trim().isNotEmpty) {
      heightMm += 14.0;
    }

    final pageFormat = PdfPageFormat(
      rollWidthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginLeft: 1.5 * PdfPageFormat.mm,
      marginRight: 6.0 * PdfPageFormat.mm,
      marginTop: 2.5 * PdfPageFormat.mm,
      marginBottom: 5.0 * PdfPageFormat.mm,
    );

    pw.TextStyle text(double size, {bool bold = false}) => pw.TextStyle(
          fontSize: size,
          font: font,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('BILL NO : ${bill.billNo}', style: text(10.5)),
                  pw.Text('DATE : $dateText', style: text(10.5)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  ReceiptService.businessName,
                  style: text(12.0),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  _addressLine,
                  style: text(9.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('GSTIN: ${ReceiptService.gstin}', style: text(9.0)),
                  pw.Text('$dateText $timeText', style: text(9.0)),
                ],
              ),
              if (bill.customerName.trim().isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text('NAME: ${bill.customerName.trim()}', style: text(9.5)),
              ],
              if (bill.mobile.trim().isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text('MOBILE: ${bill.mobile.trim()}', style: text(9.5)),
              ],
              pw.SizedBox(height: 3),
              _dashedDivider(),
              _tableHeader(font),
              _dashedDivider(),
              pw.SizedBox(height: 1),
              ...bill.items.map((item) {
                return [
                  _itemRow(item, font),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 1, bottom: 2),
                    child: pw.Text(
                      'CGST% ${_pct(item.cgstPct)}  SGST% ${_pct(item.sgstPct)}',
                      style: text(8.5),
                    ),
                  ),
                ];
              }).expand((rows) => rows),
              _dashedDivider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL', style: text(10.5, bold: true)),
                  pw.Text(
                    '${_qty(bill.totalQty)}  ${bill.totalAmount.toStringAsFixed(2)}',
                    style: text(10.5, bold: true),
                    textAlign: pw.TextAlign.right,
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CGST', style: text(10.0)),
                  pw.Text(
                    bill.totalCgst.toStringAsFixed(2),
                    style: text(10.0),
                    textAlign: pw.TextAlign.right,
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SGST', style: text(10.0)),
                  pw.Text(
                    bill.totalSgst.toStringAsFixed(2),
                    style: text(10.0),
                    textAlign: pw.TextAlign.right,
                  ),
                ],
              ),
              _dashedDivider(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('GRAND TOTAL', style: text(12.0, bold: true)),
                    pw.Text(
                      bill.grandTotal.toStringAsFixed(2),
                      style: text(14.0, bold: true),
                      textAlign: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 2),
              _dashedDivider(),
              pw.Text(
                'INCLUDING ALL TAXES: ${_pct(bill.items.isNotEmpty ? bill.items.first.cgstPct : 2.5)}% CGST, '
                '${_pct(bill.items.isNotEmpty ? bill.items.first.sgstPct : 2.5)}% SGST',
                style: text(8.0),
              ),
              _dashedDivider(),
              pw.SizedBox(height: 3),
              pw.Text('TERMS AND CONDITION', style: text(9.0)),
              pw.Text('AMOUNT NOT REFUND', style: text(9.0)),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'THANK YOU VISIT AGAIN',
                  style: text(10.5),
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    return (bytes: bytes, format: pageFormat);
  }

  static pw.Widget _dashedDivider() => pw.Divider(
        thickness: 0.8,
        borderStyle: pw.BorderStyle.dashed,
      );

  static pw.Widget _tableHeader(pw.Font font) {
    pw.TextStyle label(double size) => pw.TextStyle(fontSize: size, font: font);
    return pw.Row(
      children: [
        pw.Expanded(
          flex: 34,
          child: pw.Text('GROUP', style: label(10.0)),
        ),
        pw.Expanded(
          flex: 16,
          child: pw.Text('RATE', textAlign: pw.TextAlign.right, style: label(10.0)),
        ),
        pw.Expanded(
          flex: 14,
          child: pw.Text('QTY', textAlign: pw.TextAlign.right, style: label(10.0)),
        ),
        pw.Expanded(
          flex: 36,
          child: pw.Text('AMOUNT', textAlign: pw.TextAlign.right, style: label(10.0)),
        ),
      ],
    );
  }

  static pw.Widget _itemRow(BillItem item, pw.Font font) {
    final name = item.particular.trim().isEmpty ? 'ITEM' : item.particular.trim();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 34,
            child: pw.Text(
              name.toUpperCase(),
              maxLines: 2,
              style: pw.TextStyle(fontSize: 10.5, font: font, letterSpacing: -0.3),
            ),
          ),
          pw.Expanded(
            flex: 16,
            child: pw.Text(
              _rate(item.rate),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10.0, font: font),
            ),
          ),
          pw.Expanded(
            flex: 14,
            child: pw.Text(
              _qty(item.qty),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10.0, font: font),
            ),
          ),
          pw.Expanded(
            flex: 36,
            child: pw.Text(
              item.grossAmt.toStringAsFixed(2),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10.0, font: font),
            ),
          ),
        ],
      ),
    );
  }

  static String _qty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _rate(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String _pct(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
