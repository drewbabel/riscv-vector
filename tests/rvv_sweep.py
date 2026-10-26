#!/usr/bin/env python3

import argparse
import concurrent.futures
import csv
import glob
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COSIM = os.path.join(ROOT, "tests", "cosim.py")
OUT = os.path.join(ROOT, "build", "rvv")
VERDICTS = ("PASS", "DIVERGE", "TRAP", "HUNG")


def insn_name(test):
    return test.rsplit("-", 1)[0].replace("_", ".")


def call(cmd, timeout):
    try:
        r = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return "HUNG wall clock timeout"
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    if lines:
        return lines[-1]
    err = [l for l in r.stderr.splitlines() if l.strip()]
    return "ERROR " + (err[-1] if err else f"exit {r.returncode}")


def pool(jobs, work, items):
    done = 0
    with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
        futs = {ex.submit(work, item): item for item in items}
        for fut in concurrent.futures.as_completed(futs):
            done += 1
            yield done, len(futs), futs[fut], fut.result()


# Spike traces
def prep(args):
    srcs = sorted(glob.glob(os.path.join(args.stage2, "*.S")))
    if args.match:
        srcs = [s for s in srcs if re.search(args.match, os.path.basename(s))]
    if not srcs:
        sys.exit(f"no tests in {args.stage2}")
    os.makedirs(OUT, exist_ok=True)

    def work(src):
        name = os.path.splitext(os.path.basename(src))[0]
        return call(
            [
                sys.executable,
                COSIM,
                "--gen-spike",
                src,
                os.path.join(OUT, name),
            ],
            args.timeout,
        )

    rows = []
    for k, n, src, line in pool(args.jobs, work, srcs):
        name = os.path.splitext(os.path.basename(src))[0]
        f = line.split()
        ok = len(f) >= 5 and f[0] == "SPIKE"
        rows.append(
            [
                insn_name(name),
                name,
                f[2] if ok else "",
                f[4][4:] if ok else line,
            ]
        )
        print(f"[{k}/{n}] {name} {line}", flush=True)
    rows.sort(key=lambda r: r[1])
    with open(os.path.join(OUT, "manifest.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["instruction", "test", "spike_instrs", "end"])
        w.writerows(rows)
    insns = {r[0] for r in rows}
    ends = {}
    for r in rows:
        ends[r[3]] = ends.get(r[3], 0) + 1
    print(f"{len(rows)} tests over {len(insns)} instructions, ends {ends}")


# DUT lockstep runs
def run(args):
    r = subprocess.run(
        [sys.executable, COSIM, "--compile"], cwd=ROOT, check=False
    )
    if r.returncode:
        sys.exit("monitor compile failed")
    tests = sorted(
        d
        for d in os.listdir(OUT)
        if os.path.exists(os.path.join(OUT, d, "spike.json.gz"))
    )
    if args.match:
        tests = [t for t in tests if re.search(args.match, t)]
    if not tests:
        sys.exit(f"no prepared tests in {OUT}")
    extra = ["--cycles", str(args.cycles)] if args.cycles else []

    def work(test):
        return call(
            [
                sys.executable,
                COSIM,
                "--gen-dut",
                os.path.join(OUT, test),
                "--no-compile",
                *extra,
            ],
            args.timeout,
        )

    rows = []
    counts = {}
    t0 = time.time()
    with open(args.csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["instruction", "test", "result", "detail"])
        for k, n, test, line in pool(args.jobs, work, tests):
            verdict, _, detail = line.partition(" ")
            if verdict not in VERDICTS:
                verdict, detail = "ERROR", line
            row = [insn_name(test), test, verdict, detail]
            rows.append(row)
            w.writerow(row)
            fh.flush()
            counts[verdict] = counts.get(verdict, 0) + 1
            print(f"[{k}/{n}] {test} {verdict} {detail}"[:200], flush=True)
    rows.sort(key=lambda r: r[1])
    with open(args.csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["instruction", "test", "result", "detail"])
        w.writerows(rows)
    print(
        f"{len(rows)} tests in {time.time() - t0:.0f}s {counts} -> {args.csv}"
    )


# Trap probe images
def probe_prep(args):
    srcs = sorted(glob.glob(os.path.join(args.stage2, "*.S")))
    if args.match:
        srcs = [s for s in srcs if re.search(args.match, os.path.basename(s))]

    def work(src):
        name = os.path.splitext(os.path.basename(src))[0]
        return call(
            [
                sys.executable,
                COSIM,
                "--gen-probe-build",
                src,
                os.path.join(OUT, name),
            ],
            args.timeout,
        )

    for k, n, src, line in pool(args.jobs, work, srcs):
        if line != "BUILT":
            print(f"[{k}/{n}] {src} {line}", flush=True)
    print(f"{len(srcs)} probe images")


# Trap probe runs
def probe(args):
    r = subprocess.run(
        [sys.executable, COSIM, "--compile"], cwd=ROOT, check=False
    )
    if r.returncode:
        sys.exit("monitor compile failed")
    tests = sorted(
        d
        for d in os.listdir(OUT)
        if os.path.exists(os.path.join(OUT, d, "probe.hex"))
    )
    if args.match:
        tests = [t for t in tests if re.search(args.match, t)]

    def work(test):
        return call(
            [
                sys.executable,
                COSIM,
                "--gen-probe",
                os.path.join(OUT, test),
                "--no-compile",
            ],
            args.timeout,
        )

    rows = []
    for k, n, test, line in pool(args.jobs, work, tests):
        end, _, words = line.partition(" ")
        rows.append([insn_name(test), test, end, words])
        print(f"[{k}/{n}] {test} {end}", flush=True)
    rows.sort(key=lambda r: r[1])
    with open(args.csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["instruction", "test", "end", "words"])
        w.writerows(rows)
    print(f"{len(rows)} tests -> {args.csv}")


def main():
    ap = argparse.ArgumentParser(
        description="Generated RVV tests against Spike"
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prep", help="build images and save Spike traces")
    p.add_argument("stage2", help="generator tests/stage2 directory")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    p.add_argument("--match", help="regex on test name")
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=prep)
    p = sub.add_parser("run", help="DUT runs against saved traces")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    p.add_argument("--csv", default=os.path.join(OUT, "results.csv"))
    p.add_argument("--match", help="regex on test name")
    p.add_argument("--cycles", type=int, help="fixed cycle budget")
    p.add_argument("--timeout", type=int, default=7200, help="seconds per test")
    p.set_defaults(func=run)
    p = sub.add_parser("probe-prep", help="build images that step over traps")
    p.add_argument("stage2", help="generator tests/stage2 directory")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    p.add_argument("--match", help="regex on test name")
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=probe_prep)
    p = sub.add_parser("probe", help="count retired and trapped vector words")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    p.add_argument("--csv", default=os.path.join(OUT, "probe.csv"))
    p.add_argument("--match", help="regex on test name")
    p.add_argument("--timeout", type=int, default=7200, help="seconds per test")
    p.set_defaults(func=probe)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
