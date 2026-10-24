"""Check recovered implementations or run the two 500-sample comparison profiles."""
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "comparison/build"
RESULTS = ROOT / "comparison/results"
ENV = dict(os.environ, TMPDIR="/tmp", GOTMPDIR="/tmp", GOCACHE="/tmp/array-bench-go-cache", GO111MODULE="off",
           PYTHONDONTWRITEBYTECODE="1", PYTHONPATH=str(BUILD / "python"))
COMMANDS = {
    "C-control": [str(BUILD / "c")],
    "Rust": [str(BUILD / "rust")],
    "Zig": [str(BUILD / "zig")],
    "Go": [str(BUILD / "go")],
    "Java": ["java", "-Xmx4G", "-cp", str(BUILD / "java"), "VecSum"],
    "Python-Cython": ["python3", str(ROOT / "comparison/python/main.py")],
}
VIDEO_WORKERS = {"C-control": 8, "Rust": 12, "Zig": 20, "Go": 16, "Java": 8, "Python-Cython": 16}


def execute(command):
    result = subprocess.run(command, cwd=ROOT, env=ENV, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=600)
    if result.returncode:
        raise RuntimeError(f"{command!r} exited {result.returncode}:\n{result.stdout}")
    return result.stdout


def metrics(output, elements):
    def value(label):
        match = re.search(rf"^{label}:[ \t]+([0-9.]+)", output, re.MULTILINE)
        if not match:
            raise ValueError(f"missing {label}:\n{output}")
        return float(match.group(1))
    result = int(value("Sum"))
    assert result == elements * 2, output
    return {"first_ms": value("First time") if "First time:" in output else "",
            "mean_ms": value("Average time"), "median_ms": value("Median time"), "sum": result}


def check():
    assert metrics("Average time:   1.5 ms\nMedian time:  1.0 ms\nSum: 2\n", 1)["median_ms"] == 1.0
    log = [execute(["go", "test", "./comparison/go"])]
    cases = [(n, 3) for n in (0, 1, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33, 63, 65, 101)]
    cases += [(3, 8), (33, 1)]
    for name, command in COMMANDS.items():
        for n, workers in cases:
            output = execute(command + [str(n), "3", str(workers)])
            metrics(output, n)
            log.append(f"{name}: elements={n}, workers={workers}\n{output}")
        print(f"PASS {name}: {len(cases)} cases", flush=True)
    sdk = "/home/andrejjj/Projects/A2/minia2/target/bundle/ob"
    log.append(execute([sdk, "run", "ArrayBench.Mod", "Check"]))
    assert "PASS: SUM and AVX2" in log[-1], log[-1]
    (RESULTS / "checks.txt").write_text("\n".join(log))
    print("PASS Active Oberon: existing signed-input and worker checks", flush=True)


def run():
    versions = {}
    for name, command in {"gcc": ["gcc", "--version"], "rust": ["rustc", "--version"],
                          "zig": ["zig", "version"], "go": ["go", "version"],
                          "java": ["java", "-version"], "python": ["python3", "--version"]}.items():
        versions[name] = execute(command).strip()
    source_paths = [ROOT / "ArrayBench.Mod"]
    source_paths += sorted(p for p in (ROOT / "comparison").rglob("*")
                           if p.suffix in (".c", ".h", ".rs", ".zig", ".go", ".s", ".java", ".pyx", ".py", ".sh")
                           and not p.is_relative_to(BUILD))
    metadata = {"started_utc": datetime.now(timezone.utc).isoformat(), "elements": 200_000_000,
                "iterations": 500, "cpu_affinity": sorted(os.sched_getaffinity(0)), "versions": versions,
                "hardware": execute(["lscpu"]), "memory": Path("/proc/meminfo").read_text(),
                "environment": {k: ENV.get(k) for k in ("OMP_WAIT_POLICY", "OMP_NUM_THREADS", "GOMP_SPINCOUNT", "GOMAXPROCS")},
                "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}}
    (RESULTS / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    jobs = []
    for profile in ("video", "eight"):
        for name, command in COMMANDS.items():
            arguments = ["200000000", "500"] + (["8"] if profile == "eight" else [])
            jobs.append((profile, name, 8 if profile == "eight" else VIDEO_WORKERS[name], command + arguments))
    jobs += [("eight", "Active-Oberon-AVX2", 8, [str(BUILD / "oberon-eight")]),
             ("eight", "Active-Oberon-SUM", 8, [str(BUILD / "oberon-math-eight")]),
             ("auto", "Active-Oberon-AVX2", "auto", [str(ROOT / "array-bench")]),
             ("auto", "Active-Oberon-SUM", "auto", [str(ROOT / "array-math-bench")])]
    columns = ["profile", "language", "workers", "first_ms", "mean_ms", "median_ms", "sum"]
    with (RESULTS / "timings.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=columns)
        writer.writeheader()
        for profile, name, workers, command in jobs:
            print(f"RUN {profile}/{name}: 200000000 elements, 500 sums", flush=True)
            output = execute(command)
            (RESULTS / f"{profile}-{name}.txt").write_text(output)
            measured = metrics(output, 200_000_000)
            if workers == "auto":
                workers = int(re.search(r"Threads: (\d+)", output).group(1))
            writer.writerow(dict(profile=profile, language=name, workers=workers, **measured))
            file.flush()
            print(f"DONE {profile}/{name}: median {measured['median_ms']:.3f} ms", flush=True)
    print(f"Saved {RESULTS / 'timings.csv'}", flush=True)


if __name__ == "__main__":
    RESULTS.mkdir(parents=True, exist_ok=True)
    if sys.argv[1:] == ["check"]:
        check()
    elif sys.argv[1:] == ["run"]:
        run()
    else:
        raise SystemExit("usage: python3 comparison/run.py check|run")
