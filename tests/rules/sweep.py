#!/usr/bin/env python3
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check

ROOT = check.ROOT
TABLE = os.path.join(check.HERE, "sweep.txt")
VLT = os.path.join(check.HERE, "lint.vlt")
DIRECTED = os.path.join(ROOT, "tests", "cosim_directed.txt")
COPY = ("rtl", "tb", "tests", "formal", "sw", "Makefile")


class Row:
    def __init__(self, no, module, bench, settings, expect):
        self.no = no
        self.module = module
        self.bench = bench
        self.header = {}
        self.pkg = {}
        for s in settings:
            k, v = s.split("=", 1)
            if "::" in k:
                self.pkg[k] = v
            else:
                self.header[k] = v
        self.expect = expect
        self.lint = None
        self.notes = []
        self.params = None
        self.covered = None
        self.bench_ok = None
        self.secs = 0.0

    @property
    def key(self):
        return tuple(sorted(self.pkg.items()))

    @property
    def label(self):
        s = [f"{k}={v}" for k, v in sorted(self.pkg.items())] + [
            f"{k}={v}" for k, v in sorted(self.header.items())
        ]
        return f"{self.module} {','.join(s) or 'defaults'}"

    def verdict(self):
        if self.expect:
            return self.lint == "guard"
        return self.lint == "clean" and self.covered and self.bench_ok


def load_table(path=TABLE):
    rows = []
    with open(path) as f:
        for no, line in enumerate(f, 1):
            parts = shlex.split(line)
            if not parts:
                continue
            module, bench, settings = parts[0], parts[1], parts[2]
            expect = None
            for p in parts[3:]:
                if p.startswith("expect="):
                    expect = p[len("expect=") :]
            sets = [] if settings == "-" else settings.split(",")
            rows.append(Row(no, module, bench, sets, expect))
    return rows


def make_tree(pkg):
    tree = tempfile.mkdtemp(prefix="sweep.")
    for f in check.tracked():
        if f.split("/")[0] not in COPY:
            continue
        dst = os.path.join(tree, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), dst)
    os.makedirs(os.path.join(tree, "build"), exist_ok=True)
    for f in os.listdir(os.path.join(tree, "tb")):
        if not f.endswith(".sv"):
            continue
        with open(os.path.join(tree, "tb", f)) as h:
            for name in re.findall(r'\$dumpfile\s*\(\s*"([^"]+)"', h.read()):
                dump = os.path.join(tree, name)
                if not os.path.lexists(dump):
                    os.symlink(os.devnull, dump)
    tf = os.path.join(ROOT, "build", "testfloat")
    if os.path.isdir(tf):
        os.symlink(tf, os.path.join(tree, "build", "testfloat"))
    for k, v in pkg.items():
        name_pkg, name = k.split("::")
        path = os.path.join(tree, "rtl", f"{name_pkg}.sv")
        with open(path) as f:
            text = f.read()
        new, n = re.subn(
            rf"(parameter\s+[^;=]*\b{re.escape(name)}\s*=\s*)[^;]+;",
            rf"\g<1>{v};",
            text,
        )
        if n != 1:
            raise SystemExit(f"cannot override {k}: {n} declarations")
        with open(path, "w") as f:
            f.write(new)
    vlen = package_value(tree, "arch_pkg", "VLEN")
    cos = os.path.join(tree, "tests", "cosim.py")
    if vlen and os.path.exists(cos):
        with open(cos) as f:
            text = f.read()
        with open(cos, "w") as f:
            f.write(text.replace("zvl128b", f"zvl{vlen}b"))
    return tree


def package_value(tree, pkg, name):
    with open(os.path.join(tree, "rtl", f"{pkg}.sv")) as f:
        m = re.search(rf"\b{name}\s*=\s*(\d+)\s*;", f.read())
    return m.group(1) if m else None


def run(cmd, cwd, timeout=None, env=None):
    try:
        r = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            env=env,
        )
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        return (
            124,
            f"timeout after {timeout}s\n{e.stdout or ''}{e.stderr or ''}",
        )


def module_file(tree, module):
    for sub in (
        "rtl",
        "rtl/single_cycle",
        "rtl/boards/bram",
        "rtl/boards/nexys_video",
    ):
        p = os.path.join(sub, module + ".sv")
        if os.path.exists(os.path.join(tree, p)):
            return p
    return None


