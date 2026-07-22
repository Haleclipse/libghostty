import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show GridRef, Position;
import 'package:meta/meta.dart';

import '../foundation.dart';
import 'terminal_controller.dart';
import 'terminal_scroll_controller.dart';
import 'terminal_view_binding.dart';

/// Visual diameter of a selection handle in logical pixels.
const _handleSize = 20.0;

/// Transparent hit slop around each handle so it stays grabbable
/// without covering more of the terminal than necessary.
const _hitSlop = 6.0;

/// Whether the current platform renders touch selection handles.
///
/// Handles are a mobile-only affordance. Desktop platforms keep their
/// existing selection behavior with no handle layer at all.
bool get _touchHandlesEnabled => switch (defaultTargetPlatform) {
  .android || .iOS => true,
  .fuchsia || .linux || .macOS || .windows => false,
};

/// Overlays draggable selection handles on top of the terminal.
///
/// On touch platforms (Android, iOS) this renders an Android-style drop
/// handle below each end of the active selection. Dragging a handle moves
/// that endpoint while the other endpoint stays anchored, driven through
/// the [TerminalViewBinding] selection gesture interface. On all other
/// platforms [build] returns [child] untouched.
///
/// Handle positions are derived from the selection endpoints' viewport
/// coordinates; an endpoint scrolled outside the viewport hides its
/// handle. The layer listens to the controller, the terminal, and the
/// scroll controller to track selection, content, and viewport changes.
@internal
class TerminalSelectionHandles extends StatefulWidget {
  final Widget child;
  final TerminalController controller;
  final TerminalViewBinding binding;
  final CellMetrics metrics;
  final TerminalScrollController scrollController;
  final TerminalTheme theme;
  final int visibleRows;

  const TerminalSelectionHandles({
    super.key,
    required this.child,
    required this.controller,
    required this.binding,
    required this.metrics,
    required this.scrollController,
    required this.theme,
    this.visibleRows = 0,
  });

  @override
  State<TerminalSelectionHandles> createState() =>
      _TerminalSelectionHandlesState();
}

/// Which selection endpoint a handle controls, in top-left to
/// bottom-right screen order.
enum _HandleEnd { first, last }

final class _HandleDrag {
  /// Offset from the finger to the dragged endpoint's cell center,
  /// captured at drag start so the endpoint does not jump under the
  /// finger when the handle (drawn below the cell) is grabbed.
  final Offset grabDelta;

  /// Current drag target in layer-local pixels.
  Offset target;

  /// Unclamped cell under [target]; may be outside the viewport.
  Position cell;

  /// Last viewport-clamped cell reported to the binding.
  Position sentCell;

  _HandleDrag({
    required this.grabDelta,
    required this.target,
    required this.cell,
    required this.sentCell,
  });
}

final class _HandleLayout {
  /// Top-left endpoint in screen coordinates (scrollback included).
  final Position firstScreen;

  /// Bottom-right endpoint in screen coordinates.
  final Position lastScreen;

  /// Viewport position of the top-left endpoint, or null when it is
  /// scrolled outside the visible area.
  final Position? firstViewport;

  /// Viewport position of the bottom-right endpoint, or null when it is
  /// scrolled outside the visible area.
  final Position? lastViewport;

  /// Cell span of the bottom-right endpoint (2 for a wide character) so
  /// the trailing handle anchors at the glyph's true right edge.
  final int lastSpan;

  const _HandleLayout({
    required this.firstScreen,
    required this.lastScreen,
    required this.firstViewport,
    required this.lastViewport,
    required this.lastSpan,
  });
}

class _TerminalSelectionHandlesState extends State<TerminalSelectionHandles> {
  _HandleDrag? _drag;
  Timer? _autoScrollTimer;
  var _subscribed = false;
  var _rebuildQueued = false;
  var _decorated = false;

  TerminalViewBinding get _binding => widget.binding;

  Color get _fillColor {
    final theme = widget.theme;
    return theme.selection.background?.fixedColor ??
        theme.cursor.color?.fixedColor ??
        theme.foreground;
  }

