import 'dart:async';
import 'dart:convert' show LineSplitter;
import 'dart:math' show sqrt;

String _duration(num microseconds, _DurationScale scale) {
  return '${(microseconds / scale.divisor).toStringAsFixed(3)} ${scale.unit}';
}

_DurationScale _durationScale(double microseconds) {
  return switch (microseconds) {
    < 1000 => (divisor: 1, unit: 'µs'),
    < Duration.microsecondsPerSecond => (divisor: 1000, unit: 'ms'),
    _ => (divisor: Duration.microsecondsPerSecond.toDouble(), unit: 's'),
  };
}

int _percentile(List<int> sorted, double percentile) {
  return sorted[(sorted.length * percentile).ceil() - 1];
}

BenchmarkClock _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMicroseconds;
}

/// Work performed before, during, or after a benchmark run.
typedef BenchmarkCallback = FutureOr<void> Function();

/// Reads a monotonic timestamp in microseconds.
typedef BenchmarkClock = int Function();

typedef _DurationScale = ({double divisor, String unit});

/// Frames benchmark reports so a launcher can separate them from test output.
///
/// Flutter's machine test reporter emits benchmark prints alongside protocol
/// events and prefixes each printed line with `Shell: `. Framing keeps report
/// extraction independent of test names, progress messages, and incidental
/// logs.
///
/// ```dart
/// stdout.writeln(BenchmarkOutput.frame(report.format(index: 1)));
/// ```
final class BenchmarkOutput {
  static const _beginMarker = 'FLTERM_BENCHMARK_REPORT_BEGIN';
  static const _endMarker = 'FLTERM_BENCHMARK_REPORT_END';
  static const _shellPrefix = 'Shell: ';

  /// Wraps a non-empty [report] in stable extraction markers.
  static String frame(String report) {
    final normalizedReport = report.trim();
    if (normalizedReport.isEmpty) {
      throw ArgumentError.value(report, 'report', 'must not be empty');
    }
    return '$_beginMarker\n$normalizedReport\n$_endMarker';
  }

  /// Extracts complete framed reports from Flutter process output.
  ///
  /// Machine-reporter lines outside report markers are ignored. Flutter's
  /// `Shell: ` prefix is removed while report indentation is preserved.
  static String extract(String processOutput) {
    final reports = <String>[];
    List<String>? reportLines;

    for (final processLine in LineSplitter.split(processOutput)) {
      final line = processLine.startsWith(_shellPrefix)
          ? processLine.substring(_shellPrefix.length)
          : processLine;
      switch (line) {
        case _beginMarker:
          if (reportLines != null) {
            throw const FormatException(
              'Benchmark output contains a nested start marker.',
            );
          }
          reportLines = <String>[];
        case _endMarker:
          final completedLines = reportLines;
          if (completedLines == null) {
            throw const FormatException(
              'Benchmark output contains an end marker without a start marker.',
            );
          }
          final report = completedLines.join('\n').trim();
          if (report.isEmpty) {
            throw const FormatException(
              'Benchmark output does not contain a complete benchmark report.',
            );
          }
          reports.add(report);
          reportLines = null;
        default:
          reportLines?.add(line);
      }
    }

    if (reportLines != null) {
      throw const FormatException(
        'Benchmark output contains a start marker without an end marker.',
      );
    }
    if (reports.isEmpty) {
      throw const FormatException(
        'Benchmark output does not contain a complete benchmark report.',
      );
    }
    return reports.join('\n\n');
  }
}

/// Statistical summary of repeated benchmark samples.
///
/// Durations use microseconds because that is the finest portable resolution
/// exposed by [Stopwatch]. Percentiles use the nearest-rank definition. The
/// deviation is the sample standard deviation, matching comparison tools that
/// summarize repeated command runs.
final class BenchmarkReport {
  /// Workload name and mode shown in reports.
  final String name;

  /// Measured durations in execution order.
  final List<int> durationsMicroseconds;

  /// Bytes processed by each sample, when the workload measures throughput.
  final int? bytesPerSample;

  /// Arithmetic mean of measured durations.
  final double meanMicroseconds;

  /// Sample standard deviation of measured durations.
  final double standardDeviationMicroseconds;

  /// Shortest measured duration.
  final int minMicroseconds;

  /// Longest measured duration.
  final int maxMicroseconds;

  /// Nearest-rank 50th percentile.
  final int p50Microseconds;

  /// Nearest-rank 95th percentile.
  final int p95Microseconds;

  /// Nearest-rank 99th percentile.
  final int p99Microseconds;