def lint(row, tree):
    src = module_file(tree, row.module)
    if src is None:
        row.lint = "missing"
        row.notes.append(f"no rtl file for {row.module}")
        return
    board = (
        "rtl/boards/nexys_video" if "nexys_video" in src else "rtl/boards/bram"
    )
    cmd = [
        "verilator",
        "--lint-only",
        "-Wall",
        "-Wno-TIMESCALEMOD",
        VLT,
        "--top-module",
        row.module,
        *[f"-G{k}={v}" for k, v in row.header.items()],
        "-y",
        "rtl",
        "-y",
        board,
        "-y",
        "rtl/single_cycle",
        "+libext+.v+.sv",
        *check.PKGS,
        src,
    ]
    rc, out = run(cmd, tree, timeout=900)
    msgs = [
        l
        for l in out.splitlines()
        if l.startswith("%") and not l.startswith("%Error: Exiting due to")
    ]
    guards = [
        l
        for l in msgs
        if "USERERROR" in l or l.startswith("%Error: ") and "$error" in l
    ]
    if row.expect:
        if any(row.expect in l for l in guards):
            row.lint = "guard"
        else:
            row.lint = "unguarded" if rc else "elaborated"
            row.notes += (guards or msgs)[:6] or ["elaborated with no $error"]
        return
    if rc == 0 and not msgs:
        row.lint = "clean"
    else:
        row.lint = (
            "warnings"
            if rc == 0 or all(m.startswith("%Warning") for m in msgs)
            else "error"
        )
        kinds = {}
        for m in msgs:
            k = m.split(":", 1)[0]
            kinds[k] = kinds.get(k, 0) + 1
        row.notes.append(
            "lint " + ", ".join(f"{k} x{n}" for k, n in sorted(kinds.items()))
        )
        row.notes += [
            m for m in msgs if "USERERROR" in m or m.startswith("%Error")
        ][:4]


def top_params(row, tree, tmp):
    src = module_file(tree, row.module)
    if src is None:
        return None
    out = os.path.join(tmp, f"top_{row.no}.json")
    data, log = check.slang_json(
        row.module,
        check.rtl_files(tree) + [src] * (src not in check.rtl_files(tree)),
        [],
        out,
        root=tree,
        extra=[x for k, v in row.header.items() for x in ("-G", f"{k}={v}")]
        + ["--ignore-unknown-modules", "--ast-json-scope", row.module],
    )
    if data is None:
        row.notes.append(
            "slang could not elaborate the module: " + log.strip()[:200]
        )
        return None
    found = []
    check.jwalk(
        data,
        lambda x: (
            found.append(x)
            if x.get("kind") == "Instance" and x.get("name") == row.module
            else None
        ),
    )
    return header_values(found[0].get("body"), {}) if found else None


def header_values(body, bodies):
    if isinstance(body, str):
        body = bodies.get(check.sym_addr(body), {})
    out = {}
    for m in body.get("members", []) if isinstance(body, dict) else []:
        if m.get("kind") == "Parameter" and not m.get("isLocal"):
            out[m["name"]] = norm(m.get("value"))
    return out


def norm(v):
    n = check.sv_number(str(v)) if v is not None else None
    return str(n) if n is not None else str(v)


def bench_instances(tree, bench, tmp, cache):
    key = (tree, bench)
    if key in cache:
        return cache[key]
    path = f"tb/{bench}.sv" if bench == "cosim" else f"tb/{bench}_tb.sv"
    if not os.path.exists(os.path.join(tree, path)):
        cache[key] = None
        return None
    srcs, defs = check.bench_build(path, tree)
    top = os.path.basename(path)[:-3]
    data, _ = check.slang_json(
        top,
        srcs + [path],
        defs,
        os.path.join(tmp, f"b_{abs(hash(key))}.json"),
        root=tree,
    )
    found = {}
    if data is not None:
        bodies = {}
        check.jwalk(
            data,
            lambda x: (
                bodies.__setitem__(str(x["addr"]), x)
                if x.get("kind") == "InstanceBody" and "addr" in x
                else None
            ),
        )
        insts = []
        check.jwalk(
            data,
            lambda x: insts.append(x) if x.get("kind") == "Instance" else None,
        )
        for i in insts:
            b = i.get("body")
            b = (
                bodies.get(check.sym_addr(b), {})
                if isinstance(b, str)
                else b or {}
            )
            d = (
                check.sym_addr(b.get("definition", ""))
                and b.get("definition", "").split(" ", 1)[-1]
            )
            if d:
                found.setdefault(d, []).append(header_values(b, bodies))
    cache[key] = found
    return found


def run_bench(tree, bench):
    if bench.startswith("formal:"):
        name = bench.split(":", 1)[1]
        rc, out = run(["make", "formal", f"MOD={name}"], tree, timeout=21600)
        return rc == 0, [] if rc == 0 else [f"{bench}: {last_line(out)}"]
    if bench == "cosim":
        fails = []
        with open(os.path.join(tree, "tests", "cosim_directed.txt")) as f:
            progs = [shlex.split(l) for l in f if l.strip()]
        for args in progs:
            rc, out = run(
                [sys.executable, "tests/cosim.py", *args], tree, timeout=3600
            )
            if rc:
                fails.append(f"cosim {' '.join(args)}: {last_line(out)}")
        return not fails, fails
    rc, out = run(
        ["make", "run", f"MOD={bench}", f"SIM=build/sim_{bench}"],
        tree,
        timeout=5400,
    )
    ok = rc == 0 and not re.search(r"FAIL|UNDER-RAN|STOPPED", out)
    return ok, [] if ok else [f"bench {bench}: {last_line(out)}"]


