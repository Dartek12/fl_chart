import 'dart:async';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_scaffold_widget.dart';
import 'package:fl_chart/src/chart/line_chart/line_chart_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

/// Renders a line chart as a widget, using provided [LineChartData].
class LineChart extends ImplicitlyAnimatedWidget {
  /// [data] determines how the [LineChart] should be look like,
  /// when you make any change in the [LineChartData], it updates
  /// new values with animation, and duration is [swapAnimationDuration].
  /// also you can change the [swapAnimationCurve]
  /// which default is [Curves.linear].
  const LineChart(
    this.data, {
    this.chartRendererKey,
    super.key,
    super.duration = const Duration(milliseconds: 150),
    super.curve = Curves.linear,
  });

  /// Determines how the [LineChart] should be look like.
  final LineChartData data;

  /// We pass this key to our renderers which are supposed to
  /// render the chart itself (without anything around the chart).
  final Key? chartRendererKey;

  /// Creates a [_LineChartState]
  @override
  _LineChartState createState() => _LineChartState();
}

class _LineChartState extends AnimatedWidgetBaseState<LineChart>
    with ChartTooltipProviderMixin {
  /// we handle under the hood animations (implicit animations) via this tween,
  /// it lerps between the old [LineChartData] to the new one.
  LineChartDataTween? _lineChartDataTween;

  /// If [LineTouchData.handleBuiltInTouches] is true, we override the callback to handle touches internally,
  /// but we need to keep the provided callback to notify it too.
  BaseTouchCallback<LineTouchResponse>? _providedTouchCallback;

  final Map<int, List<int>> _showingTouchedIndicators = {};

  @override
  Widget build(BuildContext context) {
    final showingData = _getData();

    return AxisChartScaffoldWidget(
      chart: LineChartLeaf(
        data: _withTouchedIndicators(_lineChartDataTween!.evaluate(animation)),
        targetData: _withTouchedIndicators(showingData),
        key: widget.chartRendererKey,
      ),
      data: showingData,
    );
  }

  LineChartData _withTouchedIndicators(LineChartData lineChartData) {
    if (!lineChartData.lineTouchData.enabled ||
        !lineChartData.lineTouchData.handleBuiltInTouches) {
      return lineChartData;
    }

    return lineChartData.copyWith(
      lineBarsData: lineChartData.lineBarsData.map((barData) {
        final index = lineChartData.lineBarsData.indexOf(barData);
        return barData.copyWith(
          showingIndicators: _showingTouchedIndicators[index] ?? [],
        );
      }).toList(),
    );
  }

  LineChartData _getData() {
    final lineTouchData = widget.data.lineTouchData;
    if (lineTouchData.enabled && lineTouchData.handleBuiltInTouches) {
      _providedTouchCallback = lineTouchData.touchCallback;
      return widget.data.copyWith(
        lineTouchData: widget.data.lineTouchData
            .copyWith(touchCallback: _handleBuiltInTouch),
      );
    }
    return widget.data;
  }

  void _handleBuiltInTouch(
    FlTouchEvent event,
    LineTouchResponse? touchResponse,
  ) {
    if (!mounted) {
      return;
    }
    _providedTouchCallback?.call(event, touchResponse);

    if (!event.isInterestedForInteractions ||
        touchResponse?.lineBarSpots == null ||
        touchResponse!.lineBarSpots!.isEmpty) {
      setState(_showingTouchedIndicators.clear);
      _hideTooltip();
      return;
    }

    setState(() {
      final sortedLineSpots = List.of(touchResponse.lineBarSpots!)
        ..sort((spot1, spot2) => spot2.y.compareTo(spot1.y));

      _showingTouchedIndicators.clear();
      for (var i = 0; i < touchResponse.lineBarSpots!.length; i++) {
        final touchedBarSpot = touchResponse.lineBarSpots![i];
        final barPos = touchedBarSpot.barIndex;
        _showingTouchedIndicators[barPos] = [touchedBarSpot.spotIndex];
      }

      showTooltip(ShowingTooltipIndicators(sortedLineSpots));
    });
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _lineChartDataTween = visitor(
      _lineChartDataTween,
      _getData(),
      (dynamic value) =>
          LineChartDataTween(begin: value as LineChartData, end: widget.data),
    ) as LineChartDataTween?;
  }

  @override
  Offset getLocalPosition(FlSpot spot) {
    final render = _findRenderObject(context)!;

    final size = render.size;
    // ignore: invalid_use_of_visible_for_testing_member
    final x = render.painter.getPixelX(spot.x, size, render.paintHolder);
    // ignore: invalid_use_of_visible_for_testing_member
    final y = render.painter.getPixelY(spot.y, size, render.paintHolder);

    return Offset(x, y);
  }

  RenderLineChart? _findRenderObject(BuildContext context) {
    RenderLineChart? render;
    context.visitChildElements((element) {
      if (render != null) return;

      if (element.renderObject is RenderLineChart) {
        render = element.renderObject as RenderLineChart?;
      } else {
        render = _findRenderObject(element);
      }
    });

    return render;
  }
}

