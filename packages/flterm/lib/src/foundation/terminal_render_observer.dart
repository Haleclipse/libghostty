import 'package:flutter/foundation.dart';

/// Observable focus state for the rendering layer.
///
/// Implemented by [TerminalController] and consumed by painters that need
/// to react to focus changes or selection updates without depending on
/// the full controller API.
///
/// Listeners are notified when [hasFocus] changes, triggering repaint of
/// cursor state.
abstract class TerminalRenderObserver implements Listenable {
  /// Whether the terminal view has keyboard focus.
  ///
  /// Painters use this to adjust cursor rendering: a focused terminal
  /// draws a filled cursor, while an unfocused terminal draws a hollow
  /// block outline.
  bool get hasFocus;

  /// Called immediately before the renderer resizes the terminal grid.
  ///
  /// Gives the observer a chance to drop idle tracked state (e.g. the
  /// selection gesture's repeat-detection pin left behind by a tap). A
  /// tracked pin on a viewport row anchors that row during the resize
  /// reflow: a shrinking grid then pushes rows into scrollback instead
  /// of trimming blank rows, and the following grow appends blank rows
  /// instead of pulling them back — permanently inflating the grid
  /// across a soft-keyboard show/hide cycle.
  void willResizeGrid() {}
}
