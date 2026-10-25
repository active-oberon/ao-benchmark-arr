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

In the local MiniA2 SDK, the `SUM` operator for `SIGNED32` calls the scalar
`SumALLoop` in `../minia2/source/FoxArrayBase.Mod`. Mathematical array syntax
does not automatically make this particular reduction use SIMD instructions.
`FoxArrayBaseOptimized` is linked for the standard array runtime optimizations;
its SSE optimizations do not replace this integer reduction.

With eight workers on the tested Intel Core i7-9700K, built-in `SUM` took
44.834 ms versus 25.020 ms for the AVX2 kernel, about a 1.8x difference.
The scalar loop adds one integer at a time to a single accumulator; the AVX2
kernel uses four independent vector accumulators and processes 32 integers
per main-loop iteration. Rust and Zig obtain vector loops from their compilers
without handwritten assembly. This exposes a limitation of the tested MiniA2
`SUM` implementation, not an inherent limitation of Active Oberon.

The optimized implementations cluster around 25-26 ms, consistent with a
memory-bandwidth limit when reading 800 MB per sum (about 32 GB/s at 25 ms).
This limit is inferred from timings, not verified with hardware counters.
Optimizing the library's `SUM` would let application code retain `SUM(...)`
without its own assembly kernel. See [measurements and limits](comparison/RESULTS.md).

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
