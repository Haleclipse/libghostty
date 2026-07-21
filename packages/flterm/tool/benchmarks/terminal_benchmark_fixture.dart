import 'dart:convert';
import 'dart:typed_data';

/// Deterministic input shared by terminal performance workloads.
///
/// Fixture generation belongs outside timed benchmark steps. Keeping it here
/// also ensures that baseline and changed revisions consume identical bytes.
abstract final class TerminalBenchmarkFixture {
  static final _controllerLine = utf8.encode(
    '\x1b[38;5;39mINFO\x1b[0m '
    'build completed in 42 ms; 17 checks passed\r\n',
  );

  /// Creates lightly styled line output with exactly [length] bytes.
  static Uint8List controllerOutput(int length) {
    if (length <= 0) throw RangeError.range(length, 1, null, 'length');
    final output = Uint8List(length);
    var offset = 0;
    while (offset + _controllerLine.length <= output.length) {
      output.setRange(offset, offset + _controllerLine.length, _controllerLine);
      offset += _controllerLine.length;
    }
    output.fillRange(offset, output.length, 0x20);
    return output;
  }

  /// Creates an update that dirties every row with representative text.
  ///
  /// [columns] must be at least 80 so the ASCII, wide, and combining fixture
  /// remains on its addressed row rather than wrapping into the next row.
  static Uint8List fullFrame({
    required int columns,
    required int rows,
    required int variant,
  }) {
    _validateDimensions(columns, rows, variant);
    return _frame(
      columns: columns,
      dirtyRows: rows,
      variant: variant,
      full: true,
    );
  }

  /// Creates an update that dirties the first [dirtyRows] terminal rows.
  static Uint8List partialFrame({
    required int columns,
    required int rows,
    required int dirtyRows,
    required int variant,
  }) {
    _validateDimensions(columns, rows, variant);
    if (dirtyRows <= 0 || dirtyRows > rows) {
      throw RangeError.range(dirtyRows, 1, rows, 'dirtyRows');
    }
    return _frame(
      columns: columns,
      dirtyRows: dirtyRows,
      variant: variant,
      full: false,
    );
  }

  static Uint8List _frame({
    required int columns,
    required int dirtyRows,
    required int variant,
    required bool full,
  }) {
    final buffer = StringBuffer();
    for (var row = 0; row < dirtyRows; row++) {
      final content = full
          ? 'row $row frame $variant ASCII wide 界 combining e\u0301'
          : 'prompt row $row frame $variant';
      buffer
        ..write('\x1b[${row + 1};1H')
        ..write(content.padRight(columns - 8));
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static void _validateDimensions(int columns, int rows, int variant) {
    if (columns < 80) throw RangeError.range(columns, 80, null, 'columns');
    if (rows <= 0) throw RangeError.range(rows, 1, null, 'rows');
    if (variant < 0) throw RangeError.range(variant, 0, null, 'variant');
  }
}
