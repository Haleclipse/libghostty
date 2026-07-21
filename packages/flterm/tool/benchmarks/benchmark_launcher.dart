import 'benchmark_harness.dart' show BenchmarkOutput;

/// Result returned by a benchmark process adapter.
typedef BenchmarkProcessResult = ({int exitCode, String stdout, String stderr});

/// Starts one Flutter benchmark process with the supplied arguments.
typedef BenchmarkProcessRunner =
    Future<BenchmarkProcessResult> Function(List<String> arguments);

/// Buffered output and exit status from a benchmark launcher command.
final class BenchmarkCommandResult {
  /// Process-compatible status code.
  final int exitCode;

  /// Clean reports on success or complete child output on failure.
  final String stdout;

  /// Usage or process diagnostics.
  final String stderr;

  const BenchmarkCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Runs the selected benchmark processes and buffers their final reports.
///
/// The `all` command awaits each process before starting the next one because
/// concurrent benchmarks interfere with wall-clock measurements.
///
/// ```dart
/// final result = await runBenchmarkCommand(
///   const ['controller-write'],
///   processRunner: runFlutter,
/// );
/// ```
Future<BenchmarkCommandResult> runBenchmarkCommand(
  List<String> arguments, {
  required BenchmarkProcessRunner processRunner,
}) async {
  if (arguments.length != 1) {
    return const BenchmarkCommandResult(
      exitCode: _usageExitCode,
      stdout: '',
      stderr: _usage,
    );
  }

  final command = arguments.single;
  if (command == '--help' || command == '-h') {
    return const BenchmarkCommandResult(
      exitCode: 0,
      stdout: _usage,
      stderr: '',
    );
  }

  final targets = switch (command) {
    'controller-write' => const [_BenchmarkTarget.controllerWrite],
    'frame-render' => const [_BenchmarkTarget.frameRender],
    'all' => const [
      _BenchmarkTarget.controllerWrite,
      _BenchmarkTarget.frameRender,
    ],
    _ => null,
  };
  if (targets == null) {
    return BenchmarkCommandResult(
      exitCode: _usageExitCode,
      stdout: '',
      stderr: 'Unknown benchmark "$command".\n\n$_usage',
    );
  }

  final reports = <String>[];
  final processStdout = <String>[];
  final processStderr = <String>[];
  for (final target in targets) {
    final result = await processRunner([
      'test',
      '--no-track-widget-creation',
      target.path,
      '--machine',
    ]);
    if (result.stdout.isNotEmpty) processStdout.add(result.stdout);
    if (result.stderr.isNotEmpty) processStderr.add(result.stderr);
    if (result.exitCode != 0) {
      return BenchmarkCommandResult(
        exitCode: result.exitCode,
        stdout: processStdout.join('\n'),
        stderr: processStderr.join('\n'),
      );
    }

    try {
      reports.add(BenchmarkOutput.extract(result.stdout));
    } on FormatException catch (error) {
      processStderr.add('Failed to extract ${target.label}: ${error.message}');
      return BenchmarkCommandResult(
        exitCode: 1,
        stdout: processStdout.join('\n'),
        stderr: processStderr.join('\n'),
      );
    }
  }

  return BenchmarkCommandResult(
    exitCode: 0,
    stdout: reports.join('\n\n'),
    stderr: '',
  );
}

const _usage =
    'Usage: dart tool/benchmarks/run.dart '
    '<controller-write|frame-render|all>';
const _usageExitCode = 64;

enum _BenchmarkTarget {
  controllerWrite(
    label: 'controller write benchmark report',
    path: 'tool/benchmarks/controller_write_benchmark.dart',
  ),
  frameRender(
    label: 'frame render benchmark report',
    path: 'tool/benchmarks/frame_render_benchmark.dart',
  );

  final String label;
  final String path;

  const _BenchmarkTarget({required this.label, required this.path});
}