@optionalTypeArgs
mixin ChartTooltipProviderMixin<T extends StatefulWidget> on State<T> {
  static const Duration _tooltipTimeout = Duration(milliseconds: 300);
  static const Duration _fadeInDuration = Duration(milliseconds: 150);
  static const Duration _fadeOutDuration = Duration(milliseconds: 75);
  static const Duration _defaultShowDuration = Duration(milliseconds: 1500);

  OverlayEntry? _entry;
  AnimationController? _backingController;
  AnimationController get _controller {
    return _backingController ??= AnimationController(
      duration: _fadeInDuration,
      reverseDuration: _fadeOutDuration,
      vsync: vsync,
    )..addStatusListener(_handleStatusChanged);
  }

  TickerProvider get vsync;

  late Offset _position;
  Timer? _timer;

  Offset getLocalPosition(FlSpot spot);

  AnimationStatus _animationStatus = AnimationStatus.dismissed;
  void _handleStatusChanged(AnimationStatus status) {
    assert(mounted);
    switch ((_isTooltipVisible(_animationStatus), _isTooltipVisible(status))) {
      case (true, false):
        _hideTooltip();
      case (false, true):
        showTooltip(indicators);
      // SemanticsService.tooltip(_tooltipMessage);
      case (true, true) || (false, false):
        break;
    }
    _animationStatus = status;
  }

  static bool _isTooltipVisible(AnimationStatus status) {
    return switch (status) {
      AnimationStatus.completed ||
      AnimationStatus.forward ||
      AnimationStatus.reverse =>
        true,
      AnimationStatus.dismissed => false,
    };
  }

  void showTooltip(ShowingTooltipIndicators indicators) {
    _position = _getGlobalPosition(indicators)!;
    _timer?.cancel();

    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }

    _entry = OverlayEntry(
      builder: _buildOverlayContent,
    );
    Overlay.of(context).insert(_entry!);
  }

  Offset? _getGlobalPosition(ShowingTooltipIndicators indicators) {
    final showingBarSpots = indicators.showingSpots;
    if (showingBarSpots.isEmpty) {
      return null;
    }
    final barSpots = List<LineBarSpot>.of(showingBarSpots);
    FlSpot topSpot = barSpots[0];
    for (final barSpot in barSpots) {
      if (barSpot.y > topSpot.y) {
        topSpot = barSpot;
      }
    }

    final localPosition = getLocalPosition(topSpot);

    final overlayState = Overlay.of(context, debugRequiredFor: widget);
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(
      localPosition,
      ancestor: overlayState.context.findRenderObject(),
    );
  }

  void _hideTooltip() {
    if (_entry == null) return;

    _timer?.cancel();
    _timer = Timer(_tooltipTimeout, () {
      _entry!.remove();
      _entry = null;
    });
  }

  Widget _buildOverlayContent(BuildContext context) {
    print('build, ${Theme.of(context).brightness}');
    return Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0,
      child: _Tooltip(duration: kThemeAnimationDuration, position: _position),
    );
  }
}

class _Tooltip extends ImplicitlyAnimatedWidget {
  final Offset position;

  const _Tooltip({required this.position, required super.duration});

  @override
  __TooltipState createState() => __TooltipState();
}

class __TooltipState extends AnimatedWidgetBaseState<_Tooltip> {
  static const double _defaultVerticalOffset = 24;

  Tween<Offset>? _positionTween;
  late Animation<Offset> _positionAnimation;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _positionTween = visitor(
      _positionTween,
      widget.position,
      (dynamic value) => Tween<Offset>(begin: value as Offset),
    )! as Tween<Offset>;
  }

  @override
  void didUpdateTweens() {
    _positionAnimation = animation.drive(_positionTween!);
  }

  @override
  Widget build(BuildContext context) {
    // TODO: position is wrong, themeing not working
    final tooltipTheme = Theme.of(context).tooltipTheme;
    final result =
        Container(width: 50, height: 50, color: Theme.of(context).canvasColor);
    final verticalOffset =
        tooltipTheme.verticalOffset ?? _defaultVerticalOffset;

    return CustomSingleChildLayout(
      delegate: _TooltipPositionDelegate(
        target: _positionAnimation.value,
        verticalOffset: verticalOffset,
        preferBelow: false,
      ),
      child: result,
    );
  }
}

class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  /// Creates a delegate for computing the layout of a tooltip.
  _TooltipPositionDelegate({
    required this.target,
    required this.verticalOffset,
    required this.preferBelow,
  });

  /// The offset of the target the tooltip is positioned near in the global
  /// coordinate system.
  final Offset target;

  /// The amount of vertical distance between the target and the displayed
  /// tooltip.
  final double verticalOffset;

  /// Whether the tooltip is displayed below its widget by default.
  ///
  /// If there is insufficient space to display the tooltip in the preferred
  /// direction, the tooltip will be displayed in the opposite direction.
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
    );
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        verticalOffset != oldDelegate.verticalOffset ||
        preferBelow != oldDelegate.preferBelow;
  }
}
