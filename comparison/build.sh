#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p comparison/build/{java,python} comparison/results
export GOCACHE=/tmp/array-bench-go-cache
export GOTMPDIR=/tmp
export TMPDIR=/tmp
export GO111MODULE=off
export ZIG_LOCAL_CACHE_DIR=/tmp/array-bench-zig-local
export ZIG_GLOBAL_CACHE_DIR=/tmp/array-bench-zig-global
export PYTHONDONTWRITEBYTECODE=1
gcc -O3 -march=native -Wall -Wextra -pthread -I comparison/common comparison/c/main.c -o comparison/build/c
rustc -C opt-level=3 -C target-cpu=native comparison/rust/main.rs -o comparison/build/rust
zig build-exe comparison/zig/main.zig -O ReleaseFast -mcpu=native -lc -femit-bin=comparison/build/zig
(cd comparison/go && go build -o ../build/go .)
javac -d comparison/build/java comparison/java/VecSum.java
if ! python3 -c 'import Cython, setuptools' 2>/dev/null; then
    export PYTHONPATH="/opt/programming/blender/5.2/python/lib/python3.13/site-packages${PYTHONPATH:+:$PYTHONPATH}"
fi
python3 comparison/python/setup.py build_ext --build-lib comparison/build/python --build-temp comparison/build/python-temp
A2_OB=${A2_OB:-/home/andrejjj/Projects/A2/minia2/target/bundle/ob}
"$A2_OB" build ArrayBench.Mod -o array-bench
"$A2_OB" build ArrayBench.Mod -o array-math-bench Math
python3 - <<'PY'
from pathlib import Path
source = Path('ArrayBench.Mod').read_text()
needle = '\tMeasure(data, bestThreads, Iterations, useAVX2, mean, median, result);'
assert source.count(needle) == 1
source = source.replace('ArrayBench', 'ArrayBenchEight')
source = source.replace(needle, '\tbestThreads := 8;\n' + needle)
Path('comparison/build/ArrayBenchEight.Mod').write_text(source)
PY
"$A2_OB" build comparison/build/ArrayBenchEight.Mod -o comparison/build/oberon-eight
"$A2_OB" build comparison/build/ArrayBenchEight.Mod -o comparison/build/oberon-math-eight Math
