import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/terminal_benchmark_fixture.dart';

void main() {
  group('TerminalBenchmarkFixture', () {
    group('controllerOutput', () {
      test('returns the requested byte length', () {
        final result = TerminalBenchmarkFixture.controllerOutput(4096);

        expect(result, hasLength(4096));
      });

      test('returns identical bytes for identical lengths', () {
        final first = TerminalBenchmarkFixture.controllerOutput(4096);
        final second = TerminalBenchmarkFixture.controllerOutput(4096);

        expect(first, orderedEquals(second));
      });

      test('contains lightly styled line output', () {
        final result = TerminalBenchmarkFixture.controllerOutput(4096);

        final text = utf8.decode(result);

        expect(text, contains('\x1b[38;5;39mINFO\x1b[0m'));
      });

      test('rejects a non-positive length', () {
        expect(
          () => TerminalBenchmarkFixture.controllerOutput(0),
          throwsRangeError,
        );
      });
    });

    group('fullFrame', () {
      test('addresses every terminal row', () {
        final result = TerminalBenchmarkFixture.fullFrame(
          columns: 80,
          rows: 2,
          variant: 7,
        );

        final text = utf8.decode(result);
        final cursorAddresses = RegExp(r'\x1b\[\d+;1H').allMatches(text);

        expect(cursorAddresses, hasLength(2));
      });

      test('contains wide and combining text', () {
        final result = TerminalBenchmarkFixture.fullFrame(
          columns: 80,
          rows: 1,
          variant: 7,
        );

        final text = utf8.decode(result);

        expect(text, contains('界 combining e\u0301'));
      });

      test('rejects fewer than 80 columns', () {
        expect(
          () => TerminalBenchmarkFixture.fullFrame(
            columns: 79,
            rows: 24,
            variant: 0,
          ),
          throwsRangeError,
        );
      });

      test('rejects a non-positive row count', () {
        expect(
          () => TerminalBenchmarkFixture.fullFrame(
            columns: 80,
            rows: 0,
            variant: 0,
          ),
          throwsRangeError,
        );
      });
    });

    group('partialFrame', () {
      test('addresses only the requested dirty rows', () {
        final result = TerminalBenchmarkFixture.partialFrame(
          columns: 80,
          rows: 24,
          dirtyRows: 3,
          variant: 7,
        );

        final text = utf8.decode(result);
        final cursorAddresses = RegExp(r'\x1b\[\d+;1H').allMatches(text);

        expect(cursorAddresses, hasLength(3));
      });

      test('rejects more dirty rows than terminal rows', () {
        expect(
          () => TerminalBenchmarkFixture.partialFrame(
            columns: 80,
            rows: 2,
            dirtyRows: 3,
            variant: 0,
          ),
          throwsRangeError,
        );
      });

      test('rejects a negative variant', () {
        expect(
          () => TerminalBenchmarkFixture.partialFrame(
            columns: 80,
            rows: 24,
            dirtyRows: 3,
            variant: -1,
          ),
          throwsRangeError,
        );
      });
    });
  });
}
