import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:surabhi/services/printer_settings_service.dart';
import 'package:surabhi/theme/app_theme.dart';
import 'package:surabhi/utils/thermal_printer_filter.dart';
import 'package:surabhi/widgets/compact_layout.dart';

/// Staff printer picker — physical printers only (no PDF / virtual).
class StaffThermalPrinterScreen extends StatefulWidget {
  const StaffThermalPrinterScreen({super.key});

  @override
  State<StaffThermalPrinterScreen> createState() =>
      _StaffThermalPrinterScreenState();
}

class _StaffThermalPrinterScreenState extends State<StaffThermalPrinterScreen> {
  bool _loading = true;
  String? _error;
  List<Printer> _printers = [];
  String? _selected;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _printerKey(Printer printer) {
    return printer.url.isNotEmpty ? printer.url : printer.name;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final all = await Printing.listPrinters();
      final physical = ThermalPrinterFilter.physicalPrinters(all);
      final saved =
          await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal);

      if (!mounted) return;

      setState(() {
        _printers = physical;
        _saved = saved;
        _selected = _matchSaved(saved, physical);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load printers: $e';
        _loading = false;
      });
    }
  }

  String? _matchSaved(String? saved, List<Printer> printers) {
    if (saved == null || saved.isEmpty) return null;
    for (final printer in printers) {
      final key = _printerKey(printer);
      if (key == saved || printer.name == saved) {
        return key;
      }
    }
    return saved;
  }

  Future<void> _selectPrinter(String key) async {
    setState(() => _selected = key);
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.thermal,
      key,
    );
    if (!mounted) return;
    setState(() => _saved = key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printer saved: $key')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'PRINTER',
        actions: [
          IconButton(
            tooltip: 'Refresh printer list',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saved != null && _saved!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardWhite,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Saved printer: $_saved',
                        style: const TextStyle(
                          fontSize: AppTextSizes.listTitle,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Choose the thermal printer for bills. Virtual printers '
                    '(PDF, XPS, Fax) are hidden.',
                    style: TextStyle(fontSize: AppTextSizes.listSubtitle),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _printers.isEmpty
                        ? const Center(
                            child: Text(
                              'No physical printers detected on this system.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _printers.length,
                            itemBuilder: (context, index) {
                              final printer = _printers[index];
                              final key = _printerKey(printer);
                              return RadioListTile<String>(
                                title: Text(printer.name),
                                subtitle: printer.url.isNotEmpty
                                    ? Text(
                                        printer.url,
                                        style: const TextStyle(
                                          fontSize: AppTextSizes.listSubtitle,
                                        ),
                                      )
                                    : null,
                                value: key,
                                groupValue: _selected,
                                onChanged: (value) {
                                  if (value == null) return;
                                  _selectPrinter(value);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
