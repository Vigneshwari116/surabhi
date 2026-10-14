
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/local_credentials.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/repositories/bill_repository.dart';
import 'package:surabhi/services/app_session_service.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/services/session_service.dart';

import 'bill_item.dart';
import 'package:surabhi/screen/number%20to%20words.dart';
import 'login_screen.dart';
import 'sales_ledger_screen.dart';
import 'package:surabhi/services/printer_settings_service.dart';
import 'package:surabhi/services/gst_config_service.dart';
import 'package:surabhi/services/sync_service.dart';
import 'package:surabhi/theme/app_theme.dart';
import 'package:surabhi/utils/money_format.dart';
import 'package:surabhi/widgets/compact_layout.dart';

class SalesBillScreen extends StatefulWidget {
  /// When true, navigation is provided by [StaffDashboardScreen].
  final bool embeddedInDashboard;

  /// When set (tests only), replaces the default [SalesLedgerScreen] route.
  @visibleForTesting
  final Widget Function(String location)? ledgerScreenBuilder;

  /// When set (tests only), skips async local DB bill-number load on open.
  @visibleForTesting
  final int? initialBillNo;

  /// When set (tests only), replaces the default save/print handler for 777.
  @visibleForTesting
  final Future<void> Function()? saveBillOverride;

  /// When false, bill tab is hidden inside [IndexedStack] — restore focus on return.
  final bool isSectionActive;

  const SalesBillScreen({
    super.key,
    this.embeddedInDashboard = false,
    this.isSectionActive = true,
    this.initialBillNo,
    this.ledgerScreenBuilder,
    this.saveBillOverride,
  });

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color billNoColor = Color(0xFF7FE8E8);
  static const double _entryBoxWidth = 92;
  static const double _entryBoxHeight = 44;
  static const double _entryLabelSize = 18.0;
  static const int _flexSno = 48;
  static const int _flexGroup = 100;
  static const int _flexRate = 72;
  static const int _flexQty = 56;
  static const int _flexAmount = 88;
  static const int _flexLineTotal = 100;
  static const int _flexCgst = 80;
  static const int _flexSgst = 80;
  static const int _flexIgst = 72;
  static const double _tableRowHeight = 40;
  static const double _tableHeaderFontSize = 15;
  static const double _tableCellFontSize = 15;
  static const double _deleteColWidth = 34;
  static const double _desktopBreakpoint = 900;
  static const double _sidebarBreakpoint = 700;
  static const double _sidebarWidth = 200;

  bool _sidebarOpen = false;

  // ============================================================
  // LOCATION (from login — not shown on screen)
  // ============================================================

  late String _selectedLocation;

  // Current bill number.
  int _billNo = 1;

  // Whether the bill has been saved/completed.
  bool _billSaved = false;

  bool _busy = false;
  bool _manualPushInProgress = false;
  String? _currentBillLocalId;
  String? _rateError;
  String? _qtyError;
  double _cgstPct = GstConfigService.defaultCgstPct;
  double _sgstPct = GstConfigService.defaultSgstPct;

  // ============================================================
  // BILL DATE
  // ============================================================

  DateTime _billDate = DateTime.now();

  // ============================================================
  // PAYMENT
  // ============================================================

  String _paymentMode = 'UPI';

  final List<String> _paymentModes = const [
    'UPI',
    'CASH',
    'CARD',
  ];

  List<String> _masterParticulars = [];
  String? _selectedParticular;
  String? _particularError;

  // ============================================================
  // CUSTOMER
  // ============================================================

  final TextEditingController _customerNameController =
  TextEditingController();

  final TextEditingController _mobileController =
  TextEditingController();

  // ============================================================
  // RATE / QTY
  // ============================================================

  final TextEditingController _rateController =
  TextEditingController(text: '0');

  final TextEditingController _qtyController =
  TextEditingController(text: '0');

  final TextEditingController _amountController =
  TextEditingController(text: '0');

  final FocusNode _rateFocus = FocusNode();

  final FocusNode _qtyFocus = FocusNode();

  final FocusNode _nameFocus = FocusNode();

  final FocusNode _mobileFocus = FocusNode();

  final FocusNode _groupFocus = FocusNode();

  String _lastFocusField = 'name';

  double _todayAmount = 0;
  double _todayGst = 0;
  double _todayGrandTotal = 0;
  bool _todaySalesPanelVisible = false;

  // ============================================================
  // AUTO FOCUS TIMERS — removed; field advance is Enter-only.
  // ============================================================

  // ============================================================
  // ITEMS
  // ============================================================

  final List<BillItem> _items = [];

  int? _selectedIndex;

  // Password-gated edit for line items in the excel table.
  bool _editUnlocked = false;
  bool _showPasswordField = false;
  String? _passwordError;
  final TextEditingController _passwordController = TextEditingController();
  int? _editingIndex;
  final TextEditingController _editRateController = TextEditingController();
  final TextEditingController _editQtyController = TextEditingController();

  // ============================================================
  // INIT
  // ============================================================

