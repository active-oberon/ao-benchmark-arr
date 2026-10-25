# Active Oberon array sum benchmark

Recovered C, Rust, Zig, Go, Java, and Python/Cython examples from the
[YouTube video](https://www.youtube.com/watch?v=7NAZCrfmLxk) and the reproducible
comparison are in [comparison/README.md](comparison/README.md).

The workload matches the screenshots: 200,000,000 `SIGNED32` elements, each set
to 2, and 500 timed sums. The data occupies 800,000,000 bytes and the expected
sum is 400,000,000. Allocation and initialization happen before measurement.

`ArrayBench.Mod` provides two reductions over the same mathematical array:

- `Math` uses the language directly: `ARRAY [*] OF SIGNED32`, scalar broadcast
  assignment (`data.values := 2`), array slices, and `SUM(...)`.
- `Do` uses an AVX2 `CODE` kernel with four independent accumulators, processing
  32 integers per loop. It accepts unaligned data and handles the remaining
  elements without reading beyond the requested range.

The original MiniA2 SDK used the scalar `SumALLoop` for `SIGNED32` reductions.
With eight workers on the tested Intel Core i7-9700K, that version took
44.834 ms versus 25.020 ms for the AVX2 kernel on 2026-10-09.

The updated MiniA2 runtime tested on 2026-10-25 dispatches `SUM` through
`FoxArrayBase.loopSumAL`. On AMD64, the installed `FoxArrayBaseOptimized` module
selects an SSE2 kernel with four independent vector accumulators, processing
16 integers per main-loop iteration. Unaligned input is supported; short arrays,
tails and noncontiguous strides use scalar additions. Other targets retain the
portable default, and the result keeps the existing `SIGNED32` wraparound.
The application still writes `SUM(...)`; its mathematical-array code is unchanged.
Rust and Zig obtain vector loops from their compilers without handwritten assembly.

The repeat with eight workers measured **24.922 ms for built-in `SUM`**, down
from a fresh pre-change baseline of **44.071 ms** (about **1.77x faster**).
The explicit AVX2 kernel measured 25.362 ms in the same repeat; with automatic
worker selection, `SUM` measured 23.933 ms and AVX2 23.958 ms. These small
differences between the optimized kernels do not establish a reliable winner.

The optimized implementations cluster around 25-26 ms, consistent with a
memory-bandwidth limit when reading 800 MB per sum (about 32 GB/s at 25 ms).
This limit is inferred from timings, not verified with hardware counters.
See the [updated measurements and limits](comparison/RESULTS.md) for the effect
of the library optimization and the exact MiniA2 source/SDK hashes used.

Both modes share persistent active objects and synchronize with `EXCLUSIVE`
and `AWAIT`. Each worker reads a disjoint range. Workers are created before
measurement and stopped afterwards, avoiding thread creation in every sample.
Task dispatch, waiting, and combining the partial results remain inside the
measured interval. This differs from the screenshot's per-sample thread creation.

Calibration measures every worker count from 1 to the number of online CPUs,
with three warmups and seven samples per count. The count with the lowest
median is used for the 500-sample run, after three more warmups. Times use the
monotonic `PrecisionTimer`; an even-length median averages the two middle values.
Every measured result is checked with `ASSERT`.

Run the already built programs from this directory:

```sh
./array-bench
./array-math-bench
```

To check or rebuild with the SDK used for validation:

```sh
A2_OB=/home/andrejjj/Projects/A2/minia2/target/bundle/ob
"$A2_OB" run ArrayBench.Mod Check
"$A2_OB" build ArrayBench.Mod -o array-bench
"$A2_OB" build ArrayBench.Mod -o array-math-bench Math
```

The self-check compares both reductions with a scalar reference over all
lengths 0 through 128 at four offsets. It also covers an empty range at the end
of an array, empty arrays, unequal partitions, more workers than elements,
three consecutive jobs per pool, signed inputs, and mean/median calculation.

Recorded outputs from the Intel Core i7-9700K on 2026-10-09 are in
`benchmark-output.txt`, `math-output.txt`, and `selfcheck-output.txt`.
Performance depends on memory bandwidth and other work on the machine; the
calibration is a short sample, not a guarantee of the best count on every run.

The module targets Linux x86-64. `Do` checks AVX2 and the operating system's
vector state before executing the kernel. `Math` performs its reduction without
AVX2. Both retain 32-bit sum semantics; the fixed workload fits `SIGNED32`.
ARM, Windows, and CPUs without AVX2 were not tested. The MiniA2 SDK was not changed.