  @override
  Widget build(BuildContext context) {
    // Platform short-circuit: desktop gets the untouched child so the
    // handle layer adds zero widgets and zero per-frame work there.
    if (!_touchHandlesEnabled) return widget.child;

    final layout = _resolveLayout();
    _decorated = layout != null;
    return Stack(
      fit: .passthrough,
      clipBehavior: .none,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (layout != null) ...[
          if (layout.firstViewport != null)
            _buildHandle(end: .first, cell: layout.firstViewport!, span: 1),
          if (layout.lastViewport != null)
            _buildHandle(
              end: .last,
              cell: layout.lastViewport!,
              span: layout.lastSpan,
            ),
        ],
      ],
    );
  }

  @override
  void didUpdateWidget(TerminalSelectionHandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_touchHandlesEnabled) return;

    if (widget.controller != oldWidget.controller ||
        widget.binding != oldWidget.binding ||
        widget.scrollController != oldWidget.scrollController) {
      _unsubscribe(oldWidget);
      _subscribe();
      _cancelDrag();
    }
    if (widget.metrics != oldWidget.metrics) _cancelDrag();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    if (_subscribed) _unsubscribe(widget);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_touchHandlesEnabled) _subscribe();
  }

  void _autoScrollTick(Timer timer) {
    final drag = _drag;
    // A cleared selection removes the handle mid-drag without a pan-end
    // callback, so the timer must also stop itself in that case.
    if (drag == null || !widget.controller.hasSelection) {
      _stopAutoScroll();
      return;
    }
    _binding.updateSelectionAutoscroll(
      cell: drag.cell,
      localPosition: drag.target,
      rectangle: false,
    );
  }

  Positioned _buildHandle({
    required _HandleEnd end,
    required Position cell,
    required int span,
  }) {
    final metrics = widget.metrics;
    // The first handle hangs below-left of the endpoint cell; the last
    // handle hangs below-right, matching Android text selection.
    final anchor = end == .first
        ? Offset(
            cell.col * metrics.cellWidth,
            (cell.row + 1) * metrics.cellHeight,
          )
        : Offset(
            (cell.col + span) * metrics.cellWidth,
            (cell.row + 1) * metrics.cellHeight,
          );
    final left = end == .first
        ? anchor.dx - _handleSize - _hitSlop
        : anchor.dx - _hitSlop;

    return Positioned(
      left: left,
      top: anchor.dy - _hitSlop,
      width: _handleSize + _hitSlop * 2,
      height: _handleSize + _hitSlop * 2,
      child: GestureDetector(
        behavior: .opaque,
        onPanStart: (details) => _startHandleDrag(end, details),
        onPanUpdate: _updateHandleDrag,
        onPanEnd: (_) => _endHandleDrag(),
        onPanCancel: _endHandleDrag,
        child: Padding(
          padding: const EdgeInsets.all(_hitSlop),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _fillColor,
              borderRadius: _radiusFor(end),
              border: Border.all(color: _strokeColor(_fillColor)),
            ),
          ),
        ),
      ),
    );
  }

  void _cancelDrag() {
    _drag = null;
    _stopAutoScroll();
  }

  void _endHandleDrag() {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    _stopAutoScroll();
    _binding.handleSelectionRelease(drag.sentCell);
  }

  /// Rebuilds when the selection, terminal content, or viewport changes.
  ///
  /// Terminal and scroll notifications can fire during layout (the render
  /// box resizes the terminal and corrects scroll offsets in
  /// performLayout), where setState is not allowed; those are deferred to
  /// the end of the frame.
  void _requestRebuild() {
    if (!mounted) return;
    // Skip the rebuild while nothing is decorated and there is still no
    // selection; otherwise every output batch would rebuild the layer.
    if (!_decorated && !widget.controller.hasSelection) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildQueued) return;
      _rebuildQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildQueued = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// Resolves the current selection into handle geometry, or null when
  /// there is no selection to decorate.
  _HandleLayout? _resolveLayout() {
    final metrics = widget.metrics;
    if (metrics.cellWidth <= 0 || metrics.cellHeight <= 0) return null;

    final selection = _binding.terminal.selection;
    if (selection == null) return null;

    final startScreen = selection.start.positionIn(.screen);
    final endScreen = selection.end.positionIn(.screen);
    if (startScreen == null || endScreen == null) return null;

    // Selection endpoints preserve gesture direction; order them so the
    // first handle is always the top-left end.
    final startIsFirst =
        startScreen.row < endScreen.row ||
        (startScreen.row == endScreen.row && startScreen.col <= endScreen.col);
    final (firstRef, lastRef) = startIsFirst
        ? (selection.start, selection.end)
        : (selection.end, selection.start);

    return _HandleLayout(
      firstScreen: startIsFirst ? startScreen : endScreen,
      lastScreen: startIsFirst ? endScreen : startScreen,
      firstViewport: _visibleViewportPosition(firstRef),
      lastViewport: _visibleViewportPosition(lastRef),
      lastSpan: lastRef.isWide ? 2 : 1,
    );
  }

  void _startHandleDrag(_HandleEnd end, DragStartDetails details) {
    final layout = _resolveLayout();
    if (layout == null) return;

    final draggedCell = end == .first
        ? layout.firstViewport
        : layout.lastViewport;
    final anchor = end == .first ? layout.lastScreen : layout.firstScreen;
    if (draggedCell == null) return;

    final box = context.findRenderObject();
    if (box is! RenderBox) return;

    final metrics = widget.metrics;
    final local = box.globalToLocal(details.globalPosition);
    final target = Offset(
      (draggedCell.col + 0.5) * metrics.cellWidth,
      (draggedCell.row + 0.5) * metrics.cellHeight,
    );

    _drag = _HandleDrag(
      grabDelta: target - local,
      target: target,
      cell: draggedCell,
      sentCell: draggedCell,
    );
    // Anchor the gesture at the fixed endpoint; subsequent drag events
    // move only the grabbed end. The tap-to-clear path in the gesture
    // detector never fires because the handle consumes the pointer.
    _binding.startSelectionHandleDrag(anchor: anchor, localPosition: target);
  }

  void _startAutoScroll() {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      _autoScrollTick,
    );
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _subscribe() {
    widget.controller.addListener(_requestRebuild);
    widget.binding.terminal.addListener(_requestRebuild);
    widget.scrollController.addListener(_requestRebuild);
    _subscribed = true;
  }

  void _unsubscribe(TerminalSelectionHandles target) {
    target.controller.removeListener(_requestRebuild);
    target.binding.terminal.removeListener(_requestRebuild);
    target.scrollController.removeListener(_requestRebuild);
    _subscribed = false;
  }

  void _updateHandleDrag(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;

    final box = context.findRenderObject();
    if (box is! RenderBox) return;

    final target = box.globalToLocal(details.globalPosition) + drag.grabDelta;
    final cell = widget.metrics.cellAt(target);
    drag
      ..target = target
      ..cell = cell;

    final rows = widget.visibleRows;
    if (rows > 0 && (cell.row < 0 || cell.row >= rows)) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }

    final clampedRow = rows > 0 ? _clampInt(cell.row, 0, rows - 1) : cell.row;
    final clamped = Position(row: clampedRow, col: cell.col);
    if (clamped == drag.sentCell) return;
    drag.sentCell = clamped;
    _binding.updateSelectionDrag(
      cell: clamped,
      localPosition: target,
      rectangle: false,
    );
  }

  /// Viewport position for [ref], or null when it is outside the
  /// currently visible rows.
  Position? _visibleViewportPosition(GridRef ref) {
    final position = ref.positionIn(.viewport);
    if (position == null) return null;
    if (position.row < 0 || position.col < 0) return null;
    final rows = widget.visibleRows;
    if (rows > 0 && position.row >= rows) return null;
    return position;
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Rounded on all corners except the one touching the selection edge,
  /// producing the Android-style teardrop pointing at the endpoint.
  static BorderRadius _radiusFor(_HandleEnd end) {
    const round = Radius.circular(_handleSize);
    return end == .first
        ? const BorderRadius.only(
            topLeft: round,
            bottomLeft: round,
            bottomRight: round,
          )
        : const BorderRadius.only(
            topRight: round,
            bottomLeft: round,
            bottomRight: round,
          );
  }

  /// Thin outline that keeps the handle visible over both light and dark
  /// terminal content regardless of the fill color.
  static Color _strokeColor(Color fill) => fill.computeLuminance() > 0.5
      ? const Color(0x66000000)
      : const Color(0xB3FFFFFF);
}
