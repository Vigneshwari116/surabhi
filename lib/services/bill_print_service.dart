import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/services/esc_pos_receipt_service.dart';
import 'package:surabhi/services/printer_settings_service.dart';
import 'package:surabhi/services/receipt_service.dart';
import 'package:surabhi/services/thermal_raw_printer.dart';

class BillPrintService {
  /// TVS RP3200: 80mm roll; 70mm content area keeps left/right data visible.
  static const double thermalPageWidthMm = 80.0;
  static const double thermalPrintableWidthMm = 70.0;
  static const double _thermalMarginMm =
      (thermalPageWidthMm - thermalPrintableWidthMm) / 2;

  /// RP3200 Font A (12×24 dots): 48 columns, 1.50×3.00mm per character.
  static const double thermalFontSizePt = 8.0;
  static const double thermalCharWidthMm = 1.50;
  static const double thermalLineSpacingMm = 4.25;

  static Future<String> saveReceiptToDesktop(SaleBill bill) async {
    final text = ReceiptService.buildReceiptText(bill);
    final saveDir = await _receiptSaveDirectory();
    final datePart = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final fileName = 'Bill_${bill.billNo}_$datePart.txt';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsString(text);
    return file.path;
  }

  /// Saves a normal A4 PDF that opens correctly in Desktop viewers.
  static Future<String> saveReceiptPdfToDesktop(SaleBill bill) async {
    final bytes = await buildDesktopPdfBytes(bill);
    final saveDir = await _receiptSaveDirectory();
    final datePart = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final fileName = 'Bill_${bill.billNo}_$datePart.pdf';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<bool> printReceipt(
    SaleBill bill, {
    required String printerName,
    PrinterType type = PrinterType.thermal,
  }) async {
    if (type == PrinterType.fast) {
      throw UnsupportedError(
        'Fast printer routing is not configured yet. '
        'Persist a fast printer in settings, but assign its print flow '
        'before calling printReceipt with PrinterType.fast.',
      );
    }

    final printers = await Printing.listPrinters();
    Printer? printer;

    for (final candidate in printers) {
      if (candidate.name == printerName || candidate.url == printerName) {
        printer = candidate;
        break;
      }
    }

    if (printer == null) {
      throw Exception('Printer "$printerName" not found');
    }

    if (type == PrinterType.thermal &&
        !kIsWeb &&
        Platform.isWindows &&
        _usesRawEscPos(printerName)) {
      final escPosBytes = EscPosReceiptService.buildReceiptBytes(bill);
      return printRawEscPos(
        printerName: printerName,
        data: escPosBytes,
      );
    }

    final pdfBytes = await buildDesktopPdfBytes(bill);
    final printed = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => pdfBytes,
      name: 'Bill_${bill.billNo}',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
      usePrinterSettings: false,
    );

    return printed;
  }

  /// PDF for Desktop / Print to PDF — avoids blank pages from thermal FittedBox layout.
  @visibleForTesting
  static Future<Uint8List> buildDesktopPdfBytes(SaleBill bill) async {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    final lines = text.split('\n');
    final doc = pw.Document();
    const fontSize = 11.0;
    final style = pw.TextStyle(
      font: pw.Font.courier(),
      fontSize: fontSize,
      color: PdfColors.black,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: _pdfReceiptLine(line, style),
                ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  @visibleForTesting
  static Future<Uint8List> buildPdfBytes(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) {
    return buildDesktopPdfBytes(bill);
  }

  @visibleForTesting
  static PdfPageFormat pageFormatForBill(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) {
    return PdfPageFormat.a4;
  }

  static bool _usesRawEscPos(String printerName) {
    return !_isVirtualDocumentPrinter(printerName);
  }

  static bool _isVirtualDocumentPrinter(String printerName) {
    final lower = printerName.toLowerCase();
    return lower.contains('pdf') ||
        lower.contains('xps') ||
        lower.contains('onenote') ||
        lower.contains('fax');
  }

  static String _displayLine(String line) {
    final trimmed = line.trim();
    return trimmed.isEmpty ? ' ' : trimmed;
  }

  /// Preserves thermal receipt alignment (centered shop name, thank-you line).
  static pw.Widget _pdfReceiptLine(String line, pw.TextStyle style) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return pw.SizedBox(height: style.fontSize);
    }
    if (_isCenteredReceiptLine(line, trimmed)) {
      return pw.Center(
        child: pw.Text(trimmed, style: style, textAlign: pw.TextAlign.center),
      );
    }
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(_displayLine(line), style: style),
    );
  }

  static bool _isCenteredReceiptLine(String raw, String trimmed) {
    if (trimmed == ReceiptService.businessName) {
      return true;
    }
    if (trimmed.startsWith('GSTIN:')) {
      return true;
    }
    if (trimmed.contains('THANK YOU VISIT AGAIN')) {
      return true;
    }
    final leading = raw.length - raw.trimLeft().length;
    final trailing = raw.length - raw.trimRight().length;
    return leading >= 6 && trailing >= 6;
  }

  static String _normalizedReceiptText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll('\r', ''))
        .join('\n')
        .trimRight();
  }

  static Future<String> _receiptSaveDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads.path;
      }
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    }

    if (!kIsWeb && Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final desktop = '$home/Desktop';
        if (Directory(desktop).existsSync()) {
          return desktop;
        }
      }
    }

    if (!kIsWeb && Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Desktop';
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}
