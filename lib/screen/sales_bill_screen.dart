
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

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
import 'package:surabhi/utils/qty_format.dart';
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

  /// Bill screen typography — local only; other screens stay on [AppTextSizes].
  static const double _billMainFontSize = 24;
  static const double _customerFontSize = 20;
  static const double _gridFontSize = 18;
  static const double _grandTotalAmountFontSize = 32;
  static const double _amountInWordsFontSize = 16;
  static const double _pcsFooterFontSize = 20;
  static const double _todayCardLabelFontSize = 16;
  static const double _todayCardValueFontSize = 20;

  static const double _billNoBoxWidth = 100;
  static const double _upiBoxWidth = 150;
  static const double _billDateBoxWidth = 170;
  static const double _groupBoxWidth = 240;
  static const double _numericBoxWidth = 150;
  static const double _entryBoxHeight = 52;
  static const double _entryFieldVerticalPadding = 14;
  static const double _customerFieldHeight = 40;
  static const double _customerFieldVerticalPadding = 10;
  static const double _customerNameWidth = 220;
  static const double _customerMobileWidth = 170;
  static const double _topAreaGap = 8;
  static const double _actionButtonGap = 12;
  static const double _framePadding = 6;
  static const double _compactButtonMinWidth = 150;
  static const double _tableHeaderHeight = 40;
  static const double _tableRowHeight = 38;
  static const double _gridFooterHeight = 76;
  static const double _bottomBarHeight = 52;
  static const double _desktopChromeEstimate = 368;
  static const double _gridMinScrollHeight =
      _tableHeaderHeight + (_tableRowHeight * 4) + _gridFooterHeight + 8;
  static const double _deleteColWidth = 48;
  static const double _gridMinWidthBeforeHScroll = 1000;
  static const int _flexSno = 10;
  static const int _flexGroup = 30;
  static const int _flexRate = 20;
  static const int _flexQty = 15;
  static const int _flexAmount = 22;
  static const int _flexTotal = 22;
  static const int _flexCgst = 16;
  static const int _flexSgst = 16;
  static const int _flexIgst = 14;
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
  final FocusNode _paymentFocus = FocusNode();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _saveSaleFocus = FocusNode();

  String _lastFocusField = 'name';

  double _todayAmount = 0;
  double _todayGst = 0;
  double _todayGrandTotal = 0;
  double _todayPcs = 0;
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
    _paymentFocus.addListener(() {
      if (_paymentFocus.hasFocus) _onFieldFocused('payment');
    });
    _groupFocus.addListener(() {
      if (_groupFocus.hasFocus) _onFieldFocused('group');
    });

    _manualPushInProgress = SyncService.instance.manualPushInProgress.value;
    SyncService.instance.manualPushInProgress.addListener(_onManualPushChanged);

    _loadGstRates();
    unawaited(_loadMasterParticulars());

    if (widget.initialBillNo != null) {
      _billNo = widget.initialBillNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPayment();
      });
    } else {
      _restoreSessionOrLoadBill().then((_) {
        if (mounted) {
          _focusPayment();
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
        _focusName();
      case 'group':
        _focusGroup();
      case 'payment':
      default:
        _focusPayment();
    }
  }

  void _focusPayment() {
    if (!mounted) return;
    _paymentFocus.requestFocus();
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
      height: _entryBoxHeight,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.actionButton,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(_compactButtonMinWidth, _entryBoxHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: _billMainFontSize,
            fontWeight: FontWeight.w600,
          ),
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
      _focusGroup();
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
    final hideDesktopTitleBar = !mobileBillLayout;
    final body = mobileBillLayout
        ? _buildMobileBody(context)
        : _buildDesktopBody(
            context: context,
            showMenuButton: hideDesktopTitleBar && !widget.embeddedInDashboard,
            useSidebarLayout: useSidebarLayout,
          );

    if (widget.embeddedInDashboard) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: hideDesktopTitleBar
            ? null
            : sectionHeaderAppBar('SALES BILL'),
        body: _buildLockedBody(body),
      );
    }

    if (useSidebarLayout) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: hideDesktopTitleBar
            ? null
            : _buildAppBar(
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
      appBar: hideDesktopTitleBar
          ? null
          : _buildAppBar(
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
    );
  }

  double _gridFontSizeForWidth(double width) => _gridFontSize;

  Widget _buildDesktopBody({
    required BuildContext context,
    required bool showMenuButton,
    required bool useSidebarLayout,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridFontSize = _gridFontSizeForWidth(constraints.maxWidth);
        final fitsFixedLayout = constraints.maxHeight >=
            _desktopChromeEstimate + _gridMinScrollHeight;

        Widget columnChild({
          required bool expandGrid,
          double? gridHeight,
        }) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopArea(
                includeEntryRow: true,
                gridFontSize: gridFontSize,
                showMenuButton: showMenuButton,
                useSidebarLayout: useSidebarLayout,
                menuContext: context,
              ),
              const SizedBox(height: _topAreaGap),
              if (expandGrid)
                Expanded(
                  child: _buildDesktopGridZone(
                    gridFontSize: gridFontSize,
                  ),
                )
              else
                SizedBox(
                  height: gridHeight ??
                      math.max(
                        _gridMinScrollHeight,
                        constraints.maxHeight - _desktopChromeEstimate,
                      ),
                  child: _buildDesktopGridZone(
                    gridFontSize: gridFontSize,
                  ),
                ),
              const SizedBox(height: _topAreaGap),
              _buildSaveSaleBar(),
            ],
          );
        }

        final content = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: fitsFixedLayout
                ? columnChild(expandGrid: true)
                : SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: columnChild(
                        expandGrid: false,
                        gridHeight: math.max(
                          _gridMinScrollHeight,
                          constraints.maxHeight - _desktopChromeEstimate,
                        ),
                      ),
                    ),
                  ),
          ),
        );

        return content;
      },
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
        _todayPcs = summary.totalPcs;
      });
    } catch (_) {
      // Keep previous totals on refresh failure.
    }
  }

  Future<void> _onTodaySalesPressed() async {
    final show = !_todaySalesPanelVisible;
    setState(() => _todaySalesPanelVisible = show);
    if (show) {
      await _refreshTodaySales();
    }
  }

  Widget _buildTodaySalesButton() {
    final pressed = _todaySalesPanelVisible;
    return SizedBox(
      height: _entryBoxHeight,
      child: ElevatedButton(
        key: const Key('today_sales_button'),
        onPressed: _busy ? null : _onTodaySalesPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: pressed
              ? AppColors.navy
              : AppColors.actionButton,
          foregroundColor: Colors.white,
          elevation: pressed ? 4 : 1,
          shadowColor: Colors.black45,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(_compactButtonMinWidth, _entryBoxHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: _billMainFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text('TODAY SALES'),
      ),
    );
  }

  Widget _buildTodaySalesSummary({bool inline = false}) {
    return CompactAbstractSummary(
      amountValue: _formatAmount(_todayAmount),
      gstValue: _formatAmount(_todayGst),
      pcsValue: formatPcs(_todayPcs),
      grandTotalValue: _formatAmount(_todayGrandTotal),
      grandTotalLabel: 'Total sales',
      cardWidth: 130,
      fixedHeight: inline ? _bottomBarHeight : null,
      forceHorizontalRow: inline,
      labelFontSize: _todayCardLabelFontSize,
      valueFontSize: _todayCardValueFontSize,
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
    return SizedBox(
      height: _bottomBarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(6),
            child: SizedBox(
              height: _bottomBarHeight,
              child: ElevatedButton(
                key: const Key('save_sale_bar_button'),
                focusNode: _saveSaleFocus,
                onPressed: _saveBill,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize:
                      const Size(_compactButtonMinWidth, _bottomBarHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: _billMainFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                child: const Text('SAVE SALE'),
              ),
            ),
          ),
          const SizedBox(width: _topAreaGap),
          Expanded(
            child: Opacity(
              opacity: _todaySalesPanelVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_todaySalesPanelVisible,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTodaySalesSummary(inline: true),
                ),
              ),
            ),
          ),
          if (_particularError != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _particularError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: AppTextSizes.listSubtitle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTopArea(),
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

  Widget _buildTopArea({
    bool includeEntryRow = false,
    double gridFontSize = _gridFontSize,
    bool showMenuButton = false,
    bool useSidebarLayout = false,
    BuildContext? menuContext,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: _actionButtonGap,
            runSpacing: _actionButtonGap,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showMenuButton && menuContext != null)
                IconButton(
                  icon: Icon(
                    useSidebarLayout && _sidebarOpen
                        ? Icons.menu_open
                        : Icons.menu,
                  ),
                  tooltip: useSidebarLayout && _sidebarOpen
                      ? 'Close menu'
                      : 'Open menu',
                  onPressed: () {
                    if (useSidebarLayout) {
                      setState(() => _sidebarOpen = !_sidebarOpen);
                    } else {
                      Scaffold.maybeOf(menuContext)?.openDrawer();
                    }
                  },
                ),
              Focus(
                skipTraversal: true,
                child: _buildTodaySalesButton(),
              ),
              Focus(
                skipTraversal: true,
                child: _buildBillNavButton(
                  label: 'PREVIOUS',
                  onPressed: _goToPreviousBill,
                ),
              ),
              Focus(
                skipTraversal: true,
                child: _buildBillNavButton(
                  label: 'NEXT',
                  onPressed: _goToNextBill,
                ),
              ),
            ],
          ),
          const SizedBox(height: _topAreaGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final bill = Focus(
                skipTraversal: true,
                child: _buildBillDetails(),
              );
              final customer = Focus(
                skipTraversal: true,
                child: _buildCustomerDetails(),
              );
              const minRowWidth = 520.0;
              if (constraints.maxWidth < minRowWidth) {
                return Wrap(
                  spacing: _topAreaGap,
                  runSpacing: _topAreaGap,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [bill, customer],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bill,
                    const SizedBox(width: _topAreaGap),
                    customer,
                  ],
                ),
              );
            },
          ),
          if (includeEntryRow) ...[
            const SizedBox(height: _topAreaGap),
            _buildAlignedEntryRow(
              showTax: _items.isNotEmpty,
              gridFontSize: gridFontSize,
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BILL DETAILS
  // ============================================================

  Widget _buildBillDetails() {
    const labelStyle = TextStyle(
      fontSize: _billMainFontSize,
      color: Colors.black,
      fontWeight: FontWeight.w600,
    );
    const valueStyle = TextStyle(
      fontSize: _billMainFontSize,
      color: Colors.black,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(_framePadding),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 118,
                  child: Text('BILL NO:', style: labelStyle),
                ),
              Container(
                width: _billNoBoxWidth,
                height: _entryBoxHeight,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: billNoColor,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$_billNo',
                    style: valueStyle.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: _upiBoxWidth,
                height: _entryBoxHeight,
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: DropdownButtonFormField<String>(
                  key: const Key('bill_payment_dropdown'),
                  focusNode: _paymentFocus,
                  value: _paymentMode,
                  isDense: false,
                  isExpanded: true,
                  alignment: AlignmentDirectional.centerStart,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _paymentFillColor(_paymentMode),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: _entryFieldVerticalPadding,
                    ),
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: _paymentTextColor(_paymentMode),
                  ),
                  style: TextStyle(
                    fontSize: _billMainFontSize,
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
                                fontSize: _billMainFontSize,
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
                          fontSize: _billMainFontSize,
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
            const SizedBox(height: _topAreaGap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 118,
                  child: Text('BILL DATE:', style: labelStyle),
                ),
                Container(
                  width: _billDateBoxWidth,
                  height: _entryBoxHeight,
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
                    style: valueStyle,
                  ),
                ),
              ],
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(_framePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text(
              'CUSTOMER DETAILS',
              style: TextStyle(
                fontSize: _customerFontSize,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 2),
          _buildLabeledCustomerField(
            label: 'NAME',
            fieldWidth: _customerNameWidth,
            traversalOrder: const NumericFocusOrder(7),
            child: _smallTextField(
              _customerNameController,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _focusMobile(),
              compact: true,
            ),
          ),
          const SizedBox(height: 4),
          _buildLabeledCustomerField(
            label: 'MOBILE',
            fieldWidth: _customerMobileWidth,
            traversalOrder: const NumericFocusOrder(8),
            child: GestureDetector(
              onDoubleTap: _onMobileDoubleTap,
              child: _smallTextField(
                _mobileController,
                number: true,
                fieldKey: const Key('bill_mobile_field'),
                focusNode: _mobileFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _focusGroup(),
                compact: true,
              ),
            ),
          ),
          if (_showPasswordField && !_editUnlocked) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'PASSWORD',
                    style: TextStyle(fontSize: _billMainFontSize),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: _entryBoxHeight,
                    child: TextField(
                      key: const Key('bill_edit_password_field'),
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: true,
                      onSubmitted: (_) => _tryUnlockEdit(),
                      style: const TextStyle(fontSize: _billMainFontSize),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: _entryBoxHeight,
                  child: ElevatedButton(
                    key: const Key('bill_edit_password_ok'),
                    onPressed: _tryUnlockEdit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, _entryBoxHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontSize: _billMainFontSize),
                    ),
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
                    fontSize: _billMainFontSize,
                  ),
                ),
              ),
          ],
          if (_editUnlocked)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'EDIT MODE — TAP A LINE TO CORRECT RATE/QTY.',
                style: TextStyle(
                  fontSize: _billMainFontSize,
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
    required double fieldWidth,
    NumericFocusOrder? traversalOrder,
  }) {
    final field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: _customerFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: fieldWidth,
          height: _customerFieldHeight,
          child: child,
        ),
      ],
    );

    if (traversalOrder == null) {
      return field;
    }

    return FocusTraversalOrder(order: traversalOrder, child: field);
  }

  // ============================================================
  // SMALL TEXT FIELD
  // ============================================================

  Widget _smallTextField(
      TextEditingController controller, {
        bool number = false,
        bool compact = false,
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
          fontSize: _customerFontSize,
          height: 1,
          color: Colors.black,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: _customerFieldDecoration(),
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
    return InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(),
      focusedBorder: const OutlineInputBorder(),
      disabledBorder: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _entryFieldVerticalPadding,
      ),
      alignLabelWithHint: true,
    );
  }

  InputDecoration _customerFieldDecoration() {
    return InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _customerFieldVerticalPadding,
      ),
      alignLabelWithHint: true,
    );
  }

  Widget _buildStackedEntryField({
    required String label,
    required TextEditingController controller,
    double fontSize = _billMainFontSize,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    bool readOnly = false,
    bool blockTabTraversal = false,
    TextInputAction? textInputAction,
    Key? fieldKey,
    double width = _numericBoxWidth,
    NumericFocusOrder? traversalOrder,
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
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        fontSize: fontSize,
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

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
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

    if (traversalOrder == null) {
      return column;
    }

    return FocusTraversalOrder(order: traversalOrder, child: column);
  }

  Widget _buildStackedGroupDropdown({double fontSize = _billMainFontSize}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'GROUP',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: SizedBox(
            width: _groupBoxWidth,
            height: _entryBoxHeight,
            child: _buildItemMasterDropdown(),
          ),
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
      isDense: false,
      decoration: _entryDecoration(),
      dropdownColor: Colors.white,
      style: const TextStyle(
        fontSize: _billMainFontSize,
        color: Colors.black,
        height: 1,
      ),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 28),
      hint: const Text(
        'SELECT',
        style: TextStyle(
          fontSize: _billMainFontSize,
          color: Colors.black54,
          height: 1,
        ),
      ),
      items: _masterParticulars
          .map(
            (name) => DropdownMenuItem(
              value: name,
              child: Text(
                name.toUpperCase(),
                overflow: TextOverflow.visible,
                softWrap: true,
                style: const TextStyle(
                  fontSize: _billMainFontSize,
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

  static const double _entryColumnGap = 12;

  Widget _buildAlignedEntryRow({
    required bool showTax,
    bool mobile = false,
    double gridFontSize = _gridFontSize,
  }) {
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
            _buildStackedGroupDropdown(fontSize: gridFontSize),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'RATE',
              fontSize: gridFontSize,
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              textInputAction: TextInputAction.next,
              fieldKey: const Key('bill_rate_field'),
              traversalOrder: const NumericFocusOrder(3),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'QTY',
              fontSize: gridFontSize,
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_qty_field'),
              traversalOrder: const NumericFocusOrder(4),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'AMOUNT',
              fontSize: gridFontSize,
              controller: _amountController,
              focusNode: _amountFocus,
              readOnly: true,
              traversalOrder: const NumericFocusOrder(5),
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
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_rate_field'),
            ),
            _buildStackedEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
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
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: _billMainFontSize,
          ),
        ),
      ],
      if (_qtyError != null) ...[
        const SizedBox(height: 4),
        Text(
          _qtyError!,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: _billMainFontSize,
          ),
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

  Widget _buildItemTableSection({bool mobile = false}) {
    final showTax = _items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAlignedEntryRow(showTax: showTax, mobile: mobile),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final gridFontSize = _gridFontSizeForWidth(constraints.maxWidth);
            return _buildGridFrame(
              gridWidth: constraints.maxWidth,
              viewportWidth: constraints.maxWidth,
              showTax: showTax,
              gridFontSize: gridFontSize,
              scrollItems: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDesktopGridZone({
    required double gridFontSize,
  }) {
    final showTax = _items.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        return _buildGridFrame(
          gridWidth: viewportWidth,
          viewportWidth: viewportWidth,
          showTax: showTax,
          gridFontSize: gridFontSize,
          scrollItems: true,
        );
      },
    );
  }

  Widget _buildGridFrame({
    required double gridWidth,
    required double viewportWidth,
    required bool showTax,
    required double gridFontSize,
    required bool scrollItems,
  }) {
    final useHorizontalScroll = viewportWidth < _gridMinWidthBeforeHScroll;
    final effectiveGridWidth = useHorizontalScroll
        ? _gridMinWidthBeforeHScroll
        : gridWidth;

    Widget grid = Container(
      width: effectiveGridWidth,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTableHeader(showTax, gridFontSize),
          if (scrollItems)
            Expanded(
              child: _buildItemRowsList(showTax, gridFontSize),
            )
          else
            _buildItemRowsColumn(showTax, gridFontSize),
          _buildGrandTotalFooter(gridFontSize),
        ],
      ),
    );

    if (useHorizontalScroll) {
      grid = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: grid,
      );
    }

    if (scrollItems) {
      return grid;
    }

    return Align(alignment: Alignment.topLeft, child: grid);
  }

  Widget _buildItemRowsList(bool showTax, double gridFontSize) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      clipBehavior: Clip.hardEdge,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          if (_editingIndex == index) {
            return _buildEditRow(index);
          }
          return _buildTableRow(index, showTax, gridFontSize);
        },
      ),
    );
  }

  Widget _buildItemRowsColumn(bool showTax, double gridFontSize) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_items.length, (index) {
          if (_editingIndex == index) {
            return _buildEditRow(index);
          }
          return _buildTableRow(index, showTax, gridFontSize);
        }),
      ),
    );
  }

  List<Widget> _flexDataColumns(
    bool showTax, {
    required List<Widget> cells,
  }) {
    final widgets = <Widget>[
      Expanded(flex: _flexSno, child: cells[0]),
      Expanded(flex: _flexGroup, child: cells[1]),
      Expanded(flex: _flexRate, child: cells[2]),
      Expanded(flex: _flexQty, child: cells[3]),
      Expanded(flex: _flexAmount, child: cells[4]),
      Expanded(flex: _flexTotal, child: cells[5]),
    ];
    if (showTax) {
      widgets.addAll([
        Expanded(flex: _flexCgst, child: cells[6]),
        Expanded(flex: _flexSgst, child: cells[7]),
        Expanded(flex: _flexIgst, child: cells[8]),
      ]);
    }
    return widgets;
  }

  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildTableHeader(bool showTax, double gridFontSize) {
    final headerCells = [
      _tableHeaderCell('S.NO', gridFontSize),
      _tableHeaderCell('GROUP', gridFontSize),
      _tableHeaderCell('RATE', gridFontSize, alignRight: true),
      _tableHeaderCell('QTY', gridFontSize, alignRight: true),
      _tableHeaderCell('AMOUNT', gridFontSize, alignRight: true),
      _tableHeaderCell('TOTAL', gridFontSize, alignRight: true, last: !showTax),
      if (showTax) ...[
        _tableHeaderCell('CGST %', gridFontSize, alignRight: true),
        _tableHeaderCell('SGST %', gridFontSize, alignRight: true),
        _tableHeaderCell('IGST', gridFontSize, alignRight: true, last: true),
      ],
    ];

    return SizedBox(
      height: _tableHeaderHeight,
      child: ColoredBox(
        color: AppColors.tableHeader,
        child: Row(
          children: [
            ..._flexDataColumns(
              showTax,
              cells: headerCells,
            ),
            _tableDeleteHeaderCell(),
          ],
        ),
      ),
    );
  }

  Widget _tableHeaderCell(
    String text,
    double fontSize, {
    bool last = false,
    bool alignRight = false,
  }) {
    return Container(
      height: _tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          right: last
              ? BorderSide.none
              : BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          height: 1.1,
          color: const Color(0xFF111111),
        ),
      ),
    );
  }

  Widget _tableDeleteHeaderCell() {
    return SizedBox(
      width: _deleteColWidth,
      child: Container(
        height: _tableHeaderHeight,
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
            'LINE ${index + 1}',
            style: const TextStyle(
              fontSize: _billMainFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'RATE',
            controller: _editRateController,
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'QTY',
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
              child: const Text(
                'OK',
                style: TextStyle(fontSize: _billMainFontSize),
              ),
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
            fontSize: _billMainFontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _numericBoxWidth,
          height: _entryBoxHeight,
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: _billMainFontSize, height: 1),
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
    double gridFontSize,
  ) {
    final BillItem item = _items[index];

    final bool selected = _selectedIndex == index;

    final dataCells = [
      _tableDataCell('${index + 1}', gridFontSize),
      _tableDataCell(
        item.particular.trim().toUpperCase(),
        gridFontSize,
      ),
      _tableDataCell(
        _formatAmount(item.rate),
        gridFontSize,
        alignRight: true,
      ),
      _tableDataCell(
        _formatQtyOrPct(item.qty),
        gridFontSize,
        alignRight: true,
      ),
      _tableDataCell(
        _formatAmount(item.amount),
        gridFontSize,
        alignRight: true,
      ),
      _tableDataCell(
        _formatAmount(item.grossAmt),
        gridFontSize,
        alignRight: true,
        last: !showTax,
      ),
      if (showTax) ...[
        _tableDataCell(
          _formatQtyOrPct(item.cgstPct),
          gridFontSize,
          alignRight: true,
        ),
        _tableDataCell(
          _formatQtyOrPct(item.sgstPct),
          gridFontSize,
          alignRight: true,
        ),
        _tableDataCell(
          _formatAmount(item.igst),
          gridFontSize,
          alignRight: true,
          last: true,
        ),
      ],
    ];

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
            ..._flexDataColumns(showTax, cells: dataCells),
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
        child: Focus(
          skipTraversal: true,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close, color: AppColors.danger, size: 22),
            tooltip: 'Remove item',
            onPressed: () => _removeItem(index),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TABLE DATA CELL
  // ============================================================

  Widget _tableDataCell(
    String text,
    double fontSize, {
    bool last = false,
    bool alignRight = false,
  }) {
    return Container(
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
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: null,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: const Color(0xFF111111),
        ),
      ),
    );
  }

  // ============================================================
  // GRAND TOTAL (below item table only)
  // ============================================================

  Widget _buildGrandTotalFooter(double gridFontSize) {
    final words = amountInWords(_grandTotal).toUpperCase();
    return SizedBox(
      height: _gridFooterHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.headerBand,
          border: Border(
            left: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'PCS: ${formatPcs(_totalQty)}',
              style: const TextStyle(
                fontSize: _pcsFooterFontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatAmount(_grandTotal),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: _grandTotalAmountFontSize,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      words,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: _amountInWordsFontSize,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    _paymentFocus.dispose();
    _amountFocus.dispose();
    _saveSaleFocus.dispose();

    super.dispose();
  }
}