  /// Computes a report from positive [durationsMicroseconds].
  factory BenchmarkReport.fromSamples({
    required String name,
    required List<int> durationsMicroseconds,
    int? bytesPerSample,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (durationsMicroseconds.isEmpty) {
      throw ArgumentError.value(
        durationsMicroseconds,
        'durationsMicroseconds',
        'must contain at least one sample',
      );
    }
    for (final duration in durationsMicroseconds) {
      if (duration <= 0) {
        throw RangeError.value(
          duration,
          'durationsMicroseconds',
          'samples must be positive',
        );
      }
    }
    if (bytesPerSample != null && bytesPerSample <= 0) {
      throw RangeError.range(bytesPerSample, 1, null, 'bytesPerSample');
    }

    final durations = List<int>.unmodifiable(durationsMicroseconds);
    final sorted = [...durations]..sort();
    final mean =
        durations.fold<int>(0, (sum, value) => sum + value) / durations.length;
    final squaredDifferenceSum = durations.fold<double>(0, (sum, value) {
      final difference = value - mean;
      return sum + difference * difference;
    });
    final standardDeviation = durations.length == 1
        ? 0.0
        : sqrt(squaredDifferenceSum / (durations.length - 1));

    return BenchmarkReport._(
      name: normalizedName,
      durationsMicroseconds: durations,
      bytesPerSample: bytesPerSample,
      meanMicroseconds: mean,
      standardDeviationMicroseconds: standardDeviation,
      minMicroseconds: sorted.first,
      maxMicroseconds: sorted.last,
      p50Microseconds: _percentile(sorted, 0.50),
      p95Microseconds: _percentile(sorted, 0.95),
      p99Microseconds: _percentile(sorted, 0.99),
    );
  }

  const BenchmarkReport._({
    required this.name,
    required this.durationsMicroseconds,
    required this.bytesPerSample,
    required this.meanMicroseconds,
    required this.standardDeviationMicroseconds,
    required this.minMicroseconds,
    required this.maxMicroseconds,
    required this.p50Microseconds,
    required this.p95Microseconds,
    required this.p99Microseconds,
  });

  /// Mean throughput in mebibytes per second, when [bytesPerSample] is set.
  double? get mebibytesPerSecond {
    final bytes = bytesPerSample;
    if (bytes == null) return null;
    final mebibytes = bytes / (1024 * 1024);
    final seconds = meanMicroseconds / Duration.microsecondsPerSecond;
    return mebibytes / seconds;
  }

  /// Number of measured samples.
  int get sampleCount => durationsMicroseconds.length;

  /// Formats timing, range, percentiles, and optional throughput.
  ///
  /// The layout follows the output used by `hyperfine`, with percentiles added
  /// because frame-tail latency matters independently of mean throughput.
  String format({required int index}) {
    if (index <= 0) throw RangeError.range(index, 1, null, 'index');
    final scale = _durationScale(meanMicroseconds);
    final mean = _duration(meanMicroseconds, scale);
    final deviation = _duration(standardDeviationMicroseconds, scale);
    final minimum = _duration(minMicroseconds, scale);
    final maximum = _duration(maxMicroseconds, scale);
    final p50 = _duration(p50Microseconds, scale);
    final p95 = _duration(p95Microseconds, scale);
    final p99 = _duration(p99Microseconds, scale);
    final lines = <String>[
      'Benchmark $index: $name',
      '  Time (mean ± σ):     $mean ± $deviation',
      '  Range (min … max):   $minimum … $maximum    $sampleCount runs',
      '  Percentiles:         p50 $p50 | p95 $p95 | p99 $p99',
    ];
    if (mebibytesPerSecond case final throughput?) {
      lines.add(
        '  Throughput:          ${throughput.toStringAsFixed(1)} MiB/s',
      );
    }
    return lines.join('\n');
  }
}

/// Runs one benchmark workload with setup and teardown outside timed samples.
///
/// Each call to [step] produces one sample. Optional per-sample [prepare] work
/// runs immediately beforehand and outside the timed region. Fast operations
/// should loop inside [step] until a sample is long enough to exceed the clock
/// resolution and amortize runner overhead.
///
/// ```dart
/// final report = await BenchmarkRunner(
///   warmupCount: 3,
///   sampleCount: 30,
/// ).run(
///   name: 'parser --mode=ascii',
///   step: parseCorpus,
/// );
/// ```
final class BenchmarkRunner {
  /// Number of unmeasured [BenchmarkCallback] invocations before sampling.
  final int warmupCount;

  /// Number of measured [BenchmarkCallback] invocations.
  final int sampleCount;

  final BenchmarkClock _clock;

  /// Creates a runner with fixed warmup and sample counts.
  ///
  /// [clock] exists for deterministic harness tests. Production benchmarks use
  /// a monotonic [Stopwatch].
  BenchmarkRunner({
    required this.warmupCount,
    required this.sampleCount,
    BenchmarkClock? clock,
  }) : _clock = clock ?? _stopwatchClock() {
    if (warmupCount < 0) {
      throw RangeError.range(warmupCount, 0, null, 'warmupCount');
    }
    if (sampleCount <= 0) {
      throw RangeError.range(sampleCount, 1, null, 'sampleCount');
    }
  }

  /// Runs [setup], warmups, measured [step] calls, then [teardown].
  ///
  /// [setup], [prepare], and teardown are excluded from every sample. Prepare
  /// runs before every warmup and measured step. Teardown runs when preparation
  /// or a step fails, but not when setup itself fails. This keeps the lifecycle
  /// equivalent to Ghostty's benchmark runner while supporting a distinct
  /// per-sample mutation boundary for frame benchmarks.
  Future<BenchmarkReport> run({
    required String name,
    required BenchmarkCallback step,
    BenchmarkCallback? setup,
    BenchmarkCallback? prepare,
    BenchmarkCallback? teardown,
    int? bytesPerSample,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (bytesPerSample != null && bytesPerSample <= 0) {
      throw RangeError.range(bytesPerSample, 1, null, 'bytesPerSample');
    }

    await setup?.call();
    try {
      for (var warmup = 0; warmup < warmupCount; warmup++) {
        await prepare?.call();
        await step();
      }

      final durations = <int>[];
      for (var sample = 0; sample < sampleCount; sample++) {
        await prepare?.call();
        final start = _clock();
        await step();
        final duration = _clock() - start;
        if (duration <= 0) {
          throw StateError(
            'Benchmark "$normalizedName" produced a sample below the clock '
            'resolution. Increase the work performed by each step.',
          );
        }
        durations.add(duration);
      }

      return BenchmarkReport.fromSamples(
        name: normalizedName,
        durationsMicroseconds: durations,
        bytesPerSample: bytesPerSample,
      );
    } finally {
      await teardown?.call();
    }
  }
}
