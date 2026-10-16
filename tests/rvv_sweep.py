#!/usr/bin/env python3

import argparse
import collections
import concurrent.futures
import csv
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COSIM = os.path.join(ROOT, "tests", "cosim.py")
OUT = os.path.join(ROOT, "build", "rvv")
VERDICTS = ("PASS", "DIVERGE", "TRAP", "HUNG")
STATUS = os.path.join(ROOT, "tests", "rvv_status.csv")
SEG_RE = re.compile(r"(v[a-z]+seg)2-8(e|ei)(\d+)(ff)?\.v")
PSEUDO = {
    "vl1r.v": ["vl1re8.v"],
    "vl2r.v": ["vl2re8.v"],
    "vl4r.v": ["vl4re8.v"],
    "vl8r.v": ["vl8re8.v"],
    "vle1.v": ["vlm.v"],
    "vse1.v": ["vsm.v"],
    "vmsge.vi": ["vmsgt.vi"],
    "vmsge.vv": ["vmsle.vv"],
    "vmsge.vx": ["vmslt.vx", "vmnand.mm", "vmxor.mm", "vmandn.mm", "vmor.mm"],
    "vmsgeu.vi": ["vmsgtu.vi"],
    "vmsgeu.vv": ["vmsleu.vv"],
    "vmsgeu.vx": ["vmsltu.vx", "vmnand.mm", "vmxor.mm", "vmandn.mm", "vmor.mm"],
    "vmsgt.vv": ["vmslt.vv"],
    "vmsgtu.vv": ["vmsltu.vv"],
    "vmslt.vi": ["vmsle.vi"],
    "vmsltu.vi": ["vmsleu.vi"],
    "vncvt.x.x.w": ["vnsrl.wx"],
    "vneg.v": ["vrsub.vx"],
    "vnot.v": ["vxor.vi"],
    "vwcvt.x.x.v": ["vwadd.vx"],
    "vwcvtu.x.x.v": ["vwaddu.vx"],
    "vfabs.v": ["vfsgnjx.vv"],
    "vfneg.v": ["vfsgnjn.vv"],
    "vfrece7.v": ["vfrec7.v"],
    "vfrsqrte7.v": ["vfrsqrt7.v"],
    "vmfge.vv": ["vmfle.vv"],
    "vmfgt.vv": ["vmflt.vv"],
    "vfredsum.vs": ["vfredusum.vs"],
    "vfwredsum.vs": ["vfwredusum.vs"],
    "vmandnot.mm": ["vmandn.mm"],
    "vmclr.m": ["vmxor.mm"],
    "vmcpy.m": ["vmand.mm"],
    "vmmv.m": ["vmand.mm"],
    "vmnot.m": ["vmnand.mm"],
    "vmornot.mm": ["vmorn.mm"],
    "vmset.m": ["vmxnor.mm"],
    "vpopc.m": ["vcpop.m"],
}


def insn_name(test):
    return test.rsplit("-", 1)[0].replace("_", ".")


def call(cmd, timeout):
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
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


def prep(args):
    srcs = sorted(glob.glob(os.path.join(args.stage2, "*.S")))
    if args.match:
        srcs = [s for s in srcs if re.search(args.match, os.path.basename(s))]
    if not srcs:
        sys.exit(f"no tests in {args.stage2}")
    os.makedirs(OUT, exist_ok=True)

    def work(src):
        name = os.path.splitext(os.path.basename(src))[0]
        return call([sys.executable, COSIM, "--gen-spike", src, os.path.join(OUT, name)],
                    args.timeout)

    rows = []
    for k, n, src, line in pool(args.jobs, work, srcs):
        name = os.path.splitext(os.path.basename(src))[0]
        f = line.split()
        ok = len(f) >= 5 and f[0] == "SPIKE"
        rows.append([insn_name(name), name, f[2] if ok else "", f[4][4:] if ok else line])
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


def run(args):
    r = subprocess.run([sys.executable, COSIM, "--compile"], cwd=ROOT)
    if r.returncode:
        sys.exit("monitor compile failed")
    tests = sorted(d for d in os.listdir(OUT)
                   if os.path.exists(os.path.join(OUT, d, "spike.json.gz")))
    if args.match:
        tests = [t for t in tests if re.search(args.match, t)]
    if not tests:
        sys.exit(f"no prepared tests in {OUT}")
    extra = ["--cycles", str(args.cycles)] if args.cycles else []

    def work(test):
        return call([sys.executable, COSIM, "--gen-dut", os.path.join(OUT, test),
                     "--no-compile", *extra], args.timeout)

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
    print(f"{len(rows)} tests in {time.time() - t0:.0f}s {counts} -> {args.csv}")


def probe_prep(args):
    srcs = sorted(glob.glob(os.path.join(args.stage2, "*.S")))
    if args.match:
        srcs = [s for s in srcs if re.search(args.match, os.path.basename(s))]

    def work(src):
        name = os.path.splitext(os.path.basename(src))[0]
        return call([sys.executable, COSIM, "--gen-probe-build", src, os.path.join(OUT, name)],
                    args.timeout)

    for k, n, src, line in pool(args.jobs, work, srcs):
        if line != "BUILT":
            print(f"[{k}/{n}] {src} {line}", flush=True)
    print(f"{len(srcs)} probe images")


