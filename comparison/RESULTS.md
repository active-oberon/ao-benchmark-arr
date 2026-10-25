# Benchmark results

## SUM optimization — 2026-10-25

Moving the vector reduction into MiniA2 removes the earlier gap without changing
the application's `SUM(...)` expression. At eight workers, the fresh scalar
baseline was **44.071 ms**; the updated library `SUM` measured **24.922 ms**,
about **1.77x faster**. The explicit AVX2 kernel measured **25.362 ms** in the
same repeat (24.467 ms in the pre-change control). Small differences among the
optimized implementations should not be treated as a ranking.

The updated AMD64 `FoxArrayBaseOptimized` installs an SSE2 `SIGNED32` reduction
through `FoxArrayBase.loopSumAL`. It uses four independent accumulators and
16 integers per main-loop iteration, with unaligned loads. Short arrays, tails
and noncontiguous strides use scalar additions; other targets retain the
portable default. Existing partial sums and 32-bit wraparound are preserved.
This does not require AVX or change the other integer/floating-point reductions.

All 16 original benchmark batches were repeated, each with 200,000,000 elements
and 500 checked sums. At eight workers, the medians were:

- C control: **25.060 ms**; Rust: **24.606 ms**; Zig: **24.640 ms**.
- Go: **25.056 ms**; Java: **25.857 ms**; Python/Cython: **24.817 ms**.
- Active Oberon: **24.922 ms** for library `SUM`, **25.362 ms** for explicit AVX2.

Automatic worker selection gave **23.933 ms** for `SUM` with five active objects
and **23.958 ms** for AVX2 with three. The useful array-read rate for automatic
`SUM` was **33.427 GB/s**. The memory-bandwidth interpretation below remains an
inference, not a measurement with hardware counters.