  @override
  void didUpdateWidget(covariant SalesBillScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSectionActive && !oldWidget.isSectionActive) {
      unawaited(_loadMasterParticulars());
    }
    if (widget.isSectionActive && !oldWidget.isSectionActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSavedFocus();
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _selectedLocation = AppConfig.displayLocationName;
    _rateController.text = '0';
    _qtyController.text = '0';

    _rateFocus.addListener(() => _onNumericFocus(_rateFocus, _rateController));
    _qtyFocus.addListener(() => _onNumericFocus(_qtyFocus, _qtyController));
    _nameFocus.addListener(() => _onFieldFocused('name'));
    _mobileFocus.addListener(() => _onFieldFocused('mobile'));
    _rateFocus.addListener(() {
      if (_rateFocus.hasFocus) _onFieldFocused('rate');
    });
    _qtyFocus.addListener(() {
      if (_qtyFocus.hasFocus) _onFieldFocused('qty');
    });

    _manualPushInProgress = SyncService.instance.manualPushInProgress.value;
    SyncService.instance.manualPushInProgress.addListener(_onManualPushChanged);

    _loadGstRates();
    unawaited(_loadMasterParticulars());

    if (widget.initialBillNo != null) {
      _billNo = widget.initialBillNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSavedFocus();
      });
    } else {
      _restoreSessionOrLoadBill().then((_) {
        if (mounted) {
          _restoreSavedFocus();
        }
      });
    }
  }

  void _onNumericFocus(FocusNode node, TextEditingController controller) {
    if (!node.hasFocus) return;
    final text = controller.text.trim();
    if (text == '0' || text == '0.0' || text == '0.00') {
      controller.clear();
    }
  }

  void _onFieldFocused(String field) {
    _lastFocusField = field;
    SessionService.saveFocusField(field);
  }

  Future<void> _restoreSavedFocus() async {
    final saved = await SessionService.loadFocusField();
    final field = saved ?? _lastFocusField;
    switch (field) {
      case 'mobile':
        _focusMobile();
      case 'rate':
        _focusRate();
      case 'qty':
        _focusQty();
      case 'name':
      default:
        _focusName();
    }
  }

  void _focusName() {
    if (!mounted) return;
    _nameFocus.requestFocus();
  }

  void _focusMobile() {
    if (!mounted) return;
    _mobileFocus.requestFocus();
  }

  void _onManualPushChanged() {
    if (!mounted) return;
    setState(() {
      _manualPushInProgress =
          SyncService.instance.manualPushInProgress.value;
    });
  }

  bool get _isEntryLocked => _busy || _manualPushInProgress;

  Future<void> _loadGstRates() async {
    final cgst = await GstConfigService.cgstPct();
    final sgst = await GstConfigService.sgstPct();
    if (!mounted) return;
    setState(() {
      _cgstPct = cgst;
      _sgstPct = sgst;
    });
  }

  Future<void> _syncNow() async {
    final result =
        await SyncService.instance.manualPush(_selectedLocation);

    if (!mounted) return;

    _showMessage(result.summaryMessage);
  }

  Future<void> _restoreSessionOrLoadBill() async {
    final session = await SessionService.loadBillSession();

    if (!mounted) return;

    if (session != null && session.location == _selectedLocation) {
      setState(() {
        _billNo = session.billNo;
        _billDate = session.billDate;
        _paymentMode = session.paymentMode == 'PHONE PEE'
            ? 'UPI'
            : session.paymentMode;
        var customerName = session.customerName;
        if (customerName == 'CASH' && session.paymentMode == 'CASH') {
          customerName = '';
        }
        _customerNameController.text = customerName;
        _mobileController.text = session.mobile;
        _items
          ..clear()
          ..addAll(session.items);
        _billSaved = session.billSaved;
        _selectedIndex = null;
        _currentBillLocalId = null;
      });
      return;
    }

    setState(() {
      _currentBillLocalId = null;
    });

    await _loadBillNumber();
    if (!mounted) return;
  }

  Future<void> _persistSession() async {
    await SessionService.saveBillSession(
      location: _selectedLocation,
      billNo: _billNo,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      billSaved: _billSaved,
    );
  }

  // ============================================================
  // LOAD BILL NUMBER (from this location's local DB only)
  // ============================================================

  Future<void> _loadBillNumber() async {
    var nextBillNo =
        await BillRepository.getNextBillNumber(_selectedLocation);

    if (!mounted) return;

    setState(() {
      _billNo = nextBillNo;
    });
  }

  Future<void> _populateFromSavedBill(SaleBill bill) async {
    String? localId;
    try {
      localId = await LocalDb.instance.findLocalIdByBillNo(
        location: bill.location,
        billNo: bill.billNo,
      );
    } catch (_) {
      // Best-effort lookup for edit/save tracking.
    }

    if (!mounted) return;

    setState(() {
      _billNo = bill.billNo;
      _billDate = bill.billDate;
      _paymentMode = bill.paymentMode;
      _customerNameController.text = bill.customerName;
      _mobileController.text = bill.mobile;
      _items
        ..clear()
        ..addAll(bill.items.map((item) => item.copyWith()));
      _selectedIndex = null;
      _editUnlocked = false;
      _showPasswordField = false;
      _passwordError = null;
      _editingIndex = null;
      _billSaved = true;
      _currentBillLocalId = localId;
      _rateController.text = '0';
      _qtyController.text = '0';
    });

    await _persistSession();
  }

  Future<void> _goToPreviousBill() async {
    if (_busy) return;

    final previous = await BillRepository.getPreviousBill(
      location: _selectedLocation,
      beforeBillNo: _billNo,
    );

    if (!mounted) return;

    if (previous == null) {
      _showMessage('No previous bill');
      return;
    }

    await _populateFromSavedBill(previous);
  }

  Future<void> _goToNextBill() async {
    if (_busy) return;

    final next = await BillRepository.getNextBill(
      location: _selectedLocation,
      afterBillNo: _billNo,
    );

    if (!mounted) return;

    if (next != null) {
      await _populateFromSavedBill(next);
      return;
    }

    final nextBillNo =
        await BillRepository.getNextBillNumber(_selectedLocation);
    if (!mounted) return;

    if (_billNo >= nextBillNo) {
      _showMessage('No next bill');
      return;
    }

    setState(() {
      _billNo = nextBillNo;
      _clearCurrentBill();
    });
    await _persistSession();
  }

  Widget _buildBillNavButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 29,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.actionButton,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 29),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  // ============================================================
  // FOCUS RATE
  // ============================================================

  void _focusRate() {
    if (!mounted) return;

    _rateFocus.requestFocus();

    _rateController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _rateController.text.length,
    );
  }

  // ============================================================
  // FOCUS QTY
  // ============================================================

  void _focusGroup() {
    if (!mounted) return;
    _groupFocus.requestFocus();
  }

  void _focusQty() {
    if (!mounted) return;

    _qtyFocus.requestFocus();

    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  // ============================================================
  // RATE CHANGED — updates live amount display only (no auto-advance).
  // ============================================================

  void _rateChanged(String value) {
    setState(() {
      if (_rateError != null) {
        _rateError = null;
      }
    });
  }

  void _qtyChanged(String value) {
    setState(() {
      if (_qtyError != null) {
        _qtyError = null;
      }
    });
  }

  void _clearEntryErrors() {
    _rateError = null;
    _qtyError = null;
    _particularError = null;
  }

  Future<void> _loadMasterParticulars() async {
    try {
      final names = await LocalDb.instance.listMasterItemNames();
      if (!mounted) return;
      setState(() {
        _masterParticulars = names;
        if (_selectedParticular != null &&
            !_masterParticulars.contains(_selectedParticular)) {
          _selectedParticular = null;
        }
      });
    } catch (_) {
      // Master list is optional until DB is ready.
    }
  }

  bool _validateParticular({bool focusOnError = true}) {
    final selected = _selectedParticular?.trim() ?? '';
    if (selected.isEmpty) {
      setState(() => _particularError = 'Select a group from MASTER');
      if (focusOnError) {
        _showMessage('Add items in MASTER menu, then select here');
      }
      return false;
    }
    setState(() => _particularError = null);
    return true;
  }

  bool _validateRate({bool focusOnError = true}) {
    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) {
      setState(() => _rateError = 'Rate must be greater than 0');
      if (focusOnError) _focusRate();
      return false;
    }
    setState(() => _rateError = null);
    return true;
  }

  bool _validateQty({bool focusOnError = true}) {
    final qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) {
      setState(() => _qtyError = 'Quantity must be greater than 0');
      if (focusOnError) _focusQty();
      return false;
    }
    setState(() => _qtyError = null);
    return true;
  }

  // ============================================================
  // RATE / QTY ENTER — 777 prints table bill; other rates go to qty
  // ============================================================

  static const String _printCode = '777';

  void _rateSubmitted() {
    final rateText = _rateController.text.trim();

    if (rateText == _printCode) {
      _rateController.text = '0';
      if (_items.isEmpty) {
        _showMessage('Add items before printing');
        return;
      }
      final save = widget.saveBillOverride ?? _saveBill;
      unawaited(save());
      return;
    }

    if (!_validateRate()) {
      return;
    }

    _focusQty();
  }

  void _qtySubmitted() {
    if (!_validateParticular() ||
        !_validateRate() ||
        !_validateQty()) {
      return;
    }

    _addItem();
  }

  void _addItem() {
    if (!_validateParticular() ||
        !_validateRate() ||
        !_validateQty()) {
      return;
    }

    final rate = double.parse(_rateController.text);
    final qty = double.parse(_qtyController.text);
    final particular = _selectedParticular!.trim();

    setState(() {
      _clearEntryErrors();
      _items.add(
        BillItem(
          particular: particular,
          qty: qty,
          rate: rate,
          cgstPct: _cgstPct,
          sgstPct: _sgstPct,
          igstPct: 0,
        ),
      );

      _selectedIndex = null;
      _billSaved = false;

      // Reset fields to ZERO
      _rateController.text = '0';
      _qtyController.text = '0';
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  void _onMobileDoubleTap() {
    if (_editUnlocked || _showPasswordField) {
      return;
    }

    setState(() {
      _showPasswordField = true;
      _passwordError = null;
      _passwordController.clear();
    });
  }

  void _tryUnlockEdit() {
    if (_passwordController.text == billEditPassword) {
      setState(() {
        _editUnlocked = true;
        _showPasswordField = false;
        _passwordError = null;
      });
      return;
    }

    setState(() => _passwordError = 'Incorrect password');
  }

  void _startEditLine(int index) {
    if (!_editUnlocked) {
      return;
    }

    setState(() {
      _editingIndex = index;
      _editRateController.text = _items[index].rate.toString();
      _editQtyController.text = _items[index].qty.toString();
    });
  }

  void _applyLineEdit() {
    final index = _editingIndex;
    if (index == null) {
      return;
    }

    final rate = double.tryParse(_editRateController.text.trim());
    final qty = double.tryParse(_editQtyController.text.trim());

    if (rate == null || rate <= 0 || qty == null || qty <= 0) {
      _showMessage('Enter valid rate and quantity');
      return;
    }

    setState(() {
      _items[index] = _items[index].copyWith(rate: rate, qty: qty);
      _editingIndex = null;
      _billSaved = false;
    });

    _persistSession();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);

      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }

      _billSaved = false;
    });

    _persistSession();
  }

  // ============================================================
  // CLEAR CURRENT BILL
  // ============================================================

  void _clearCurrentBill() {
    _billDate = DateTime.now();

    _paymentMode = 'UPI';
    _selectedParticular = null;

    _customerNameController.text = '';

    _mobileController.clear();

    _rateController.text = '0';

    _qtyController.text = '0';

    _items.clear();

    _selectedIndex = null;
    _editUnlocked = false;
    _showPasswordField = false;
    _passwordError = null;
    _editingIndex = null;

    _billSaved = false;
    _currentBillLocalId = null;
  }

  // ============================================================
  // SAVE BILL
  // ============================================================

  Future<void> _saveBill() async {
    if (_busy) return;

    if (_items.isEmpty) {
      _showMessage('Add at least one item before saving');
      return;
    }

    setState(() => _busy = true);

    try {
      final bill = _buildCurrentBill();
      final result = await BillRepository.saveBill(
        bill,
        updateLocalId: _currentBillLocalId,
      );

      if (!mounted) return;

      if (!result.ok) {
        _showMessage(result.error ?? 'Failed to save bill');
        return;
      }

      try {
        _currentBillLocalId = await LocalDb.instance.findLocalIdByBillNo(
              location: _selectedLocation,
              billNo: _billNo,
            ) ??
            _currentBillLocalId;
      } catch (_) {
        // Bill is saved; local id lookup is best-effort.
      }

      final int savedBillNo = _billNo;

      String? pdfPath;
      try {
        pdfPath = await BillPrintService.saveReceiptPdfToDesktop(bill);
      } catch (e) {
        pdfPath = null;
      }

      final defaultPrinter = await PrinterSettingsService.getDefaultPrinter(
        PrinterType.thermal,
      );

      if (defaultPrinter == null || defaultPrinter.isEmpty) {
        if (pdfPath != null) {
          _showMessage(
            'Bill $savedBillNo saved. PDF on Desktop: ${pdfPath.split(Platform.pathSeparator).last}',
          );
        } else {
          _showMessage(
            'No printer selected. Choose one in PRINTER, or check Desktop for PDF.',
          );
        }
      } else {
        try {
          await BillPrintService.printReceipt(
            bill,
            printerName: defaultPrinter,
            type: PrinterType.thermal,
          );
          if (pdfPath != null) {
            _showMessage(
              'Bill $savedBillNo saved, printed, and PDF saved to Desktop.',
            );
          } else {
            _showMessage('Bill $savedBillNo saved and printed');
          }
        } catch (e) {
          if (pdfPath != null) {
            _showMessage(
              'Bill $savedBillNo saved. PDF on Desktop (print failed: $e)',
            );
          } else {
            _showMessage('Bill $savedBillNo saved (print failed: $e)');
          }
        }
      }

      if (!mounted) return;

      await _loadBillNumber();

      if (!mounted) return;

      setState(() {
        _billSaved = true;
        _clearCurrentBill();
      });

      await _persistSession();
      if (_todaySalesPanelVisible) {
        unawaited(_refreshTodaySales());
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusRate();
      });
    } catch (e) {
      if (mounted) {
        _showMessage('Save failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openLedger() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.ledgerScreenBuilder?.call(_selectedLocation) ??
            SalesLedgerScreen(location: _selectedLocation),
      ),
    );
  }

  SaleBill _buildCurrentBill() {
    return SaleBill(
      billNo: _billNo,
      location: _selectedLocation,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      totalQty: _totalQty,
      totalAmount: _totalAmount,
      totalCgst: _totalCgst,
      totalSgst: _totalSgst,
      totalIgst: _totalIgst,
      grandTotal: _grandTotal,
    );
  }

  // ============================================================
  // EXIT
  // ============================================================

  void _exitScreen() async {
    await _persistSession();
    await AppSessionService.onLogout();
    await AppConfig.clearLocation();
    await SessionService.clearLogin();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ============================================================
  // TOTAL QTY
  // ============================================================

  double get _totalQty {
    return _items.fold(
      0,
          (sum, item) => sum + item.qty,
    );
  }

  // ============================================================
  // TOTAL TAXABLE AMOUNT
  // ============================================================

  double get _totalAmount {
    return _items.fold(
      0,
          (sum, item) => sum + item.amount,
    );
  }

  // ============================================================
  // TOTAL CGST
  // ============================================================

  double get _totalCgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.cgst,
    );
  }

  // ============================================================
  // TOTAL SGST
  // ============================================================

  double get _totalSgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.sgst,
    );
  }

  // ============================================================
  // TOTAL IGST
  // ============================================================

  double get _totalIgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.igst,
    );
  }

  // ============================================================
  // GRAND TOTAL
  //
  // GST INCLUSIVE
  // ============================================================

  double get _grandTotal {
    return _items.fold(
      0,
          (sum, item) => sum + item.netAmt,
    );
  }

  // ============================================================
  // CURRENT AMOUNT
  // ============================================================

  double get _currentAmount {
    final double rate =
        double.tryParse(
          _rateController.text,
        ) ??
            0;

    final double qty =
        double.tryParse(
          _qtyController.text,
        ) ??
            0;

    return rate * qty;
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _formatAmount(double value) => formatMoneyAmount(value);

  String _formatQtyOrPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
        const Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    _updateAmountDisplay();

    final width = MediaQuery.sizeOf(context).width;
    final useSidebarLayout =
        !widget.embeddedInDashboard && width > _sidebarBreakpoint;
    final mobileBillLayout = width < _desktopBreakpoint;

    return _buildRootScaffold(
      context,
      useSidebarLayout: useSidebarLayout,
      mobileBillLayout: mobileBillLayout,
    );
  }

  Widget _buildRootScaffold(
    BuildContext context, {
    required bool useSidebarLayout,
    required bool mobileBillLayout,
  }) {
    final body = mobileBillLayout
        ? _buildMobileBody(context)
        : _buildDesktopBody();

    if (widget.embeddedInDashboard) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: sectionHeaderAppBar(
          'SALES BILL',
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildTodaySalesButton(compact: true),
            ),
          ],
        ),
        body: _buildLockedBody(body),
      );
    }

    if (useSidebarLayout) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(
          mobileBillLayout: mobileBillLayout,
          useSidebarLayout: true,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sidebarOpen) ...[
              SizedBox(
                width: _sidebarWidth,
                child: _buildMenuPanel(
                  onClose: () => setState(() => _sidebarOpen = false),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
            ],
            Expanded(child: _buildLockedBody(body)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        child: _buildMenuPanel(
          onClose: () => Navigator.pop(context),
        ),
      ),
      appBar: _buildAppBar(
        mobileBillLayout: mobileBillLayout,
        useSidebarLayout: false,
      ),
      body: _buildLockedBody(body),
    );
  }

  Widget _buildLockedBody(Widget child) {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isEntryLocked,
          child: child,
        ),
        if (_manualPushInProgress)
          Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Syncing bills to server...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar({
    required bool mobileBillLayout,
    required bool useSidebarLayout,
  }) {
    final todaySalesAction = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _buildTodaySalesButton(compact: true),
    );

    if (mobileBillLayout) {
      return sectionHeaderAppBar(
        'Sales Bill',
        automaticallyImplyLeading: !useSidebarLayout,
        leading: useSidebarLayout
            ? IconButton(
                icon: Icon(_sidebarOpen ? Icons.menu_open : Icons.menu),
                tooltip: _sidebarOpen ? 'Close menu' : 'Open menu',
                onPressed: () {
                  setState(() => _sidebarOpen = !_sidebarOpen);
                },
              )
            : null,
        actions: widget.embeddedInDashboard ? null : [todaySalesAction],
      );
    }

    return sectionHeaderAppBar(
      'SALES BILL',
      automaticallyImplyLeading: !useSidebarLayout,
      leading: useSidebarLayout
          ? IconButton(
              icon: Icon(_sidebarOpen ? Icons.menu_open : Icons.menu),
              tooltip: _sidebarOpen ? 'Close menu' : 'Open menu',
              onPressed: () {
                setState(() => _sidebarOpen = !_sidebarOpen);
              },
            )
          : null,
      actions: widget.embeddedInDashboard ? null : [todaySalesAction],
    );
  }

  Widget _buildDesktopBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTopArea(),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.topLeft,
            child: _buildItemTableSection(),
          ),
          const SizedBox(height: 8),
          _buildSaveSaleBar(),
          if (_todaySalesPanelVisible) ...[
            const SizedBox(height: 10),
            _buildTodaySalesSummary(),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshTodaySales() async {
    try {
      final today = DateTime.now();
      final summary = await AbstractRepository.getSummaryForDateRange(
        location: _selectedLocation,
        fromDate: today,
        toDate: today,
      );
      if (!mounted) return;
      setState(() {
        _todayAmount = summary.totalSaleAmount;
        _todayGst = summary.totalGst;
        _todayGrandTotal = summary.totalSaleAmount + summary.totalGst;
      });
    } catch (_) {
      // Keep previous totals on refresh failure.
    }
  }

  Future<void> _onTodaySalesPressed() async {
    setState(() => _todaySalesPanelVisible = true);
    await _refreshTodaySales();
  }

  Widget _buildTodaySalesButton({bool compact = false}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        key: const Key('today_sales_button'),
        onPressed: _busy ? null : _onTodaySalesPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.actionButton,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          textStyle: const TextStyle(
            fontSize: AppTextSizes.buttonText,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(compact ? 'TODAY SALES' : 'TODAY SALES'),
      ),
    );
  }

  Widget _buildTodaySalesSummary() {
    return CompactAbstractSummary(
      amountValue: _formatAmount(_todayAmount),
      gstValue: _formatAmount(_todayGst),
      grandTotalValue: _formatAmount(_todayGrandTotal),
      grandTotalLabel: 'Total sales',
      cardWidth: 130,
    );
  }

  Color _paymentFillColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'CASH':
        return Colors.black;
      case 'CARD':
        return AppColors.accentBlue;
      case 'UPI':
      default:
        return Colors.white;
    }
  }

  Color _paymentTextColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'CASH':
      case 'CARD':
        return Colors.white;
      case 'UPI':
      default:
        return Colors.black;
    }
  }

  Widget _buildSaveSaleBar() {
    return Row(
      children: [
        CompactSaveButton(
          buttonKey: const Key('save_sale_bar_button'),
          label: 'SAVE SALE',
          onPressed: _saveBill,
        ),
        if (_particularError != null) ...[
          const SizedBox(width: 12),
          Text(
            _particularError!,
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: AppTextSizes.listSubtitle,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBillDetails(mobile: true),
          const SizedBox(height: 6),
          _buildCustomerDetails(),
          const SizedBox(height: 6),
          _buildItemTableSection(mobile: true),
          const SizedBox(height: 8),
          _buildSaveSaleBar(),
          if (_todaySalesPanelVisible) ...[
            const SizedBox(height: 10),
            _buildTodaySalesSummary(),
          ],
        ],
      ),
    );
  }

  /// Staff POS menu — ledger + sync stay here for offline locations without
  /// an admin present. Abstract and printer settings are admin-dashboard only.
  Widget _buildMenuPanel({required VoidCallback onClose}) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book, size: 20),
              title: const Text('LEDGER'),
              onTap: () {
                onClose();
                _openLedger();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('SYNC NOW'),
              enabled: !_manualPushInProgress,
              onTap: _manualPushInProgress
                  ? null
                  : () {
                      onClose();
                      _syncNow();
                    },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('EXIT'),
              onTap: () {
                onClose();
                _exitScreen();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopArea() {
    // Do not use Expanded/Flexible here — this row lives inside a
    // SingleChildScrollView, which can pass unbounded width and blank the bill UI.
    return LayoutBuilder(
      builder: (context, constraints) {
        const billWidth = 300.0;
        const navWidth = 92.0;
        const gaps = 16.0;
        final customerWidth = (constraints.maxWidth - billWidth - navWidth - gaps)
            .clamp(160.0, constraints.maxWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: billWidth,
              child: _buildBillDetails(),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: customerWidth,
              child: _buildCustomerDetails(),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: navWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBillNavButton(
                    label: 'PREVIOUS',
                    onPressed: _goToPreviousBill,
                  ),
                  const SizedBox(height: 4),
                  _buildBillNavButton(
                    label: 'NEXT',
                    onPressed: _goToNextBill,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BILL DETAILS
  // ============================================================

  Widget _buildBillDetails({bool mobile = false}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.border,
        ),
      ),

      padding:
      const EdgeInsets.all(5),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,

        children: [
          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text(
                  'BILL NO:',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black,
                  ),
                ),
              ),

              // ==================================================
              // FIXED BILL NUMBER
              // ==================================================

              Container(
                width: 82,
                height: 29,

                alignment:
                Alignment.center,

                decoration:
                const BoxDecoration(
                  color: billNoColor,
                ),

                child: FittedBox(
                  fit: BoxFit.scaleDown,

                  child: Text(
                    '$_billNo',
                    style:
                    const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                child: SizedBox(
                  height: 29,

                  child:
                  DropdownButtonFormField<
                      String>(
                    value: _paymentMode,
                    isDense: true,
                    isExpanded: true,
                    alignment: AlignmentDirectional.centerStart,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _paymentFillColor(_paymentMode),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 0,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _paymentTextColor(_paymentMode),
                    ),
                    style: TextStyle(
                      fontSize: AppTextSizes.listSubtitle,
                      color: _paymentTextColor(_paymentMode),
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: Colors.white,
                    selectedItemBuilder: (context) {
                      return _paymentModes
                          .map(
                            (mode) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                mode,
                                style: TextStyle(
                                  fontSize: AppTextSizes.listSubtitle,
                                  color: _paymentTextColor(_paymentMode),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false);
                    },
                    items: _paymentModes.map((item) {
                      return DropdownMenuItem(
                        value: item,
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: AppTextSizes.listSubtitle,
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _paymentMode = value;
                      });
                      _onFieldFocused('name');
                      _focusName();
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text(
                  'BILL DATE:',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black,
                  ),
                ),
              ),

              InkWell(
                onTap: null,
                child: Container(
                  width: 108,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3F3),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${_billDate.day.toString().padLeft(2, '0')}/'
                        '${_billDate.month.toString().padLeft(2, '0')}/'
                        '${_billDate.year}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ============================================================
  // CUSTOMER DETAILS
  // ============================================================

  Widget _buildCustomerDetails() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Customer Details',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          _buildLabeledCustomerField(
            label: 'Name',
            child: _smallTextField(
              _customerNameController,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _focusMobile(),
            ),
          ),
          const SizedBox(height: 6),
          _buildLabeledCustomerField(
            label: 'MOBILE',
            child: GestureDetector(
              onDoubleTap: _onMobileDoubleTap,
              child: _smallTextField(
                _mobileController,
                number: true,
                fieldKey: const Key('bill_mobile_field'),
                focusNode: _mobileFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _focusGroup(),
              ),
            ),
          ),
          if (_showPasswordField && !_editUnlocked) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: Text(
                    'Password',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('bill_edit_password_field'),
                    controller: _passwordController,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => _tryUnlockEdit(),
                    style: const TextStyle(fontSize: 10),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    key: const Key('bill_edit_password_ok'),
                    onPressed: _tryUnlockEdit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('OK', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            if (_passwordError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _passwordError!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
          if (_editUnlocked)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Edit mode — tap a line to correct rate/qty.',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLabeledCustomerField({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 140,
          child: child,
        ),
      ],
    );
  }

  // ============================================================
  // SMALL TEXT FIELD
  // ============================================================

  Widget _smallTextField(
      TextEditingController controller, {
        bool number = false,
        Key? fieldKey,
        FocusNode? focusNode,
        TextInputAction? textInputAction,
        ValueChanged<String>? onSubmitted,
      }) {
    return TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,

        keyboardType: number
            ? TextInputType.phone
            : TextInputType.text,

        inputFormatters: number
            ? [
          FilteringTextInputFormatter
              .digitsOnly,
        ]
            : null,

        style: const TextStyle(
          fontSize: 10,
          color: Colors.black,
        ),

        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 5,
          ),
        ),
      );
  }

  // ============================================================
  // RATE / QTY / AMOUNT
  // ============================================================

  void _updateAmountDisplay() {
    final text = _formatAmount(_currentAmount);
    if (_amountController.text != text) {
      _amountController.text = text;
    }
  }

  InputDecoration _entryDecoration() {
    return const InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(),
      disabledBorder: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 11),
    );
  }

  Widget _buildStackedEntryField({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    bool readOnly = false,
    bool blockTabTraversal = false,
    TextInputAction? textInputAction,
    Key? fieldKey,
    double width = _entryBoxWidth,
  }) {
    Widget field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      showCursor: !readOnly,
      enableInteractiveSelection: !readOnly,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: readOnly
          ? null
          : [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      decoration: _entryDecoration(),
      style: const TextStyle(
        fontSize: AppTextSizes.fieldText,
        height: 1,
        color: Colors.black,
      ),
    );

    if (blockTabTraversal) {
      field = Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: field,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: _entryLabelSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: width,
          height: _entryBoxHeight,
          child: ClipRect(child: field),
        ),
      ],
    );
  }

  Widget _buildStackedGroupDropdown() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'GROUP',
          style: TextStyle(
            fontSize: _entryLabelSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _entryBoxWidth,
          height: _entryBoxHeight,
          child: _buildItemMasterDropdown(),
        ),
      ],
    );
  }

  Widget _buildItemMasterDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('bill_group_dropdown'),
      focusNode: _groupFocus,
      value: _selectedParticular,
      isExpanded: true,
      alignment: AlignmentDirectional.bottomStart,
      decoration: _entryDecoration().copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
      ),
      dropdownColor: Colors.white,
      style: const TextStyle(
        fontSize: AppTextSizes.fieldText,
        color: Colors.black,
        height: 1,
      ),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 22),
      hint: const Text(
        'Select',
        style: TextStyle(
          fontSize: AppTextSizes.fieldText,
          color: Colors.black54,
          height: 1,
        ),
      ),
      items: _masterParticulars
          .map(
            (name) => DropdownMenuItem(
              value: name,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTextSizes.fieldText,
                  color: Colors.black,
                  height: 1,
                ),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _selectedParticular = value;
          _particularError = null;
        });
        _focusRate();
      },
    );
  }

  static const double _entryColumnGap = 14;

  Widget _buildAlignedEntryRow({required bool showTax, bool mobile = false}) {
    if (mobile) {
      return _buildEntryRowFallbackMobile();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStackedGroupDropdown(),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              blockTabTraversal: true,
              textInputAction: TextInputAction.next,
              fieldKey: const Key('bill_rate_field'),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              blockTabTraversal: true,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_qty_field'),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'AMOUNT',
              controller: _amountController,
              readOnly: true,
            ),
          ],
        ),
        ..._entryRowErrors(),
      ],
    );
  }

  Widget _buildEntryRowFallbackMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: _entryColumnGap,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _buildStackedGroupDropdown(),
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              blockTabTraversal: true,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_rate_field'),
            ),
            _buildStackedEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              blockTabTraversal: true,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_qty_field'),
            ),
            _buildStackedEntryField(
              label: 'AMOUNT',
              controller: _amountController,
              readOnly: true,
            ),
          ],
        ),
        ..._entryRowErrors(),
      ],
    );
  }

  List<Widget> _entryRowErrors() {
    return [
      if (_rateError != null) ...[
        const SizedBox(height: 4),
        Text(
          _rateError!,
          style: const TextStyle(color: AppColors.danger, fontSize: 10),
        ),
      ],
      if (_qtyError != null) ...[
        const SizedBox(height: 4),
        Text(
          _qtyError!,
          style: const TextStyle(color: AppColors.danger, fontSize: 10),
        ),
      ],
    ];
  }

  // ============================================================
  // ITEM TABLE
  //
  // BEFORE ITEM (Enter on Qty adds first row):
  //
  // S.NO | RATE | QTY | AMOUNT | Total | CGST % | SGST % | IGST | X
  // ============================================================

  double _tableWidth(bool showTax) =>
      (showTax ? 820 : 620).toDouble() + _deleteColWidth;

  Widget _buildItemTableSection({bool mobile = false}) {
    final showTax = _items.isNotEmpty;
    final width = _tableWidth(showTax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAlignedEntryRow(showTax: showTax, mobile: mobile),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildItemTable(mobile: mobile),
              if (_items.isNotEmpty) ...[
                SizedBox(
                  width: width,
                  child: _buildGrandTotalFooter(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemTable({bool mobile = false}) {
    final bool showTax = _items.isNotEmpty;
    final width = _tableWidth(showTax);

    Widget table = SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.background,
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTableHeader(showTax),
            ...List.generate(_items.length, (index) {
              if (_editingIndex == index) {
                return _buildEditRow(index);
              }
              return _buildTableRow(index, showTax);
            }),
          ],
        ),
      ),
    );

    if (!mobile) {
      return table;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: table,
    );
  }  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildTableHeader(bool showTax) {
    return Container(
      height: _tableRowHeight,
      color: AppColors.tableHeader,
      child: Row(
        children: [
          _tableHeaderCell('S.NO', _flexSno),
          _tableHeaderCell('GROUP', _flexGroup),
          _tableHeaderCell('RATE', _flexRate, alignRight: true),
          _tableHeaderCell('QTY', _flexQty, alignRight: true),
          _tableHeaderCell('AMOUNT', _flexAmount, alignRight: true),
          _tableHeaderCell('TOTAL', _flexLineTotal, alignRight: true, last: !showTax),
          if (showTax) ...[
            _tableHeaderCell('CGST %', _flexCgst, alignRight: true),
            _tableHeaderCell('SGST %', _flexSgst, alignRight: true),
            _tableHeaderCell('IGST', _flexIgst, alignRight: true),
          ],
          _tableDeleteHeaderCell(),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(
    String text,
    int flex, {
    bool last = false,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: _tableRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        alignment:
            alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: const TextStyle(
            fontSize: _tableHeaderFontSize,
            fontWeight: FontWeight.bold,
            height: 1.1,
            color: Color(0xFF111111),
          ),
        ),
      ),
    );
  }

  Widget _tableDeleteHeaderCell() {
    return SizedBox(
      width: _deleteColWidth,
      child: Container(
        height: _tableRowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildEditRow(int index) {
    return Container(
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Line ${index + 1}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'Rate',
            controller: _editRateController,
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'Qty',
            controller: _editQtyController,
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: _entryBoxHeight,
            child: ElevatedButton(
              key: const Key('bill_edit_line_ok'),
              onPressed: _applyLineEdit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, _entryBoxHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('OK', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditLineField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: _entryLabelSize,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _entryBoxWidth,
          height: _entryBoxHeight,
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: AppTextSizes.fieldText, height: 1),
            decoration: _entryDecoration(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildTableRow(
      int index,
      bool showTax,
      ) {
    final BillItem item =
    _items[index];

    final bool selected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (_editUnlocked) {
          _startEditLine(index);
          return;
        }

        setState(() {
          _selectedIndex = selected ? null : index;
        });
      },
      child: Container(
        height: _tableRowHeight,
        color: selected ? const Color(0xFFFFE5A0) : AppColors.background,
        child: Row(
          children: [
            _tableDataCell('${index + 1}', _flexSno),
            _tableDataCell(
              item.particular.trim().toUpperCase(),
              _flexGroup,
            ),
            _tableDataCell(_formatAmount(item.rate), _flexRate, alignRight: true),
            _tableDataCell(_formatQtyOrPct(item.qty), _flexQty, alignRight: true),
            _tableDataCell(_formatAmount(item.amount), _flexAmount, alignRight: true),
            _tableDataCell(
              _formatAmount(item.grossAmt),
              _flexLineTotal,
              alignRight: true,
              last: !showTax,
            ),
            if (showTax) ...[
              _tableDataCell(
                _formatQtyOrPct(item.cgstPct),
                _flexCgst,
                alignRight: true,
              ),
              _tableDataCell(
                _formatQtyOrPct(item.sgstPct),
                _flexSgst,
                alignRight: true,
              ),
              _tableDataCell(
                _formatAmount(item.igst),
                _flexIgst,
                alignRight: true,
              ),
            ],
            _buildDeleteCell(index),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteCell(int index) {
    return SizedBox(
      width: _deleteColWidth,
      child: Container(
        height: _tableRowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.close, color: AppColors.danger, size: 16),
          tooltip: 'Remove item',
          onPressed: () => _removeItem(index),
        ),
      ),
    );
  }

  // ============================================================
  // TABLE DATA CELL
  // ============================================================

  Widget _tableDataCell(
    String text,
    int flex, {
    bool last = false,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: _tableRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: AppColors.border, width: 0.6),
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        alignment:
            alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: const TextStyle(
            fontSize: _tableCellFontSize,
            fontWeight: FontWeight.w600,
            height: 1.1,
            color: Color(0xFF111111),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // GRAND TOTAL (below item table only)
  // ============================================================

  Widget _buildGrandTotalFooter() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        border: Border(
          left: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'GRAND TOTAL',
                style: TextStyle(
                  fontSize: AppTextSizes.sectionHeader,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              Expanded(
                child: Text(
                  _formatAmount(_grandTotal),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTextSizes.statNumber,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amountInWords(_grandTotal),
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTextSizes.listSubtitle,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    SyncService.instance.manualPushInProgress
        .removeListener(_onManualPushChanged);
    _persistSession();

    _customerNameController.dispose();

    _mobileController.dispose();

    _passwordController.dispose();
    _editRateController.dispose();
    _editQtyController.dispose();

    _rateController.dispose();

    _qtyController.dispose();

    _amountController.dispose();

    _rateFocus.dispose();

    _qtyFocus.dispose();

    _nameFocus.dispose();

    _mobileFocus.dispose();

    _groupFocus.dispose();

    super.dispose();
  }
}
