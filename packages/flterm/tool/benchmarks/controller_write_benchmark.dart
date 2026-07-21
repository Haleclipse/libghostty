@Tags(['benchmark', 'ffi'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flterm/flterm.dart' show TerminalConfig, TerminalController;
import 'package:flutter_test/flutter_test.dart';

import 'benchmark_harness.dart';
import 'terminal_benchmark_fixture.dart';

void main() {
  group('TerminalController.write benchmark', () {
    group('write', () {
      test('measures sustained 4 KiB terminal output', () async {
        final report = await _benchmarkControllerWrites(
          name: 'controller-write --chunk-size=4-kib --bytes=4-mib',
          payload: TerminalBenchmarkFixture.controllerOutput(4 * 1024),
        );

        stdout.writeln(BenchmarkOutput.frame(report.format(index: 1)));

        expect(report.sampleCount, _sampleCount);
      });

      test('measures 1 MiB terminal output bursts', () async {
        final report = await _benchmarkControllerWrites(
          name: 'controller-write --chunk-size=1-mib --bytes=4-mib',
          payload: TerminalBenchmarkFixture.controllerOutput(1024 * 1024),
        );

        stdout.writeln(BenchmarkOutput.frame(report.format(index: 2)));

        expect(report.sampleCount, _sampleCount);
      });
    });
  });
}

const _bytesPerSample = 4 * 1024 * 1024;
const _sampleCount = 100;
const _warmupCount = 5;

Future<BenchmarkReport> _benchmarkControllerWrites({
  required String name,
  required Uint8List payload,
}) {
  late TerminalController controller;
  final writesPerSample = _bytesPerSample ~/ payload.length;
  final runner = BenchmarkRunner(
    warmupCount: _warmupCount,
    sampleCount: _sampleCount,
  );

  return runner.run(
    name: name,
    setup: () {
      controller = TerminalController(
        config: const TerminalConfig(scrollbackLimit: 0),
      );
    },
    step: () => _writeBatch(controller, payload, writesPerSample),
    teardown: () => controller.dispose(),
    bytesPerSample: payload.length * writesPerSample,
  );
}

void _writeBatch(TerminalController controller, Uint8List payload, int writes) {
  for (var write = 0; write < writes; write++) {
    controller.write(payload);
  }
}
