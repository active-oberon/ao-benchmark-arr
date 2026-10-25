# Recovered video benchmarks

These programs reproduce the summation examples in the
[YouTube video](https://www.youtube.com/watch?v=7NAZCrfmLxk).
The source notes below identify the relevant timestamps and frame names;
extracted frames are optional working files and are not included in Git.
They use 200,000,000 signed 32-bit integers filled with 2, an 800,000,000-byte
array, 500 timed sums, and the expected result 400,000,000. Allocation and
initialization happen outside the timer. Every timed result is checked.

## Source provenance

- `rust/main.rs`: the complete worker algorithm and benchmark are visible at
  11:37-12:00 (`rust.png`, `rust-bottom.png`). The original creates 12 operating
  system threads for every sum and uses `chunk.iter().sum::<i32>()`.
- `zig/main.zig`: the scalar loop, 20-thread partitioning, aligned accumulators,
  thread creation/join, and benchmark are visible at 00:44-02:31
  (`zig-main.png`, `zig-parallel.png`, `zig-bottom.png`). The compiler API was
  adapted to installed Zig 0.16. Optional worker counts use a 64-slot stack
  array aligned to 128 bytes, with only the requested slots active.
- `go/main.go`: the worker algorithm is visible at 03:22-03:43
  (`go-main.png`, `go-bottom.png`, `go-tail.png`). It launches twice the CPU
  count in goroutines and collects their sums through a buffered channel.
  The displayed ARM64 assembly at 04:01-04:20 is ported to x86-64 SSE2 in
  `sum_amd64.s`, retaining four 128-bit accumulators and 16 integers per loop.
  Allocation and the partly hidden benchmark driver were reconstructed.
- `java/VecSum.java`: the array, 500-sample benchmark, and
  `Arrays.stream(arr).parallel().sum()` are visible at 09:48-10:30
  (`java.png`, `java-bottom.png`, `java-tail.png`). Java uses its normal common
  pool in the video profile. In the eight-worker profile the pool parallelism
  is seven, with the calling thread also able to execute stream tasks.
- `python/blazing_sum.pyx`: the four-accumulator NEON kernel and the declaration
  of 16 parallel chunks are visible at 09:07-09:22 (`python.png`,
  `python-entry.png`). The rest of the parallel wrapper and Python driver are
  not displayed; they were reconstructed using Cython `prange` and OpenMP.
  This reconstruction explicitly requests one OpenMP thread per chunk.
- `c/main.c`: **control implementation, not an extracted original**. The video
  only runs an existing C binary and does not show its source. This control
  combines the displayed Cython SIMD loop with pthread creation/join and uses
  eight threads by default; the video's C thread count is unknown.

`common/neon_compat.h` maps the displayed 128-bit NEON operations to SSE2 on
x86-64. Go has an assembly equivalent. Rust and Zig retain the source-level
sum and allow their optimizing compilers to vectorize it. No C# or Swift
implementation was added.

The optional positional arguments are `elements iterations workers`; omitted
values retain the video's constants where visible. Boundary handling was added
for empty arrays and worker counts greater than the number of elements.

## Build and reproduce

Run from the parent directory:

```sh
bash comparison/build.sh
python3 comparison/run.py check
python3 comparison/run.py run
```

The build uses installed GCC, Rust, Zig, Go, Java, and Python toolchains. C,
Rust, Zig, and Cython use native CPU optimizations. Cython links OpenMP.
If Cython is absent from the system Python, the build uses the already
installed Blender Python 3.13 packages; no package is downloaded or installed.
Set `A2_OB` before building to select a different MiniA2 SDK.

`build.sh` also builds the existing Active Oberon programs and a comparison
copy named `ArrayBenchEight.Mod`. That copy changes only the final worker
selection to eight; the existing source, kernels, calibration, and warmups are
preserved. Generated sources and binaries are under `build/`.

## Measurement protocol and limits

The 2026-10-09 SDK used a scalar `SIGNED32` reduction: eight-worker `SUM` took
44.834 ms versus 25.020 ms for the explicit AVX2 kernel. The MiniA2 optimization
tested on 2026-10-25 installs a contiguous SSE2 reduction with four independent
accumulators. With eight workers, `SUM` now takes 24.922 ms versus 25.362 ms for
AVX2; the fresh pre-change `SUM` baseline was 44.071 ms. Application code still
uses `SUM(...)`. Rust and Zig receive vectorized loops from their compilers.
See [RESULTS.md](RESULTS.md) for both dated runs and the memory-bandwidth inference.

The repeat's outputs and MiniA2 source/SDK hashes are in
[`results/sum-optimization/`](results/sum-optimization/); the original outputs
remain directly under `results/`. To repeat into the separate directory after
rebuilding MiniA2 and running `bash comparison/build.sh`:

```sh
python3 - <<'PY'
from comparison import run
run.RESULTS = run.ROOT / 'comparison/results/sum-optimization'
run.RESULTS.mkdir(parents=True, exist_ok=True)
run.check()
run.run()
PY
```

`run.py run` executes one program at a time on this machine:

- `video`: Rust 12, Zig 20, Go 16; Java's default pool; Cython 16 requested
  threads; the reconstructed C control 8. Some actual video settings are
  unknown, as noted above.
- `eight`: all recovered implementations request eight workers, followed by
  Active Oberon AVX2 and language-level `SUM` with eight active objects.
- `auto`: the original Active Oberon programs select their worker count by
  calibration and then take 500 samples.

The recovered programs start timing their first call immediately. First-call
time, mean, and median are retained. Java therefore warms its just-in-time
compiler during the 500 calls; its median is not a cold-start measurement.
Active Oberon retains three untimed warmups and its calibration. Rust, Zig,
and C create/join threads inside each timed call; Go launches goroutines;
Java and OpenMP use runtime pools; Active Oberon uses persistent active objects.

The recovered programs report the sorted middle element at index 250, as shown
in the video. Active Oberon averages indices 249 and 250. Timings include
dispatch, waiting, and combining results, but not allocation or initialization.
First-call time does not include JVM or Python process startup.

`results/timings.csv` contains aggregate measurements. Individual program
outputs, build and check logs, CPU details, toolchain versions, and source
SHA-256 hashes are under `results/`. The runner checks every reported sum.
The edge checks cover zero length, SIMD boundaries, unequal partitions,
one worker, and more workers than elements. Go's assembly test also covers
signed values, unaligned offsets, and 64-bit final lane reduction. Active
Oberon runs its existing scalar-reference and repeated-worker self-check.

This workload fits signed 32-bit sums. SIMD lanes still accumulate in 32 bits;
these programs are not a general overflow-safe reduction for arbitrary input.
The hardware and compiler versions differ from the video's ARM Mac. Frequency
and other desktop processes remain under the operating system's normal control;
one batch per profile is not evidence for a universal ranking of languages.