def probe(args):
    r = subprocess.run([sys.executable, COSIM, "--compile"], cwd=ROOT)
    if r.returncode:
        sys.exit("monitor compile failed")
    tests = sorted(d for d in os.listdir(OUT) if os.path.exists(os.path.join(OUT, d, "probe.hex")))
    if args.match:
        tests = [t for t in tests if re.search(args.match, t)]

    def work(test):
        return call([sys.executable, COSIM, "--gen-probe", os.path.join(OUT, test),
                     "--no-compile"], args.timeout)

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


def disassemble(words):
    d = tempfile.mkdtemp()
    src, obj = os.path.join(d, "w.s"), os.path.join(d, "w.o")
    with open(src, "w") as f:
        f.writelines(f".insn 4, 0x{w}\n" for w in words)
    subprocess.run(["riscv64-elf-as", "-march=rv32gcv", "-o", obj, src], check=True)
    out = subprocess.run(["riscv64-elf-objdump", "-d", "-M", "no-aliases", obj],
                         capture_output=True, text=True, check=True).stdout
    names = {}
    for line in out.splitlines():
        m = re.match(r"\s+[0-9a-f]+:\s+([0-9a-f]{8})\s+(\S+)", line)
        if m:
            names[m.group(1)] = m.group(2)
    return names


def verdict(lock, ran, trapped):
    bad = next((f"{k}: {d}" for k, d in lock if k in ("DIVERGE", "HUNG", "ERROR")), None)
    if bad:
        return "Differs from Spike", bad[:300]
    if trapped and ran:
        return "Differs from Spike", f"Traps at {trapped} of its {ran + trapped} executions."
    if trapped:
        return "Not built", ""
    helper = next((k.split()[1] for k, _ in lock if k.startswith("HELPER")), None)
    if helper:
        return "Not run", f"Its test needs {helper}, which the core traps."
    if lock and {k for k, _ in lock} == {"PASS"}:
        return "Matches Spike", ""
    return "Not run", ""


def status(args):
    results = list(csv.DictReader(open(args.results)))
    probe = {r["test"]: r for r in csv.DictReader(open(args.probe))}
    missing = {r["test"] for r in results} - set(probe)
    if missing:
        sys.exit(f"no probe result for {len(missing)} tests, e.g. {sorted(missing)[0]}")
    hung = [t for t, r in probe.items() if r["end"] != "DONE"]
    if hung:
        sys.exit(f"probe did not finish {len(hung)} tests, e.g. {hung[0]}")

    words = {re.search(r"insn=([0-9a-f]+)", r["detail"]).group(1)
             for r in results if r["result"] == "TRAP"}
    for r in probe.values():
        words |= set(json.loads(r["words"]))
    names = disassemble(sorted(words))

    lock = collections.defaultdict(list)
    for r in results:
        v = r["result"]
        if v == "TRAP":
            mn = names.get(re.search(r"insn=([0-9a-f]+)", r["detail"]).group(1), "?")
            if mn != r["instruction"]:
                v = "HELPER " + mn
        lock[r["instruction"]].append((v, r["detail"]))
    runs = collections.defaultdict(lambda: [0, 0])
    for r in probe.values():
        for w, (ret, trap) in json.loads(r["words"]).items():
            if names.get(w) == r["instruction"]:
                runs[r["instruction"]][0] += ret
                runs[r["instruction"]][1] += trap

    rows = list(csv.DictReader(open(STATUS)))
    for row in rows:
        if row["Instruction"] in PSEUDO:
            continue
        m = SEG_RE.match(row["Instruction"])
        keys = ([f"{m.group(1)}{nf}{m.group(2)}{m.group(3)}{m.group(4) or ''}.v"
                 for nf in range(2, 9)] if m else [row["Instruction"]])
        ls = [x for k in keys for x in lock.get(k, [])]
        ran = sum(runs[k][0] for k in keys if k in runs)
        trapped = sum(runs[k][1] for k in keys if k in runs)
        row["Status"], row["Notes"] = verdict(ls, ran, trapped)
    by_name = {row["Instruction"]: row["Status"] for row in rows}
    for row in rows:
        if row["Instruction"] in PSEUDO:
            got = [by_name[k] for k in PSEUDO[row["Instruction"]]]
            row["Status"] = "Matches Spike" if set(got) == {"Matches Spike"} else got[0]
    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["Instruction", "Group", "Subset", "Status", "Notes"],
                           lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    counts = collections.Counter(row["Status"] for row in rows)
    print(f"{len(rows)} instructions {dict(counts)} -> {args.out}")


def main():
    ap = argparse.ArgumentParser(description="Generated RVV tests against Spike")
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
    p = sub.add_parser("status", help="rewrite the instruction status list")
    p.add_argument("--results", default=os.path.join(OUT, "results.csv"))
    p.add_argument("--probe", default=os.path.join(OUT, "probe.csv"))
    p.add_argument("--out", default=STATUS)
    p.set_defaults(func=status)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
