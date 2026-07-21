import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/benchmark_harness.dart';

void main() {
  group('BenchmarkRunner', () {
    group('constructor', () {
      test('rejects a negative warmup count', () {
        expect(
          () => BenchmarkRunner(warmupCount: -1, sampleCount: 1),
          throwsRangeError,
        );
      });

      test('rejects a non-positive sample count', () {
        expect(
          () => BenchmarkRunner(warmupCount: 0, sampleCount: 0),
          throwsRangeError,
        );
      });
    });

    group('run', () {
      test('runs setup, warmups, samples, and teardown in order', () async {
        final events = <String>[];
        final clock = _FakeClock();
        final runner = BenchmarkRunner(
          warmupCount: 1,
          sampleCount: 2,
          clock: clock.read,
        );

        await runner.run(
          name: 'lifecycle',
          setup: () => events.add('setup'),
          step: () {
            events.add('step');
            clock.advance(10);
          },
          teardown: () => events.add('teardown'),
        );

        expect(events, ['setup', 'step', 'step', 'step', 'teardown']);
      });

      test('excludes warmup durations from the report', () async {
        final clock = _FakeClock();
        final step = _SequenceStep(clock, [5000, 100, 200]);
        final runner = BenchmarkRunner(
          warmupCount: 1,
          sampleCount: 2,
          clock: clock.read,
        );

        final result = await runner.run(name: 'warmup', step: step.call);

        expect(result.durationsMicroseconds, [100, 200]);
      });

      test('runs preparation before every warmup and measured step', () async {
        final events = <String>[];
        final clock = _FakeClock();
        final runner = BenchmarkRunner(
          warmupCount: 1,
          sampleCount: 2,
          clock: clock.read,
        );

        await runner.run(
          name: 'prepare-order',
          prepare: () => events.add('prepare'),
          step: () {
            events.add('step');
            clock.advance(10);
          },
        );

        expect(events, [
          'prepare',
          'step',
          'prepare',
          'step',
          'prepare',
          'step',
        ]);
      });

      test('excludes preparation durations from samples', () async {
        final clock = _FakeClock();
        final step = _SequenceStep(clock, [100, 200]);
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 2,
          clock: clock.read,
        );

        final result = await runner.run(
          name: 'prepare-timing',
          prepare: () => clock.advance(5000),
          step: step.call,
        );

        expect(result.durationsMicroseconds, [100, 200]);
      });

      test('runs teardown when a measured step fails', () async {
        final events = <String>[];
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 1,
          clock: _FakeClock().read,
        );

        final result = runner.run(
          name: 'failure',
          setup: () => events.add('setup'),
          step: () {
            events.add('step');
            throw StateError('step failed');
          },
          teardown: () => events.add('teardown'),
        );

        await expectLater(result, throwsStateError);
        expect(events, ['setup', 'step', 'teardown']);
      });

      test('does not run teardown when setup fails', () async {
        final events = <String>[];
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 1,
          clock: _FakeClock().read,
        );

        final result = runner.run(
          name: 'setup-failure',
          setup: () {
            events.add('setup');
            throw StateError('setup failed');
          },
          step: () => events.add('step'),
          teardown: () => events.add('teardown'),
        );

        await expectLater(result, throwsStateError);
        expect(events, ['setup']);
      });

      test('rejects an empty benchmark name', () async {
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 1,
          clock: _FakeClock().read,
        );

        final result = runner.run(name: '  ', step: () {});

        await expectLater(result, throwsArgumentError);
      });

      test('rejects a non-positive byte count', () async {
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 1,
          clock: _FakeClock().read,
        );

        final result = runner.run(
          name: 'bytes',
          step: () {},
          bytesPerSample: 0,
        );

        await expectLater(result, throwsRangeError);
      });

      test('rejects a sample below the clock resolution', () async {
        final runner = BenchmarkRunner(
          warmupCount: 0,
          sampleCount: 1,
          clock: _FakeClock().read,
        );

        final result = runner.run(name: 'too-fast', step: () {});

        await expectLater(
          result,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('clock resolution'),
            ),
          ),
        );
      });
    });
  });

  group('BenchmarkReport', () {
    group('fromSamples', () {
      test('computes the arithmetic mean', () {
        final result = BenchmarkReport.fromSamples(
          name: 'statistics',
          durationsMicroseconds: [1000, 2000, 3000, 4000],
        );

        expect(result.meanMicroseconds, 2500);
      });

      test('computes the sample standard deviation', () {
        final result = BenchmarkReport.fromSamples(
          name: 'statistics',
          durationsMicroseconds: [1000, 2000, 3000, 4000],
        );

        expect(result.standardDeviationMicroseconds, closeTo(1290.994, 0.001));
      });

      test('uses zero deviation for one sample', () {
        final result = BenchmarkReport.fromSamples(
          name: 'single',
          durationsMicroseconds: [1000],
        );

        expect(result.standardDeviationMicroseconds, 0);
      });

      test('computes nearest-rank percentiles', () {
        final result = BenchmarkReport.fromSamples(
          name: 'percentiles',
          durationsMicroseconds: [1000, 2000, 3000, 4000],
        );

        final percentiles = (
          p50: result.p50Microseconds,
          p95: result.p95Microseconds,
          p99: result.p99Microseconds,
        );

        expect(percentiles, (p50: 2000, p95: 4000, p99: 4000));
      });

      test('computes range independently of input order', () {
        final result = BenchmarkReport.fromSamples(
          name: 'range',
          durationsMicroseconds: [3000, 1000, 4000, 2000],
        );

        final range = (
          min: result.minMicroseconds,
          max: result.maxMicroseconds,
        );

        expect(range, (min: 1000, max: 4000));
      });

      test('does not mutate the input samples', () {
        final samples = [3000, 1000, 2000];

        BenchmarkReport.fromSamples(
          name: 'immutable-input',
          durationsMicroseconds: samples,
        );

        expect(samples, [3000, 1000, 2000]);
      });

      test('rejects an empty sample list', () {
        expect(
          () => BenchmarkReport.fromSamples(
            name: 'empty',
            durationsMicroseconds: const [],
          ),
          throwsArgumentError,
        );
      });

      test('rejects a non-positive duration', () {
        expect(
          () => BenchmarkReport.fromSamples(
            name: 'invalid-duration',
            durationsMicroseconds: const [0],
          ),
          throwsRangeError,
        );
      });
    });

    group('throughput', () {
      test('uses mean duration for mebibytes per second', () {
        final result = BenchmarkReport.fromSamples(
          name: 'throughput',
          durationsMicroseconds: [2000, 3000],
          bytesPerSample: 1024 * 1024,
        );

        expect(result.mebibytesPerSecond, 400);
      });

      test('is absent without a byte count', () {
        final result = BenchmarkReport.fromSamples(
          name: 'latency',
          durationsMicroseconds: [1000],
        );

        expect(result.mebibytesPerSecond, isNull);
      });
    });

    group('format', () {
      test('uses hyperfine-style timing output', () {
        final result = BenchmarkReport.fromSamples(
          name: 'controller-write --chunk-size=4-kib',
          durationsMicroseconds: [1000, 2000, 3000, 4000],
          bytesPerSample: 1024 * 1024,
        );

        final output = result.format(index: 1);

        expect(
          output,
          'Benchmark 1: controller-write --chunk-size=4-kib\n'
          '  Time (mean ± σ):     2.500 ms ± 1.291 ms\n'
          '  Range (min … max):   1.000 ms … 4.000 ms    4 runs\n'
          '  Percentiles:         p50 2.000 ms | p95 4.000 ms | '
          'p99 4.000 ms\n'
          '  Throughput:          400.0 MiB/s',
        );
      });

      test('omits throughput without a byte count', () {
        final result = BenchmarkReport.fromSamples(
          name: 'frame-render --mode=full',
          durationsMicroseconds: [1000],
        );

        final output = result.format(index: 1);

        expect(output, isNot(contains('Throughput')));
      });
    });
  });

  group('BenchmarkOutput', () {
    group('frame', () {
      test('wraps a report in extraction markers', () {
        final result = BenchmarkOutput.frame('Benchmark 1: workload');

        expect(
          result,
          'FLTERM_BENCHMARK_REPORT_BEGIN\n'
          'Benchmark 1: workload\n'
          'FLTERM_BENCHMARK_REPORT_END',
        );
      });

      test('rejects an empty report', () {
        expect(() => BenchmarkOutput.frame('  '), throwsArgumentError);
      });
    });

    group('extract', () {
      test('removes Flutter shell prefixes', () {
        const output =
            'runner noise\n'
            'Shell: FLTERM_BENCHMARK_REPORT_BEGIN\n'
            'Shell: Benchmark 1: workload\n'
            'Shell:   Time (mean ± σ): 1.000 ms ± 0.100 ms\n'
            'Shell: FLTERM_BENCHMARK_REPORT_END\n'
            'runner complete';

        final result = BenchmarkOutput.extract(output);

        expect(
          result,
          'Benchmark 1: workload\n'
          '  Time (mean ± σ): 1.000 ms ± 0.100 ms',
        );
      });

      test('separates multiple reports', () {
        const output =
            'FLTERM_BENCHMARK_REPORT_BEGIN\n'
            'Benchmark 1: first\n'
            'FLTERM_BENCHMARK_REPORT_END\n'
            'FLTERM_BENCHMARK_REPORT_BEGIN\n'
            'Benchmark 2: second\n'
            'FLTERM_BENCHMARK_REPORT_END';

        final result = BenchmarkOutput.extract(output);

        expect(result, 'Benchmark 1: first\n\nBenchmark 2: second');
      });

      test('rejects output without a report', () {
        expect(
          () => BenchmarkOutput.extract('runner noise'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('complete benchmark report'),
            ),
          ),
        );
      });

      test('rejects an unterminated report', () {
        const output = 'FLTERM_BENCHMARK_REPORT_BEGIN\nBenchmark 1: partial';

        expect(
          () => BenchmarkOutput.extract(output),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('end marker'),
            ),
          ),
        );
      });

      test('rejects an end marker without a report', () {
        expect(
          () => BenchmarkOutput.extract('FLTERM_BENCHMARK_REPORT_END'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('start marker'),
            ),
          ),
        );
      });

      test('rejects a nested report', () {
        const output =
            'FLTERM_BENCHMARK_REPORT_BEGIN\n'
            'FLTERM_BENCHMARK_REPORT_BEGIN';

        expect(
          () => BenchmarkOutput.extract(output),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('nested start marker'),
            ),
          ),
        );
      });
    });
  });
}

final class _FakeClock {
  var _microseconds = 0;

  int read() => _microseconds;

  void advance(int microseconds) {
    _microseconds += microseconds;
  }
}

final class _SequenceStep {
  final _FakeClock clock;
  final List<int> durations;
  var _index = 0;

  _SequenceStep(this.clock, this.durations);

  void call() {
    clock.advance(durations[_index]);
    _index++;
  }
}
