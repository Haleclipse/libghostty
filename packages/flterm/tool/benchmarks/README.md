# flterm terminal benchmarks

These benchmarks follow Ghostty's measurement and reporting model while
accounting for a different runtime. Ghostty separates three responsibilities:

1. `ghostty-bench` performs one silent, fixed-work benchmark run.
2. `hyperfine` repeats ReleaseFast processes and formats their statistics.
3. Pull request authors turn those results into a table tailored to the
   performance claim.

For example, Ghostty PR
[#13227](https://github.com/ghostty-org/ghostty/pull/13227) derives per-update
times from fixed-count loops after subtracting process startup, then reports
the relevant scenarios in a hand-written table. The benchmark binary does not
generate that table.

Flutter widget tests run in a JIT test process and cannot select a profile or
release build mode. Timing the complete command would primarily measure
compilation and framework startup rather than terminal work. flterm therefore
keeps Ghostty's setup, step, teardown, deterministic fixture, mode, warmup, and
repeated-sample boundaries inside the test process. A small launcher extracts
the final reports from Flutter's machine test protocol and prints them in the
familiar `hyperfine` layout.

These measurements compare revisions. They are not production raster timings
or CI pass/fail gates.

The corresponding Ghostty sources are
[`Benchmark.zig`](../../../../ghostty/src/benchmark/Benchmark.zig) and its
[benchmarking policy](../../../../ghostty/src/benchmark/AGENTS.md).

## Design correspondence

| Ghostty | flterm | Purpose |
|---|---|---|
| Domain actions such as `terminal-stream` and `screen-clone` | Controller-write and frame-render entrypoints | Keep each result tied to one ownership boundary. |
| `setupFn`, `stepFn`, and `teardownFn` | Setup, prepare, step, and teardown callbacks | Exclude fixture creation, per-frame parsing, and cleanup from samples. |
| Fixed loops inside fast benchmark steps | 4 MiB write batches or one Flutter frame per sample | Make clock and runner overhead insignificant. |
| Pre-generated deterministic corpora | Tested deterministic terminal fixtures | Keep input identical across revisions. |
| `noop`, clean, partial, and full modes where useful | Clean, three-row, and full-frame modes | Expose harness cost and common versus worst-case work. |
| Sequential `hyperfine` warmups and runs | In-process warmups and repeated samples | Avoid measuring Flutter process startup. |
| `hyperfine` terminal report | Benchmark launcher and hyperfine-style formatter | Remove Flutter test-runner noise without changing the timed region. |
| ReleaseFast native binary | Flutter JIT test binding | Preserve relative comparisons without claiming production frame time. |

## Run

Run the launcher from `packages/flterm`. The `all` command runs both suites
sequentially. It never starts benchmark processes concurrently.

```sh
dart tool/benchmarks/run.dart controller-write
dart tool/benchmarks/run.dart frame-render
dart tool/benchmarks/run.dart all
```

The launcher buffers each suite and prints only complete reports after its
Flutter process succeeds. On failure it preserves the complete Flutter output
and exit status for diagnosis. The successful output is shaped like
`hyperfine`, with tail percentiles added for frame work:

```text
Benchmark 1: workload --mode=value
  Time (mean ± σ):     <mean> ± <sample deviation>
  Range (min … max):   <minimum> … <maximum>    <count> runs
  Percentiles:         p50 <value> | p95 <value> | p99 <value>
  Throughput:          <value> MiB/s
```

Throughput appears only when every sample processes a fixed byte count.
Percentiles use the nearest-rank definition. The deviation is the sample
standard deviation.

## Workloads

The controller benchmark feeds deterministic, lightly styled line output
through `TerminalController.write`. Both modes process 4 MiB per sample. One
uses 4 KiB chunks and the other uses 1 MiB chunks, so their difference isolates
chunking and notification overhead rather than total work. Scrollback is
disabled to keep retained history out of the comparison.

The frame benchmark uses an 80 by 24 terminal, device pixel ratio 1, and the
bundled JetBrains Mono font. Its modes are:

- `clean`, a Flutter pump without terminal mutation that establishes harness
  and clean-frame cost;
- `partial-3`, the common case where three rows change;
- `full`, every row changes with ASCII, wide, and combining text.

Payload generation and terminal parsing happen before each timed frame step.
The measured region covers Flutter's build and paint work in the test binding.
It does not include GPU rasterization or presentation.

Both entrypoints record 100 samples. This gives nearest-rank p95 and p99 enough
rank resolution that p99 is not merely the single slowest observation.

## Compare revisions

Keep hardware, power state, Flutter version, Dart version, operating system,
benchmark command, and fixtures identical. Run the baseline and changed
revisions at least three times each. Alternate revisions when practical so
thermal or background-load drift is visible. Never run benchmark processes in
parallel on the same machine.

Use p50 as the primary repeated-sample comparison because it is less sensitive
to isolated scheduler or garbage-collection pauses. Keep the mean, deviation,
range, and tail percentiles in the raw evidence. Throughput is the primary
controller-write metric. Frame reports should retain p95 and p99 so an average
improvement cannot hide worse tail behavior.

Like Ghostty, write the final pull request table for the claim being evaluated.
Do not compare unrelated controls as if they were competing implementations.
For example, a clean frame establishes harness cost; it is not an alternative
to a partial or full frame. If a derived per-operation value subtracts a
control or divides a fixed loop count, state the formula and keep the work
boundaries identical between revisions.

Record machine-specific results in the pull request, not in this directory.
A typical comparison starts with:

```text
| scenario | baseline | changed | change |
|---|---:|---:|---:|
| workload and mode | <primary metric> | <primary metric> | <ratio or percent> |
```

Include:

- baseline and changed commit hashes;
- toolchain, operating system, CPU, and build mode;
- at least three complete reports from each revision;
- a before/after table using the metric relevant to the claim;
- mean, p50, p95, and p99 evidence for frame work;
- throughput for controller writes;
- the clean-frame control beside partial and full frame results;
- any regression, trade-off, or unexplained variance.

The harness and deterministic fixtures have correctness tests:

```sh
flutter test test/tool/benchmark_harness_test.dart
flutter test test/tool/benchmark_launcher_test.dart
flutter test test/tool/terminal_benchmark_fixture_test.dart
```
