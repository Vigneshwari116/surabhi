import 'package:printing/printing.dart';

/// Filters Windows virtual printers out of bill printing.
class ThermalPrinterFilter {
  static const List<String> _virtualKeywords = [
    'microsoft print to pdf',
    'microsoft xps document writer',
    'onenote',
    'fax',
    'pdf',
    'xps',
    'send to',
    'save',
  ];

  static bool isVirtualPrinterName(String name) {
    final lower = name.toLowerCase();
    for (final keyword in _virtualKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static bool isVirtualPrinter(Printer printer) {
    if (isVirtualPrinterName(printer.name)) {
      return true;
    }
    if (printer.url.isNotEmpty && isVirtualPrinterName(printer.url)) {
      return true;
    }
    return false;
  }

  static List<Printer> physicalPrinters(List<Printer> printers) {
    return printers
        .where((printer) => !isVirtualPrinter(printer))
        .toList(growable: false);
  }
}
