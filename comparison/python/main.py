"""Reconstructed Python driver for the Cython/OpenMP implementation shown at 09:07."""
import sys
import time

from blazing_sum import close, parallel_sum, prepare

settings = [200_000_000, 500, 16]
if len(sys.argv) > 4:
    raise ValueError("expected: elements iterations workers")
for i, argument in enumerate(sys.argv[1:]):
    settings[i] = int(argument)
n, iterations, workers = settings
if not 0 <= n <= 200_000_000 or not 1 <= iterations <= 100_000 or not 1 <= workers <= 64:
    raise ValueError("invalid arguments")
prepare(n)
try:
    times = []
    for _ in range(iterations):
        start = time.perf_counter_ns()
        result = parallel_sum(workers)
        times.append((time.perf_counter_ns() - start) / 1_000_000)
        assert result == n * 2
    print(f"Workers: {workers}\nFirst time: {times[0]:.3f} ms")
    times.sort()
    print(f"Average time: {sum(times) / iterations:.3f} ms")
    print(f"Median time: {times[iterations // 2]:.3f} ms\nSum: {result}")
finally:
    close()
