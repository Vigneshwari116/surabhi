import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:surabhi/theme/app_theme.dart';

/// Full-width report body with standard side padding (no max-width cap).
class ReportFullWidthBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ReportFullWidthBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        width: double.infinity,
        child: child,
      ),
    );
  }
}

/// Scrollable report area with optional horizontal scroll below [minTableWidth].
class ReportScrollArea extends StatefulWidget {
  final double minTableWidth;
  final Widget child;

  const ReportScrollArea({
    super.key,
    required this.minTableWidth,
    required this.child,
  });

  @override
  State<ReportScrollArea> createState() => _ReportScrollAreaState();
}

class _ReportScrollAreaState extends State<ReportScrollArea> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    if (!_horizontalController.hasClients) {
      return;
    }
    final target = _horizontalController.offset + event.scrollDelta.dy;
    _horizontalController.jumpTo(
      target.clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final tableWidth = math.max(viewportWidth, widget.minTableWidth);
          final needsHorizontalScroll = viewportWidth < widget.minTableWidth;

          Widget content = SizedBox(
            width: tableWidth,
            child: widget.child,
          );

          content = Scrollbar(
            key: const Key('report_table_vertical_scroll'),
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: content,
            ),
          );

          if (!needsHorizontalScroll) {
            return Listener(
              onPointerSignal: _onPointerSignal,
              child: content,
            );
          }

          return Listener(
            onPointerSignal: _onPointerSignal,
            child: Scrollbar(
              key: const Key('report_table_horizontal_scroll'),
              controller: _horizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ledger-style table: fixed header/footer, scrollable body, dual-axis scroll.
class ReportTableViewport extends StatefulWidget {
  final double minTableWidth;
  final Widget header;
  final Widget footer;
  final List<Widget> bodyRows;
  final BoxDecoration? decoration;

  const ReportTableViewport({
    super.key,
    required this.minTableWidth,
    required this.header,
    required this.footer,
    required this.bodyRows,
    this.decoration,
  });

  @override
  State<ReportTableViewport> createState() => _ReportTableViewportState();
}

class _ReportTableViewportState extends State<ReportTableViewport> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    if (!_horizontalController.hasClients) {
      return;
    }
    final target = _horizontalController.offset + event.scrollDelta.dy;
    _horizontalController.jumpTo(
      target.clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration ??
        BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(6),
        );

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final tableWidth = math.max(viewportWidth, widget.minTableWidth);
          final needsHorizontalScroll = viewportWidth < widget.minTableWidth;

          Widget table = Container(
            width: tableWidth,
            decoration: decoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.header,
                Expanded(
                  child: Scrollbar(
                    key: const Key('report_table_vertical_scroll'),
                    controller: _verticalController,
                    thumbVisibility: true,
                    child: ListView(
                      controller: _verticalController,
                      children: widget.bodyRows,
                    ),
                  ),
                ),
                widget.footer,
              ],
            ),
          );

          if (!needsHorizontalScroll) {
            return Listener(
              onPointerSignal: _onPointerSignal,
              child: table,
            );
          }

          return Listener(
            onPointerSignal: _onPointerSignal,
            child: Scrollbar(
              key: const Key('report_table_horizontal_scroll'),
              controller: _horizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  height: constraints.maxHeight,
                  child: table,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
