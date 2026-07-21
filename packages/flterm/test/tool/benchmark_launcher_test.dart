import 'dart:convert' show LineSplitter;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/benchmark_harness.dart';
import '../../tool/benchmarks/benchmark_launcher.dart';

void main() {
  group('runBenchmarkCommand', () {
    String shellOutput(String report) {
      return LineSplitter.split(
        BenchmarkOutput.frame(report),
      ).map((line) => 'Shell: $line').join('\n');
    }

    BenchmarkProcessResult successfulResult(String report) {
      return (exitCode: 0, stdout: shellOutput(report), stderr: '');
    }

    group('selection', () {
      test('runs the controller write benchmark', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('controller report'),
        );

        await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(processRunner.arguments.single, [
          'test',
          '--no-track-widget-creation',
          'tool/benchmarks/controller_write_benchmark.dart',
          '--machine',
        ]);
      });

      test('runs the frame render benchmark', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('frame report'),
        );

        await runBenchmarkCommand(const [
          'frame-render',
        ], processRunner: processRunner.call);

        expect(processRunner.arguments.single, [
          'test',
          '--no-track-widget-creation',
          'tool/benchmarks/frame_render_benchmark.dart',
          '--machine',
        ]);
      });

      test('runs all benchmarks sequentially', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('benchmark report'),
        );

        await runBenchmarkCommand(const [
          'all',
        ], processRunner: processRunner.call);

        expect(processRunner.arguments, [
          [
            'test',
            '--no-track-widget-creation',
            'tool/benchmarks/controller_write_benchmark.dart',
            '--machine',
          ],
          [
            'test',
            '--no-track-widget-creation',
            'tool/benchmarks/frame_render_benchmark.dart',
            '--machine',
          ],
        ]);
      });
    });

    group('success', () {
      test('returns clean benchmark reports', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('Benchmark 1: controller-write'),
        );

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.stdout, 'Benchmark 1: controller-write');
      });

      test('separates reports from multiple suites', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('Benchmark 1: workload'),
        );

        final result = await runBenchmarkCommand(const [
          'all',
        ], processRunner: processRunner.call);

        expect(result.stdout, 'Benchmark 1: workload\n\nBenchmark 1: workload');
      });

      test('uses a successful exit code', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('benchmark report'),
        );

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.exitCode, 0);
      });
    });

    group('failure', () {
      test('propagates the child exit code', () async {
        final processRunner = _RecordingProcessRunner(const (
          exitCode: 7,
          stdout: 'child output',
          stderr: 'child error',
        ));

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.exitCode, 7);
      });

      test('preserves the child standard output', () async {
        final processRunner = _RecordingProcessRunner(const (
          exitCode: 7,
          stdout: 'child output',
          stderr: 'child error',
        ));

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.stdout, 'child output');
      });

      test('preserves the child standard error', () async {
        final processRunner = _RecordingProcessRunner(const (
          exitCode: 7,
          stdout: 'child output',
          stderr: 'child error',
        ));

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.stderr, 'child error');
      });

      test('rejects successful output without a report', () async {
        final processRunner = _RecordingProcessRunner(const (
          exitCode: 0,
          stdout: 'runner noise',
          stderr: '',
        ));

        final result = await runBenchmarkCommand(const [
          'controller-write',
        ], processRunner: processRunner.call);

        expect(result.stderr, contains('complete benchmark report'));
      });
    });

    group('arguments', () {
      test('rejects an unknown benchmark', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('benchmark report'),
        );

        final result = await runBenchmarkCommand(const [
          'unknown',
        ], processRunner: processRunner.call);

        expect(result.exitCode, 64);
      });

      test('shows usage for help', () async {
        final processRunner = _RecordingProcessRunner(
          successfulResult('benchmark report'),
        );

        final result = await runBenchmarkCommand(const [
          '--help',
        ], processRunner: processRunner.call);

        expect(result.stdout, contains('controller-write|frame-render|all'));
      });
    });
  });
}

final class _RecordingProcessRunner {
  final BenchmarkProcessResult result;
  final arguments = <List<String>>[];

  _RecordingProcessRunner(this.result);

  Future<BenchmarkProcessResult> call(List<String> processArguments) async {
    arguments.add(processArguments);
    return result;
  }
}