Raw outputs and aggregate figures are in
[`results/sum-optimization/timings.csv`](results/sum-optimization/timings.csv).
[`environment.json`](results/sum-optimization/environment.json) records hardware,
toolchains and hashes of the modified MiniA2 sources and rebuilt SDK objects.
The old SDK was used for `before-eight-SUM.txt`; the benchmark source is unchanged.
The optimized results use the modified MiniA2 checkout, not the original SDK.
The runtime change is available in [MiniA2 commit 3902319](https://github.com/active-oberon/minia2/commit/39023192139c0b49f18aaade17e40fd065a391b7).

Validation passed on Linux AMD64 and A64/QEMU: all four new `FoxArrayBase.Test`
cases pass, and the combined array suites report 33 passed, zero failed and four
previously known failures on each target. The A64 library builds 396/396 modules;
the two changed runtime modules also compile for Win64. The recovered/control
boundary checks and `ArrayBench.Check` pass. Details, known failures and skipped
platforms are in [`validation.txt`](results/sum-optimization/validation.txt).

## Original comparison — 2026-10-09

The recovered examples all take approximately 25-26 ms on this Intel
Core i7-9700K. Active Oberon's AVX2 implementation takes 25.020 ms with eight
workers, or 23.597 ms after automatic worker selection. The
[YouTube video](https://www.youtube.com/watch?v=7NAZCrfmLxk) therefore
does not demonstrate that these languages would take 7 ms on this computer.

All figures below are medians of 500 sums of 200,000,000 signed 32-bit integers
filled with 2. Each array occupies 800,000,000 bytes. Every timed sum returned
400,000,000. Programs ran sequentially, with allocation and initialization
outside the timer. CPU: eight physical cores, no simultaneous multithreading;
L3 cache: 12 MiB. Toolchain versions and hardware details are in
[`results/environment.json`](results/environment.json).

### Eight-worker comparison

- Rust: **24.968 ms**; mean 25.216 ms; first call 26.745 ms.
- Zig: **24.989 ms**; mean 25.619 ms; first call 25.741 ms.
- Go: **25.090 ms**; mean 25.445 ms; first call 25.209 ms.
- C control: **25.316 ms**; mean 25.645 ms; first call 25.860 ms.
- Python/Cython: **25.055 ms**; mean 26.314 ms; first call 25.597 ms.
- Java: **26.051 ms**; mean 26.783 ms; first call 68.853 ms.
- Active Oberon, AVX2 `CODE`: **25.020 ms**; mean 25.433 ms.
- Active Oberon, built-in mathematical-array `SUM`: **44.834 ms**; mean 46.856 ms.

The authoritative figures are in [`results/timings.csv`](results/timings.csv)
and the corresponding `eight-*.txt` logs. Active Oberon retains its calibration
and three untimed warmups. The other examples include their first call in the
500 samples. Java's common pool has parallelism seven plus the calling thread;
this is a requested execution policy, not a promise that all eight run equally.

### Original visible worker settings

- Rust, 12 threads: **24.581 ms**.
- Zig, 20 threads: **24.886 ms**.
- Go, twice the local CPU count, 16 goroutines: **25.136 ms**.
- Java, default common pool: **26.243 ms**; first call 56.699 ms.
- Python/Cython reconstruction, 16 OpenMP threads: **25.673 ms**.
- C control, 8 threads: **25.349 ms**; the original C thread count is unknown.

These results are in the `video-*.txt` logs. The Cython frame shows 16 chunks
but does not reveal the complete parallel wrapper; 16 OpenMP threads are an
explicit reconstruction choice. C's source is not shown anywhere in the video.

The original Active Oberon programs were also rerun. Calibration selected
five active objects for AVX2: **23.597 ms**, mean 23.996 ms, effective array-read
rate **33.903 GB/s**. For built-in `SUM`, it selected seven: **47.524 ms**, mean
49.213 ms. Logs are [`results/auto-Active-Oberon-AVX2.txt`](results/auto-Active-Oberon-AVX2.txt)
and [`results/auto-Active-Oberon-SUM.txt`](results/auto-Active-Oberon-SUM.txt).
Short calibration can select a count that performs worse over 500 samples;
the eight-worker `SUM` batch was faster than its automatically selected batch.

### Why the video is faster

The video's final table without OBS recording reports Rust 6.822 ms, Zig
7.019 ms, Go 7.074 ms, C 7.184 ms, Python/Cython 7.270 ms, and Java 10.724 ms
([YouTube, 18:42 onward](https://www.youtube.com/watch?v=7NAZCrfmLxk&t=1122s)).
The quoted Java result of about 16 ms was obtained while recording with OBS.
Neither value is a cold Java call: the benchmark makes 500 calls in one JVM.
Our fresh Java processes show the difference directly: a 56.699 or 68.853 ms
first call followed by a roughly 26 ms median. Process startup is not timed.

At 25 ms, reading this 800 MB array implies about **32 GB/s** of useful payload
reads. At 7 ms it implies about **114 GB/s**. The array is much larger than
the local 12 MiB last-level cache. Closely clustered timings across several
different vector kernels are consistent with memory bandwidth being the main
limit on this host. This is an inference from measurements, not a separate
measurement of the Mac's memory system. The video's exact Mac model and memory
configuration were not established; direct timing comparisons also mix CPUs,
compilers, runtimes, and operating systems.

The SDK used for this original comparison had an implementation limitation: its
`SIGNED32` operator dispatches to the scalar `SumALLoop` in
[`../../minia2/source/FoxArrayBase.Mod`](../../minia2/source/FoxArrayBase.Mod).
It does not automatically use the AVX2 reduction. In contrast, disassembly
confirms four AVX2 accumulators in the optimized Rust and Zig array loops;
[`results/simd-kernels.txt`](results/simd-kernels.txt) preserves that evidence.
The explicit Active Oberon AVX2 kernel achieves essentially the same time as
those loops when all use eight workers.

At eight workers, the built-in `SUM` is about 1.8x slower than the explicit
kernel. Its scalar loop adds one integer at a time to one accumulator, so
successive additions form a dependency chain. The AVX2 kernel processes 32
integers per main-loop iteration with four independent vector accumulators,
reducing loop overhead and exposing independent work to the CPU. Both paths
use the same Active Oberon worker pool; the selected reduction is what changes.

The conclusion is specific to that MiniA2 library implementation:
high-level `SUM` syntax did not select a vectorized integer reduction.
It does not show that Active Oberon inherently requires handwritten assembly
for competitive performance. Optimizing the library reduction would preserve
`SUM(...)` in application code. Once the optimized loops approach the inferred
memory-bandwidth limit, wider instructions need not yield proportional speedups.

### Validation and reproducibility

- `bash comparison/build.sh`: all six recovered/control programs and four
  Active Oberon binaries built successfully using installed toolchains.
- `python3 comparison/run.py check`: 17 boundary/partition cases per recovered
  program passed. Every call checks its expected sum. The Go assembly test
  passed 516 signed/offset/length cases and a 64-bit final reduction case.
- The existing Active Oberon `Check` passed its scalar-reference, signed-input,
  empty-array, repeated-worker, and statistics checks. Logs are in
  [`results/checks.txt`](results/checks.txt).
- All 16 full benchmark batches completed, totaling 8,000 checked timed sums.
  Reproduce them with `python3 comparison/run.py run`.
- Initial Go compilation failed with `mkdir /home/andrejjj/tmp/go-build...:
  read-only file system` because of a user-level `GOTMPDIR`. The build now sets
  `GOTMPDIR`, `TMPDIR`, and caches under `/tmp`.
- A Cython package-download attempt failed because DNS/network access was
  unavailable. Installed Blender Cython 3.0.11 and setuptools 80.9.0 were used
  instead. No global Python installation was modified.
- The first result-collection pass stopped with `ValueError: missing Average
  time`: Active Oberon pads numbers with extra spaces. The parser was corrected
  and checked with a padded-output assertion. Its completed measurement was
  retained; only the three remaining batches were then run. The original
  failure and successful continuation remain in [`results/run.log`](results/run.log).

Sources, adaptation details, and repeat commands are in
[`README.md`](README.md). C is a control implementation; hidden Go benchmark
code and the Cython parallel wrapper/driver are reconstructed. C# and Swift
were omitted as requested. ARM execution, arbitrary overflow-prone input,
and a matching Mac rerun were not checked. The SDK and its array
runtime were not changed. Desktop scheduling and frequency control were left
at their normal settings; [`results/frequency-snapshot.txt`](results/frequency-snapshot.txt)
records approximately 4.6 GHz during a batch. Small differences within these
single batches do not establish a universal language ranking.
