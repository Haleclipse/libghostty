@Tags(['benchmark', 'ffi'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flterm/src/foundation/cell_metrics.dart';
import 'package:flterm/src/foundation/terminal_render_observer.dart';
import 'package:flterm/src/foundation/terminal_theme.dart';
import 'package:flterm/src/rendering/terminal_render_cache.dart';
import 'package:flterm/src/rendering/terminal_renderer.dart';
import 'package:flutter/rendering.dart' show ViewportOffset;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libghostty/libghostty.dart' show Terminal;

import '../../test/rendering/helpers/font_loader.dart';
import 'benchmark_harness.dart';
import 'terminal_benchmark_fixture.dart';

void main() {
  group('Terminal frame benchmark', () {
    group('build and paint', () {
      testWidgets('measures a clean 80 by 24 frame', (tester) async {
        final report = await _runFrameBenchmark(
          tester,
          name: 'frame-render --mode=clean --size=80x24',
        );

        stdout.writeln(BenchmarkOutput.frame(report.format(index: 1)));

        expect(report.sampleCount, _sampleCount);
      });

      testWidgets('measures three dirty rows in an 80 by 24 frame', (
        tester,
      ) async {
        final report = await _runFrameBenchmark(
          tester,
          name: 'frame-render --mode=partial-3 --size=80x24',
          payloadFor: (variant) => TerminalBenchmarkFixture.partialFrame(
            columns: _cols,
            rows: _rows,
            dirtyRows: 3,
            variant: variant,
          ),
        );

        stdout.writeln(BenchmarkOutput.frame(report.format(index: 2)));

        expect(report.sampleCount, _sampleCount);
      });

      testWidgets('measures a full 80 by 24 frame', (tester) async {
        final report = await _runFrameBenchmark(
          tester,
          name: 'frame-render --mode=full --size=80x24',
          payloadFor: (variant) => TerminalBenchmarkFixture.fullFrame(
            columns: _cols,
            rows: _rows,
            variant: variant,
          ),
        );

        stdout.writeln(BenchmarkOutput.frame(report.format(index: 3)));

        expect(report.sampleCount, _sampleCount);
      });
    });
  });
}

const _cols = 80;
const _rows = 24;
const _sampleCount = 100;
const _warmupCount = 10;
const _metrics = CellMetrics(cellWidth: 8, cellHeight: 16, baseline: 12);

Future<BenchmarkReport> _runFrameBenchmark(
  WidgetTester tester, {
  required String name,
  Uint8List Function(int variant)? payloadFor,
}) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadBundledFonts();
  final terminal = Terminal(cols: _cols, rows: _rows);
  final renderCache = TerminalRenderCache();
  addTearDown(terminal.dispose);
  addTearDown(renderCache.dispose);
  await tester.pumpWidget(_terminalWidget(terminal, renderCache));
  terminal.write(
    TerminalBenchmarkFixture.fullFrame(columns: _cols, rows: _rows, variant: 0),
  );
  await tester.pump();
  final renderBox = tester.renderObject<TerminalRenderBox>(
    find.byType(TerminalRenderer),
  );
  final payloads = [
    if (payloadFor != null)
      for (var sample = 1; sample <= _warmupCount + _sampleCount; sample++)
        payloadFor(sample),
  ];
  var payloadIndex = 0;
  final runner = BenchmarkRunner(
    warmupCount: _warmupCount,
    sampleCount: _sampleCount,
  );
  final BenchmarkCallback? prepare = payloadFor == null
      ? null
      : () {
          terminal.write(payloads[payloadIndex++]);
          if (!renderBox.debugNeedsPaint) {
            throw StateError(
              'Frame workload did not schedule paint after terminal input.',
            );
          }
        };

  return runner.run(name: name, prepare: prepare, step: () => tester.pump());
}

Widget _terminalWidget(Terminal terminal, TerminalRenderCache renderCache) {
  return Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: SizedBox(
        width: _cols * _metrics.cellWidth,
        height: _rows * _metrics.cellHeight,
        child: TerminalRenderer(
          terminal: terminal,
          theme: TerminalTheme.dark(),
          metrics: _metrics,
          offset: ViewportOffset.zero(),
          renderObserver: const _FocusedRenderObserver(),
          renderCache: renderCache,
        ),
      ),
    ),
  );
}

final class _FocusedRenderObserver implements TerminalRenderObserver {
  @override
  bool get hasFocus => true;

  const _FocusedRenderObserver();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
