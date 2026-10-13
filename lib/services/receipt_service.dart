import 'package:intl/intl.dart';
import 'package:surabhi/config/location_codes.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = businessDisplayName;
  static const String gstin = '29ACDPJ2452J1ZK';

  /// TVS RP3200 Font A — 48 columns on 80mm paper.
  static const int _paperWidth = 48;

  /// Content width with equal left/right margins on the roll.
  static const int _contentWidth = 32;
  static const int _margin = (_paperWidth - _contentWidth) ~/ 2;

  static const int _snoW = 3;
  static const int _partW = 11;
  static const int _rateW = 6;
  static const int _qtyW = 4;
  static const int _amountW =
      _contentWidth - _snoW - _partW - _rateW - _qtyW;
  static const int _labelW = _contentWidth - _amountW;

  static String buildReceiptText(SaleBill bill) {
    final code = locationCodeFromDisplayName(bill.location);
    return _buildOriginalFormat(bill, code).trimRight();
  }

  /// Original thermal layout — dashed separators, per-item CGST/SGST lines.
  static String _buildOriginalFormat(SaleBill bill, String locationCode) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd/MM/yyyy').format(bill.billDate);
    final profile = _locationProfile(locationCode);
    final line = _formatLeft('-' * _contentWidth);

    buffer.writeln(_formatCentered(_center(businessName)));
    buffer.writeln(_formatLeft(_singleLineAddress(profile.addressLine)));
    buffer.writeln(_formatCentered(_center('GSTIN:$gstin')));
    buffer.writeln(_formatLeft(_billDateLine(bill.billNo, dateText)));
    buffer.writeln(_formatLeft(_fieldLine('NAME', bill.customerName)));
    buffer.writeln(_formatLeft(_fieldLine('MOBILE', bill.mobile)));
    buffer.writeln(line);
    buffer.writeln(_formatLeft(_itemHeader()));
    buffer.writeln(line);

    for (var i = 0; i < bill.items.length; i++) {
      final item = bill.items[i];
      buffer.writeln(_formatLeft(_itemLine(i + 1, item)));
      buffer.writeln(line);
      buffer.writeln(_formatLeft(_itemGstLine(item)));
      buffer.writeln(line);
    }

    buffer.writeln(_formatLeft(_totalLine(bill.totalQty, bill.grandTotal)));
    buffer.writeln(_formatLeft(_rightAmountLine('CGST', bill.totalCgst)));
    buffer.writeln(_formatLeft(_rightAmountLine('SGST', bill.totalSgst)));
    buffer.writeln(line);
    buffer.writeln(_formatLeft(_rightAmountLine('GRAND TOTAL', bill.grandTotal)));
    buffer.writeln(line);
    _writeFooter(buffer);
    return buffer.toString();
  }

  static void _writeFooter(StringBuffer buffer) {
    buffer.writeln(_formatLeft('TERMS AND CONDITION'));
    buffer.writeln(_formatLeft('AMOUNT NOT REFUND'));
    buffer.writeln(_formatCentered(_center('THANK YOU VISIT AGAIN')));
  }

  static _LocationReceiptProfile _locationProfile(String locationCode) {
    return const _LocationReceiptProfile(
      addressLine:
          'T.10,3RD FLR,LN COMPLEX,OLD THARGUPET,Bangalore',
    );
  }

  static String _singleLineAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.length <= _contentWidth) {
      return trimmed;
    }
    return trimmed.substring(0, _contentWidth);
  }

  static String _itemHeader() {
    return '${_padRight('SNO', _snoW)}'
        '${_padRight('PARTICULAR', _partW)}'
        '${_padRight('RATE', _rateW)}'
        '${_padRight('QTY', _qtyW)}'
        '${_padLeft('AMOUNT', _amountW)}';
  }

  static String _itemLine(int sno, BillItem item) {
    final particular = item.particular.trim();
    return '${_padRight('$sno', _snoW)}'
        '${_padRight(particular, _partW)}'
        '${_padRight(_rate(item.rate), _rateW)}'
        '${_padRight(_qty(item.qty), _qtyW)}'
        '${_padLeft(_amount(item.grossAmt), _amountW)}';
  }

  static String _itemGstLine(BillItem item) {
    return 'CGST% ${_formatPct(item.cgstPct)}'
        'SGST% ${_formatPct(item.sgstPct)}';
  }

  static String _totalLine(double qty, double grandTotal) {
    final left = _padRight('TOTAL', _snoW + _partW + _rateW);
    final qtyPart = _padRight(_qty(qty), _qtyW);
    final amountPart = _padLeft(_amount(grandTotal), _amountW);
    return '$left$qtyPart$amountPart';
  }

  static String _rightAmountLine(String label, double amount) {
    final labelPart = _padRight(label, _labelW);
    return '$labelPart${_padLeft(_amount(amount), _amountW)}';
  }

  static String _fieldLine(String label, String value) {
    final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.isEmpty ? '$label:' : '$label:$text';
  }

  static String _billDateLine(int billNo, String dateText) {
    final left = 'BILL NO:$billNo';
    final right = 'DATE:$dateText';
    final gap = _contentWidth - left.length - right.length;
    if (gap < 1) {
      final maxLeft = _contentWidth - right.length - 1;
      final trimmedLeft =
          left.length > maxLeft ? left.substring(0, maxLeft) : left;
      final adjustedGap = _contentWidth - trimmedLeft.length - right.length;
      return '$trimmedLeft${' ' * adjustedGap}$right';
    }
    return '$left${' ' * gap}$right';
  }

  /// Left-aligns [content] within the printable area with equal side margins.
  static String _formatLeft(String content) {
    final trimmed = content.trimRight();
    if (trimmed.length > _contentWidth) {
      return '${' ' * _margin}${trimmed.substring(0, _contentWidth)}'
          '${' ' * _margin}';
    }
    final rightPad = _paperWidth - _margin - trimmed.length;
    return '${' ' * _margin}$trimmed${' ' * rightPad}';
  }

  /// Centers [content] within the printable area and pads to [_paperWidth].
  static String _formatCentered(String content) {
    final trimmed = content.trimRight();
    if (trimmed.isEmpty) {
      return ' ' * _paperWidth;
    }
    if (trimmed.length > _contentWidth) {
      return '${' ' * _margin}${trimmed.substring(0, _contentWidth)}'
          '${' ' * _margin}';
    }
    final leftPad = _margin + ((_contentWidth - trimmed.length) / 2).floor();
    final rightPad = _paperWidth - leftPad - trimmed.length;
    return '${' ' * leftPad}$trimmed${' ' * rightPad}';
  }

  static String _center(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length >= _contentWidth) {
      return trimmed.substring(0, _contentWidth);
    }
    final pad = ((_contentWidth - trimmed.length) / 2).floor();
    return '${' ' * pad}$trimmed';
  }

  static String _padRight(String text, int width) {
    if (text.length >= width) {
      return text.substring(0, width);
    }
    return text.padRight(width);
  }

  static String _padLeft(String text, int width) {
    if (text.length >= width) {
      return text.substring(text.length - width);
    }
    return text.padLeft(width);
  }

  static String _amount(double value) {
    return value.toStringAsFixed(2);
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

  static String _formatPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _LocationReceiptProfile {
  final String addressLine;

  const _LocationReceiptProfile({required this.addressLine});
}