def last_line(out):
    ls = [l for l in out.strip().splitlines() if l.strip()]
    for l in reversed(ls):
        if re.search(
            r"FAIL|UNDER-RAN|STOPPED|rror|mismatch|diverge|timeout", l
        ):
            return l.strip()[:200]
    return ls[-1].strip()[:200] if ls else "no output"


def sweep(rows, jobs, benches=True):
    tmp = tempfile.mkdtemp(prefix="sweep.json.")
    groups = {}
    for r in rows:
        groups.setdefault(r.key, []).append(r)
    trees = {k: make_tree(dict(k)) for k in groups}

    def lint_one(r):
        t0 = time.time()
        lint(r, trees[r.key])
        if not r.expect:
            r.params = top_params(r, trees[r.key], tmp)
        r.secs += time.time() - t0

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(lint_one, rows))
    cache = {}
    for r in rows:
        if r.expect:
            continue
        if r.bench == "none":
            r.covered = False
            r.notes.append("no bench names this module")
            continue
        if r.bench.startswith("formal:"):
            r.covered = not r.header
            if r.header:
                r.notes.append("formal wrappers take package sizes only")
            continue
        found = bench_instances(trees[r.key], r.bench, tmp, cache)
        if found is None:
            r.covered = False
            r.notes.append(f"no bench file for {r.bench}")
            continue
        insts = found.get(r.module, [])
        want = r.params or {}
        r.covered = any(
            all(i.get(k) == v for k, v in want.items()) for i in insts
        )
        if not r.covered:
            seen = sorted(
                {
                    ",".join(
                        f"{k}={v}" for k, v in sorted(i.items()) if k in want
                    )
                    for i in insts
                }
            )
            r.notes.append(
                f"{r.bench} has no {r.module} at {','.join(f'{k}={v}' for k, v in sorted(want.items()))}"
                + (f" (has {'; '.join(seen)})" if seen else " (no instance)")
            )
    todo = sorted(
        {
            (r.key, r.bench)
            for r in rows
            if not r.expect and r.covered and benches
        }
    )
    results = {}

    def bench_one(item):
        t0 = time.time()
        ok, notes = run_bench(trees[item[0]], item[1])
        results[item] = (ok, notes, time.time() - t0)

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(bench_one, todo))
    for r in rows:
        if r.expect or not r.covered:
            continue
        if not benches:
            r.bench_ok = True
            continue
        ok, notes, secs = results[(r.key, r.bench)]
        r.bench_ok = ok
        r.notes += notes
        r.secs += secs
    return trees


def is_heavy(r):
    return not r.expect and (
        r.bench == "cosim" or r.bench.startswith("formal:")
    )


def groups_json(rows, n):
    heavy = [r for r in rows if is_heavy(r)]
    light = sorted({r.module for r in rows} - set())
    out = [[f"{r.module}#{r.no}"] for r in heavy]
    rest = [[] for _ in range(n)]
    for i, m in enumerate(light):
        rest[i % n].append(m)
    return out + [g for g in rest if g]


def select(rows, picks):
    if not picks:
        return rows
    out = []
    heavy = {f"{r.module}#{r.no}" for r in rows if is_heavy(r)}
    for r in rows:
        tag = f"{r.module}#{r.no}"
        if tag in picks or (r.module in picks and tag not in heavy):
            out.append(r)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "picks", nargs="*", help="modules, or module#line for one row"
    )
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument(
        "--list", type=int, metavar="N", help="print N CI groups as JSON"
    )
    ap.add_argument("--lint-only", action="store_true")
    ap.add_argument("--json", help="write row results here")
    args = ap.parse_args()
    rows = load_table()
    if args.list:
        print(json.dumps([" ".join(g) for g in groups_json(rows, args.list)]))
        return 0
    rows = select(rows, set(args.picks))
    sweep(rows, args.jobs, benches=not args.lint_only)
    bad = 0
    for r in sorted(rows, key=lambda r: r.no):
        ok = r.verdict()
        bad += not ok
        want = f"guard '{r.expect}'" if r.expect else "clean"
        print(
            f"{'PASS' if ok else 'FAIL'} sweep.txt:{r.no} {r.label} expect {want} lint {r.lint} {r.secs:.0f}s"
        )
        if not ok:
            for n in r.notes:
                print(f"    {n}")
    if args.json:
        with open(args.json, "w") as f:
            json.dump(
                [
                    {
                        "line": r.no,
                        "row": r.label,
                        "expect": r.expect,
                        "lint": r.lint,
                        "covered": r.covered,
                        "bench": r.bench_ok,
                        "pass": r.verdict(),
                        "notes": r.notes,
                        "secs": round(r.secs),
                    }
                    for r in rows
                ],
                f,
                indent=1,
            )
    print(
        f"{len(rows) - bad} of {len(rows)} configurations pass", file=sys.stderr
    )
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
