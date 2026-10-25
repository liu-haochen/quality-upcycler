"""Isolated, headless UPS benchmark against native assembling machines.

python benchmark.py --pilot
python benchmark.py --counts 100 1000 --ticks 1500 --runs 3
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime-performance"


def percentile(values, fraction):
    ordered = sorted(values)
    position = (len(ordered)-1)*fraction
    lower = int(position)
    upper = min(lower+1, len(ordered)-1)
    return ordered[lower] + (ordered[upper]-ordered[lower])*(position-lower)


def summarize(output, options, case):
    groups = {}; header = None; current_run = None
    for line in output.splitlines():
        match = re.fullmatch(r"run (\d+):", line.strip())
        if match:
            current_run = int(match.group(1)); groups[current_run] = []
        elif line.startswith("tick,"):
            header = line.split(",")
        elif header and current_run and re.match(r"^t\d+,", line):
            fields = line.split(","); tick = int(fields[0][1:])
            if options.warmup < tick < options.ticks:
                groups[current_run].append({key: int(value)/1e6 for key, value in zip(header[2:], fields[2:]) if key})
    assert len(groups) == options.runs and all(len(rows) == options.ticks-options.warmup-1 for rows in groups.values())
    runs = []
    keys = ["wholeUpdate", "gameUpdate", "scriptUpdate", "entityUpdate", "luaGarbageIncremental", "AssemblingMachine", "Furnace",
            "electricHeatFluidCircuitUpdate", "transportLinesUpdate"]
    for number, rows in groups.items():
        whole = [row["wholeUpdate"] for row in rows]
        runs.append({"run": number, "samples": len(rows), "mean_ms": statistics.mean(whole),
                     "median_ms": statistics.median(whole), "p95_ms": percentile(whole, .95),
                     "p99_ms": percentile(whole, .99), "over_60ups_budget_fraction": sum(v>1000/60 for v in whole)/len(whole),
                     "timings_mean_ms": {key: statistics.mean(row[key] for row in rows) for key in keys}})
    median = statistics.median(run["mean_ms"] for run in runs)
    return {"case": dict(case), "runs": runs, "mean_ms": median, "maximum_simulated_ups": 1000/median,
            "run_mean_min_ms": min(run["mean_ms"] for run in runs), "run_mean_max_ms": max(run["mean_ms"] for run in runs),
            "p95_ms": statistics.median(run["p95_ms"] for run in runs),
            "timings_mean_ms": {key: statistics.median(run["timings_mean_ms"][key] for run in runs) for key in keys}}


def run_factorio(binary, args, log):
    command = [binary, "--config", str(RUNTIME / "config.ini"), "--mod-directory", str(RUNTIME / "mods"), *args]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    log.write_text(result.stdout + "\n" + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Factorio exited {result.returncode}: {log}\n" + "\n".join(log.read_text(encoding="utf-8").splitlines()[-35:]))
    return result.stdout, time.time() - started


def prepare(binary):
    for folder in ["mods", "logs", "saves", "scenarios", "script-output", "temp", "config", "maps", "archive"]:
        (RUNTIME / folder).mkdir(parents=True, exist_ok=True)
    for source, target in [(ROOT / "mod", RUNTIME / "mods/quality-upcycler_0.1.0"),
                           (ROOT / "performance-probe", RUNTIME / "mods/quality-upcycler-performance-probe_0.1.0")]:
        shutil.copytree(source, target, dirs_exist_ok=True)
    names = ["base", "elevated-rails", "recycler", "quality", "space-age", "quality-upcycler", "quality-upcycler-performance-probe"]
    (RUNTIME / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": True} for name in names]}), encoding="utf-8")
    data = Path(binary).resolve().parents[2] / "data"
    (RUNTIME / "config.ini").write_text(f"[path]\nread-data={data.as_posix()}\nwrite-data={RUNTIME.as_posix()}\n", encoding="utf-8")
    hashes = {p.relative_to(ROOT / "mod").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((ROOT / "mod").rglob("*")) if p.is_file()}
    (RUNTIME / "source-manifest.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")


def cases(options):
    if options.pilot:
        return [{"kind": "upcycler", "mode": "active", "item": "iron-gear-wheel", "count": 100}]
    result = [{"kind": "assembler", "mode": "idle", "item": "iron-gear-wheel", "count": 0}]
    for count in options.counts:
        for mode in ["idle", "active", "blocked"]:
            for kind in ["assembler", "upcycler", "recycler"]:
                result.append({"kind": kind, "mode": mode, "item": "iron-gear-wheel", "count": count})
    if options.stress:
        for kind in ["assembler", "upcycler", "recycler"]:
            result.append({"kind": kind, "mode": "active", "item": "iron-gear-wheel", "count": 5000})
    if options.extra:
        for item in ["processing-unit", "firearm-magazine", "bioflux"]:
            for kind in ["assembler", "upcycler"]:
                result.append({"kind": kind, "mode": "active", "item": item, "count": 1000})
        result.append({"kind": "vanilla", "mode": "active", "item": "iron-gear-wheel", "count": 1000})
    return result


def main():
    global RUNTIME
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", default="E:/steam/steamapps/common/Factorio/bin/x64/Factorio.exe")
    parser.add_argument("--counts", type=int, nargs="+", default=[100, 1000])
    parser.add_argument("--ticks", type=int, default=1500)
    parser.add_argument("--warmup", type=int, default=300)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--pilot", action="store_true")
    parser.add_argument("--stress", action="store_true")
    parser.add_argument("--extra", action="store_true")
    parser.add_argument("--filter", default="")
    parser.add_argument("--runtime", default="runtime-performance")
    options = parser.parse_args()
    RUNTIME = ROOT / options.runtime
    if options.pilot:
        options.ticks = 400; options.warmup = 120; options.runs = 1
    assert options.ticks > options.warmup > 60
    assert all(0 < n <= 5000 for n in options.counts)
    prepare(options.factorio)
    results_file = RUNTIME / "results.json"
    results = json.loads(results_file.read_text(encoding="utf-8")) if results_file.exists() else {}
    work = cases(options)
    for index, case in enumerate(work, 1):
        label = f"{case['kind']}-{case['mode']}-{case['item']}-{case['count']}"
        if options.filter and options.filter not in label:
            continue
        case.update(label=label, ticks=options.ticks, warmup=options.warmup)
        setting = RUNTIME / "mods/quality-upcycler-performance-probe_0.1.0/case.lua"
        setting.write_text("return {" + ",".join(f"{key}={json.dumps(value)}" for key, value in case.items()) + "}\n", encoding="utf-8")
        report_file = RUNTIME / f"script-output/performance-{label}.json"
        report_file.write_text("", encoding="utf-8")
        save = RUNTIME / f"maps/{label}.zip"
        print(f"[{index}/{len(work)}] Create {label}", flush=True)
        run_factorio(options.factorio, ["--create", str(save), "--map-gen-seed", "13579"], RUNTIME / f"logs/{label}-create.log")
        print(f"[{index}/{len(work)}] Benchmark {label}: {options.runs} x {options.ticks} ticks", flush=True)
        output, elapsed = run_factorio(options.factorio, ["--benchmark", str(save), "--benchmark-ticks", str(options.ticks+1),
                                    "--benchmark-runs", str(options.runs), "--benchmark-verbose", "all"],
                                      RUNTIME / f"logs/{label}-benchmark.log")
        verification = json.loads(report_file.read_text(encoding="utf-8-sig"))
        result = summarize(output, options, case)
        result["verification"] = verification
        results[label] = result
        results_file.write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(f"  elapsed={elapsed:.2f}s, rate={verification['crafts_per_machine_per_second']:.3f} crafts/machine/s", flush=True)
        print(f"  steady median of run means={result['mean_ms']:.4f} ms/tick, upper UPS={result['maximum_simulated_ups']:.1f}, "
              f"scriptUpdate={result['timings_mean_ms']['scriptUpdate']:.4f} ms", flush=True)


if __name__ == "__main__":
    main()
