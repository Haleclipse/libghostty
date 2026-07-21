import 'dart:io';

import 'benchmark_launcher.dart';

Future<void> main(List<String> arguments) async {
  final packageDirectory = File.fromUri(
    Platform.script,
  ).parent.parent.parent.path;
  final result = await runBenchmarkCommand(
    arguments,
    processRunner: (processArguments) =>
        _runFlutter(processArguments, packageDirectory: packageDirectory),
  );

  if (result.stdout.isNotEmpty) stdout.writeln(result.stdout);
  if (result.stderr.isNotEmpty) stderr.writeln(result.stderr);
  exitCode = result.exitCode;
}

Future<BenchmarkProcessResult> _runFlutter(
  List<String> arguments, {
  required String packageDirectory,
}) async {
  try {
    final result = await Process.run(
      'flutter',
      arguments,
      workingDirectory: packageDirectory,
      runInShell: Platform.isWindows,
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } on ProcessException catch (error) {
    return (exitCode: error.errorCode, stdout: '', stderr: error.toString());
  }
}
