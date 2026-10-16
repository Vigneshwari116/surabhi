import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:surabhi/api/sales_api.dart';
import 'package:surabhi/repositories/ledger_repository.dart';
import 'package:surabhi/utils/ledger_group_display.dart';
import 'package:surabhi/utils/qty_format.dart';

class LedgerPdfService {
  static Future<String> saveLedgerPdf({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final bytes = await _buildPdfBytes(
      location: location,
      entries: entries,
      summary: summary,
      fromDate: fromDate,
      toDate: toDate,
    );

    final saveDir = await _saveDirectory();
    final fromPart = DateFormat('dd-MM-yyyy').format(fromDate);
    final toPart = DateFormat('dd-MM-yyyy').format(toDate);
    final rangePart = fromPart == toPart ? fromPart : '${fromPart}_to_$toPart';
    final fileName = 'Ledger_${location}_$rangePart.pdf';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> shareLedgerPdf({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final bytes = await _buildPdfBytes(
      location: location,
      entries: entries,
      summary: summary,
      fromDate: fromDate,
      toDate: toDate,
    );

    final fromPart = DateFormat('dd-MM-yyyy').format(fromDate);
    final toPart = DateFormat('dd-MM-yyyy').format(toDate);
    final rangePart = fromPart == toPart ? fromPart : '${fromPart}_to_$toPart';

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Ledger_${location}_$rangePart.pdf',
    );
  }

  static Future<Uint8List> _buildPdfBytes({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final doc = pw.Document();
    final headerStyle = pw.TextStyle(
      font: pw.Font.helveticaBold(),
      fontSize: 11,
      color: PdfColors.black,
    );
    final cellStyle = pw.TextStyle(
      font: pw.Font.helvetica(),
      fontSize: 8,
      color: PdfColors.black,
    );
    final money = NumberFormat('#,##0.00');

    final fromPart = DateFormat('dd-MMM-yy').format(fromDate);
    final toPart = DateFormat('dd-MMM-yy').format(toDate);
    final rangeLabel =
        fromPart == toPart ? fromPart : '$fromPart — $toPart';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text('SALES LEDGER — $location', style: headerStyle),
          pw.SizedBox(height: 4),
          pw.Text('Period: $rangeLabel', style: cellStyle),
          pw.SizedBox(height: 12),
          _ledgerTable(
            entries: entries,
            summary: summary,
            money: money,
            headerStyle: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 8,
            ),
            cellStyle: cellStyle,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static const double _groupColumnWidthPt = 118;

  static pw.Widget _ledgerTable({
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required NumberFormat money,
    required pw.TextStyle headerStyle,
    required pw.TextStyle cellStyle,
  }) {
    const headers = [
      'BILLNO',
      'DATE',
      'NAME',
      'GROUP',
      'MOBILE',
      'PCS',
      'CASH',
      'CARD/UPI',
      'TOTAL',
      'GST',
      'GRAND\nTOTAL',
    ];

    pw.Widget headerCell(String label) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        alignment: pw.Alignment.centerLeft,
        color: PdfColors.grey300,
        child: pw.Text(label, style: headerStyle),
      );
    }

    pw.Widget bodyCell(
      String text, {
      pw.Alignment alignment = pw.Alignment.centerLeft,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        alignment: alignment,
        child: pw.Text(text, style: cellStyle),
      );
    }

    pw.Widget groupCell(String groupSummary) {
      final display = LedgerGroupDisplay.formatForDisplay(groupSummary);
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(display, style: cellStyle),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: headers.map(headerCell).toList(growable: false),
      ),
      for (final entry in entries)
        pw.TableRow(
          children: [
            bodyCell('${entry.billNo}'),
            bodyCell(_formatDate(entry.date)),
            bodyCell(entry.customerName),
            groupCell(entry.groupSummary),
            bodyCell(entry.mobile.isEmpty ? '—' : entry.mobile),
            bodyCell(formatPcs(entry.pcs), alignment: pw.Alignment.centerRight),
            bodyCell(_cashColumnAmount(entry), alignment: pw.Alignment.centerRight),
            bodyCell(_cardColumnAmount(entry), alignment: pw.Alignment.centerRight),
            bodyCell(money.format(entry.total), alignment: pw.Alignment.centerRight),
            bodyCell(
              money.format(entry.cgst + entry.sgst + entry.igst),
              alignment: pw.Alignment.centerRight,
            ),
            bodyCell(
              money.format(entry.grandTotal),
              alignment: pw.Alignment.centerRight,
            ),
          ],
        ),
      pw.TableRow(
        children: [
          bodyCell(''),
          bodyCell(''),
          bodyCell(''),
          bodyCell(''),
          bodyCell(''),
          bodyCell(formatPcs(summary.totalPcs), alignment: pw.Alignment.centerRight),
          bodyCell(money.format(_cashTotal(entries)), alignment: pw.Alignment.centerRight),
          bodyCell(money.format(_cardTotal(entries)), alignment: pw.Alignment.centerRight),
          bodyCell(money.format(summary.total), alignment: pw.Alignment.centerRight),
          bodyCell(
            money.format(summary.cgst + summary.sgst + summary.igst),
            alignment: pw.Alignment.centerRight,
          ),
          bodyCell(money.format(summary.grandTotal), alignment: pw.Alignment.centerRight),
        ],
      ),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        3: const pw.FixedColumnWidth(_groupColumnWidthPt),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  static String _formatDate(String value) {
    try {
      return DateFormat('dd-MMM-yy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  static String formatPayMode(String mode) {
    final upper = mode.toUpperCase();
    if (upper == 'CASH') {
      return 'CASH';
    }
    return 'CARD/UPI';
  }

  static bool _isCashPayment(String mode) => mode.toUpperCase() == 'CASH';

  static String _cashColumnAmount(LocalLedgerEntry entry) {
    if (!_isCashPayment(entry.paymentMode)) {
      return '';
    }
    return NumberFormat('#,##0.00').format(entry.grandTotal);
  }

  static String _cardColumnAmount(LocalLedgerEntry entry) {
    if (_isCashPayment(entry.paymentMode)) {
      return '';
    }
    return NumberFormat('#,##0.00').format(entry.grandTotal);
  }

  static double _cashTotal(List<LocalLedgerEntry> entries) {
    return entries
        .where((entry) => _isCashPayment(entry.paymentMode))
        .fold(0.0, (sum, entry) => sum + entry.grandTotal);
  }

  static double _cardTotal(List<LocalLedgerEntry> entries) {
    return entries
        .where((entry) => !_isCashPayment(entry.paymentMode))
        .fold(0.0, (sum, entry) => sum + entry.grandTotal);
  }

  static Future<String> _saveDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}