import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:surabhi/utils/thermal_printer_filter.dart';

void main() {
  test('isVirtualPrinterName matches PDF and related keywords', () {
    expect(
      ThermalPrinterFilter.isVirtualPrinterName('Microsoft Print to PDF'),
      isTrue,
    );
    expect(
      ThermalPrinterFilter.isVirtualPrinterName('Microsoft XPS Document Writer'),
      isTrue,
    );
    expect(ThermalPrinterFilter.isVirtualPrinterName('Fax'), isTrue);
    expect(ThermalPrinterFilter.isVirtualPrinterName('RP3200'), isFalse);
  });

  test('physicalPrinters omits virtual devices', () {
    final printers = [
      Printer(name: 'RP3200', url: '', isDefault: false),
      Printer(name: 'Microsoft Print to PDF', url: '', isDefault: true),
    ];

    final physical = ThermalPrinterFilter.physicalPrinters(printers);
    expect(physical.length, 1);
    expect(physical.first.name, 'RP3200');
  });
}
