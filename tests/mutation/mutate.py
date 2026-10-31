#!/usr/bin/env python3
# Mutation cover per module

import datetime
import glob
import json
import math
import os
import re
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.insert(0, os.path.join(ROOT, "tests", "rules"))
import check

MUTANTS = 100  # Per module
SEED = 1
FLOOR = 90.0  # Percent killed
SHARDS = 1  # Bench only start
COSIM_SHARDS = 10
TARGET_MIN = 60
STOP_MIN = 70  # Shard self stop
EQ_SEC = 120
BENCH_SLACK = 4  # Times baseline
WORK = os.path.join(ROOT, "build", "mutation")
LIB_DEF = []
BENCH_DEF = []


def read(path):
    with open(path, errors="replace") as f:
        return f.read()


def modules():
    out = []
    pat = os.path.join(ROOT, "rtl", "**", "*.sv")
    for f in sorted(glob.glob(pat, recursive=True)):
        rel = os.path.relpath(f, ROOT)
        if rel.startswith("rtl/boards/") or rel.endswith("_pkg.sv"):
            continue
        out.append((os.path.basename(f)[:-3], rel))
    return out


def rtl_path(mod):
    return dict(modules())[mod]


def bench_file(mod):
    return os.path.join(ROOT, "tb", f"{mod}_tb.sv")


def has_bench(mod):
    return os.path.isfile(bench_file(mod))


def inst_type(text, inst):
    m = re.search(rf"\b{re.escape(inst)}\s*\(", text)
    if not m:
        return None
    i = m.start() - 1
    while i >= 0 and text[i].isspace():
        i -= 1
    if text[i] == ")":
        depth = 0
        while i >= 0:
            depth += {")": 1, "(": -1}.get(text[i], 0)
            if depth == 0:
                break
            i -= 1
        i -= 1
        while i >= 0 and text[i].isspace():
            i -= 1
        if text[i] == check.HASH:
            i -= 1
    t = re.search(r"(\w+)\s*$", text[: i + 1])
    return t.group(1) if t else None


# Modules cosim reads into
def cosim_modules():
    text = read(os.path.join(ROOT, "tb", "cosim.sv"))
    files = dict(modules())
    found = set()
    for path in re.findall(r"\b\w+_inst(?:\.\w+(?:\[[^\]]*\])?)+", text):
        parent = text
        for inst in re.sub(r"\[[^\]]*\]", "", path).split("."):
            mod = inst_type(parent, inst)
            if mod not in files:
                break
            found.add(mod)
            parent = read(os.path.join(ROOT, files[mod]))
    return found


def uses_testfloat(mod):
    return has_bench(mod) and "testfloat" in read(bench_file(mod))


def last_timing():
    grow = {}
    api = os.environ.get("GITHUB_API_URL")
    repo = os.environ.get("GITHUB_REPOSITORY")
    token = os.environ.get("GH_TOKEN")
    if not (api and repo and token):
        return grow
    base = f"{api}/repos/{repo}/actions"

    def get(url):
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {token}"}
        )
        return json.load(urllib.request.urlopen(req, timeout=30))

    def stamp(t):
        return datetime.datetime.fromisoformat(t)

    name = re.compile(r"^mutation (\w+) (\d+) of (\d+)$")
    try:
        url = f"{base}/workflows/ci.yml/runs?status=completed&per_page=20"
        for run in get(url)["workflow_runs"]:
            page, seen = 1, False
            while True:
                jobs = get(
                    f"{base}/runs/{run['id']}/jobs?per_page=100&page={page}"
                )["jobs"]
                for j in jobs:
                    m = name.match(j["name"])
                    if not m or not j.get("completed_at"):
                        continue
                    seen = True
                    mod, of = m.group(1), int(m.group(3))
                    took = stamp(j["completed_at"]) - stamp(j["started_at"])
                    mins = took.total_seconds() / 60
                    n = math.ceil(of * mins / TARGET_MIN)
                    if mins >= STOP_MIN or j["conclusion"] == "cancelled":
                        n = 2 * of
                    grow[mod] = max(grow.get(mod, 0), n)
                if len(jobs) < 100:
                    break
                page += 1
            if seen:
                break
    except (OSError, ValueError, KeyError) as e:
        print(f"no shard timing: {e}", file=sys.stderr)
    return grow


def cmd_list():
    cos = cosim_modules()
    grow = last_timing()
    items = []
    for mod, _ in modules():
        bench, cosim = has_bench(mod), mod in cos
        if not bench:
            print(f"no bench: {mod}", file=sys.stderr)
        if not (bench or cosim):
            continue
        n = max(COSIM_SHARDS if cosim else SHARDS, grow.get(mod, 0))
        for k in range(n):
            items.append(
                {
                    "mod": mod,
                    "shard": k,
                    "of": n,
                    "cosim": cosim,
                    "testfloat": uses_testfloat(mod),
                }
            )
    print(json.dumps(items))
    return 0


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def bench_defines():
    text = read(os.path.join(ROOT, "Makefile"))
    m = re.search(r"^run:.*?\n((?:\t.*\n)+)", text, re.MULTILINE)
    line = next(l for l in m.group(1).splitlines() if "iverilog" in l)
    return set(re.findall(r"-D(\w+)", line))


def cosim_defines():
    text = read(os.path.join(ROOT, "tests", "cosim.py"))
    body = re.search(
        r"^def compile_monitor\b.*?(?=^def )", text, re.MULTILINE | re.DOTALL
    )
    return set(re.findall(r'"-D(\w+)"', body.group(0)))


# Defines its tests compile
def use_defines(mod):
    bench = sorted(bench_defines()) if has_bench(mod) else []
    cos = sorted(cosim_defines()) if mod in cosim_modules() else []
    LIB_DEF[:] = cos or bench
    BENCH_DEF[:] = bench if bench != LIB_DEF else []


def lib_dir(defs=None):
    defs = LIB_DEF if defs is None else defs
    lib = os.path.join(WORK, "lib-" + "-".join(defs))
    if not os.path.isdir(lib):
        os.makedirs(WORK, exist_ok=True)
        tmp = tempfile.mkdtemp(prefix="lib", dir=WORK)
        srcs = [os.path.join(ROOT, p) for p in check.PKGS]
        srcs += [os.path.join(ROOT, rel) for _, rel in modules()]
        flags = [a for d in defs for a in ("-D", d)]
        sh(["sv2v", *flags, "-w", tmp, *srcs])
        try:
            os.rename(tmp, lib)
        except OSError:
            pass
    return lib


def lib_file(mod, defs=None):
    return os.path.join(lib_dir(defs), mod + ".v")


def ports(mod, defs=None):
    lib = read(lib_file(mod, defs))
    head = re.search(
        rf"^module {re.escape(mod)}\s*\((.*?)\);",
        lib,
        re.MULTILINE | re.DOTALL,
    )
    return {p.strip() for p in head.group(1).split(",") if p.strip()}


# Ports bench build lacks
def bench_copy(path, mod):
    if not BENCH_DEF:
        return
    names = {n for n, _ in modules()}
    keep = {m: ports(m, BENCH_DEF) for m in [mod, *children(mod)]}
    text = read(path)
    gone = sorted(ports(mod) - keep[mod])
    head = re.compile(
        rf"^module {re.escape(mod)}\((.*?)\);", re.MULTILINE | re.DOTALL
    )
    m = head.search(text)
    left = [p.strip() for p in m.group(1).split(",") if p.strip() not in gone]
    text = text[: m.start(1)] + ", ".join(left) + text[m.end(1) :]
    for p in gone:
        decl = rf"^  output (\[[^\]]*\] )?{p};\n"
        text = re.sub(decl, "", text, flags=re.MULTILINE)
    opener = check.HASH + "("
    out, typ, conns = [], None, None
    for line in text.split("\n"):
        if conns is not None:
            if line == "  );":
                out.append(",\n".join(conns))
                out.append(line)
                conns = None
                continue
            port = re.match(r"\s*\.(\w+)\(", line)
            if typ in keep and port and port.group(1) not in keep[typ]:
                continue
            conns.append(line.rstrip(","))
            continue
        start = re.match(r"^  (\w+) (\x23\(|\S+ \()$", line)
        if start and start.group(1) in names:
            typ = start.group(1)
            if start.group(2) != opener:
                conns = []
        elif typ and re.match(r"^  \) \S+ \($", line):
            conns = []
        out.append(line)
    with open(path, "w") as f:
        f.write("\n".join(out))


def children(mod):
    names = {n for n, _ in modules()} - {mod}
    text = read(lib_file(mod))
    pat = re.compile(r"^\s*(\w+)\s*(?:\#|\w+\s*\()", re.MULTILINE)
    return sorted({m for m in pat.findall(text) if m in names})


def closure(mod):
    seen, todo = set(), children(mod)
    while todo:
        m = todo.pop()
        if m not in seen:
            seen.add(m)
            todo += children(m)
    return sorted(seen)


def declared(mod):
    text = read(lib_file(mod))
    pat = re.compile(r"^\s*parameter\b[^=;]*?\b(\w+)\s*=", re.MULTILINE)
    return pat.findall(text)


def cosim_file():
    return os.path.join(ROOT, "tb", "cosim.sv")


# Parameter sets per test
def params(mod):
    bench, cos = [], []
    if has_bench(mod):
        bench = hier_sets(mod, f"{mod}_tb", bench_file(mod))
    if mod in cosim_modules():
        cos = hier_sets(mod, "cosim", cosim_file())
    sets = (cos or bench)[:1] or [{}]
    sets += [ps for ps in bench + cos if ps not in sets]
    return {
        "params": sets,
        "bench": any(ps != sets[0] for ps in bench),
        "cosim": any(ps != sets[0] for ps in cos),
    }


def hier_sets(mod, top, extra):
    srcs = [os.path.join(ROOT, f) for f in check.sweep_srcs()] + [extra]
    r = subprocess.run(
        ["slang-hier", "--top", top, "--params", *srcs],
        capture_output=True,
        text=True,
        check=False,
    )
    keep = set(declared(mod))
    sets = []
    for line in r.stdout.splitlines():
        m = check.HIER_LINE.match(line)
        if m and m.group(1) == mod:
            ps = dict(check.HIER_PARAM.findall(m.group(3) or ""))
            ps = {k: v for k, v in ps.items() if k in keep}
            if ps not in sets:
                sets.append(ps)
    return sets


def with_params(path, mod, ps):
    text = read(path)
    head = re.compile(
        rf"^module {re.escape(mod)}\b[^;]*;\n", re.MULTILINE | re.DOTALL
    )
    decl = "".join(f"  parameter {k} = {v};\n" for k, v in ps.items())
    text, n = head.subn(lambda m: m.group(0) + decl, text, count=1)
    if n != 1:
        sys.exit(f"no module {mod} header in {path}")
    with open(path, "w") as f:
        f.write(text)


# Mutant on first set
def wrap(path, mod, sets):
    lib = read(lib_file(mod))
    name = re.escape(mod)
    head = re.search(
        rf"^module {name}\s*\((.*?)\);", lib, re.MULTILINE | re.DOTALL
    )
    if not head:
        sys.exit(f"no module {mod} header in {lib_file(mod)}")
    ports = [p.strip() for p in head.group(1).split(",") if p.strip()]
    pat = re.compile(
        r"^\t(?:parameter|localparam|input|output|inout)\b[^\n]*;$",
        re.MULTILINE,
    )
    decls = [
        re.sub(r"^(\toutput) reg\b", r"\1 wire", d) for d in pat.findall(lib)
    ]
    cond = " && ".join(f"({k} == {v})" for k, v in sets[0].items()) or "1"
    conn = ", ".join(f".{p}({p})" for p in ports)
    over = ", ".join(f".{k}({k})" for k in declared(mod))
    over = f" {check.HASH}({over})" if over else ""
    mut = re.sub(
        rf"^module {name}\(",
        f"module {mod}__mut(",
        read(path),
        count=1,
        flags=re.MULTILINE,
    )
    orig = re.sub(
        rf"^module {name}\b",
        f"module {mod}__orig",
        lib,
        count=1,
        flags=re.MULTILINE,
    )
    text = [
        f"module {mod} ({', '.join(ports)});",
        *decls,
        f"\tgenerate if ({cond}) begin : g_mut",
        f"\t\t{mod}__mut u ({conn});",
        "\tend else begin : g_orig",
        f"\t\t{mod}__orig{over} u ({conn});",
        "\tend endgenerate",
        "endmodule",
        mut,
        orig,
        "`default_nettype wire",
        "",
    ]
    with open(path, "w") as f:
        f.write("\n".join(text))


def config(mod, bench, cosim, ps):
    me = os.path.abspath(__file__)
    logic = []
    for t, on in (("bench", bench), ("cosim", cosim)):
        if on:
            logic += [f'if result("{t}") == "FAIL":', '    tag("KILLED")']
            logic += ["    return"]
    logic += ['if result("equiv") == "PASS":', '    tag("EQUIV")', "    return"]
    logic += ['tag("SURVIVED")']
    tests = []
    for t, on in (("bench", bench), ("cosim", cosim), ("equiv", True)):
        if on:
            tests += [f"[test {t}]", "expect PASS FAIL"]
            run = f"env -u PYTHONHOME -u PYTHONEXECUTABLE {sys.executable} {me}"
            tests += [f"run {run} test {t} {mod}", ""]
    lines = [
        "[options]",
        f"size {MUTANTS + 1}",
        f"seed {SEED}",
        "tags KILLED EQUIV SURVIVED",
        "",
        "[script]",
        *(f"read_verilog -lib {lib_file(c)}" for c in children(mod)),
        f"read_verilog {lib_file(mod)}",
        *(f"chparam -set {k} {v} {mod}" for k, v in ps.items()),
        f"hierarchy -top {mod}",
        f"prep -top {mod}",
        "pmuxtree",
        "",
        "[logic]",
        *logic,
        "",
        "[report]",
        'print("tags", tags())',
        "",
        *tests,
    ]
    return "\n".join(lines)


def shadow(dst, mod, mutant):
    os.makedirs(dst, exist_ok=True)
    for e in os.listdir(ROOT):
        if e not in ("rtl", "build", ".git"):
            os.symlink(os.path.join(ROOT, e), os.path.join(dst, e))
    target = rtl_path(mod)
    for d, _, fs in os.walk(os.path.join(ROOT, "rtl")):
        rel = os.path.relpath(d, ROOT)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in fs:
            p = os.path.join(rel, f)
            src = os.path.join(ROOT, p)
            if p == target:
                src = os.path.abspath(mutant)
            os.symlink(src, os.path.join(dst, p))
    os.makedirs(os.path.join(dst, "build"))
    tf = os.path.join(ROOT, "build", "testfloat")
    if os.path.isdir(tf):
        os.symlink(tf, os.path.join(dst, "build", "testfloat"))


def timed(cmd, cwd, limit, log):
    t0 = time.time()
    p = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        rc = p.wait(timeout=limit)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        rc = None
    return rc, time.time() - t0


def run_bench(tree, mod, limit):
    path = os.path.join(tree, "bench.log")
    with open(path, "w") as log:
        rc, secs = timed(
            ["make", "-s", f"MOD={mod}", "MAX_ERRORS=1"], tree, limit, log
        )
    out = read(path)
    return rc == 0 and re.search(r"^PASS", out, re.MULTILINE) is not None, secs


def run_cosim(tree, limit):
    secs = 0.0
    with open(os.path.join(ROOT, "tests", "cosim_directed.txt")) as f:
        progs = [line.split() for line in f if line.strip()]
    script = os.path.join(tree, "tests", "cosim.py")
    with open(os.path.join(tree, "cosim.log"), "w") as log:
        for args in progs:
            left = None if limit is None else max(1, limit - secs)
            rc, s = timed(["python3", script, *args], tree, left, log)
            secs += s
            if rc != 0:
                return False, secs
    return True, secs


# Generate scope names back
def regen(path):
    text = read(path)
    decl = re.compile(
        r"^(?:[ \t]*\(\*.*\*\)\n)*([ \t]*)(reg|wire)(\s[^\\;]*?)?\s*"
        r"\\(\w+)\[(\d+)\]\.(\w+)\s+(\[[^;]*\])?;\n",
        re.MULTILINE,
    )
    out = []
    for part in re.split(r"(?=^module )", text, flags=re.MULTILINE):
        scopes = {}
        for m in decl.finditer(part):
            v = scopes.setdefault(m.group(4), {}).setdefault(m.group(6), [])
            v.append(m)
        for scope, vs in scopes.items():
            idx = {
                tuple(sorted(int(m.group(5)) for m in ms)) for ms in vs.values()
            }
            n = len(next(iter(vs.values())))
            if idx != {tuple(range(n))}:
                continue
            pad = next(iter(vs.values()))[0].group(1)
            lines = [
                f"{pad}for (genvar i = 0; i < {n}; i = i + 1) begin : {scope}"
            ]
            for var, ms in vs.items():
                m = ms[0]
                lines.append(
                    f"{pad}  {m.group(2)}{m.group(3) or ''} {var} {m.group(7) or ''};"
                )
                for m in ms:
                    part = part.replace(m.group(0), "", 1)
                name = re.compile(rf"\\{scope}\[(\d+)\]\.{var}(?=\s)")
                part = name.sub(rf"{scope}[\1].{var}", part)
            head = re.search(r"\);\n", part)
            part = (
                part[: head.end()]
                + "\n".join(lines)
                + f"\n{pad}end\n"
                + part[head.end() :]
            )
        out.append(part)
    with open(path, "w") as f:
        f.write("".join(out))


def write_design(
    name, mod, sets, design, muts=(), plain=False, wrapped=False, bench=True
):
    cmds = [f"read_rtlil {design}"]
    cmds += [f"mutate {m.split(None, 1)[1]}" for m in muts]
    cmds += [f"write_verilog {name}"]
    sh(["yosys", "-q", "-p", "; ".join(cmds)])
    if bench:
        bench_copy(name, mod)
    if plain:
        return
    if wrapped:
        wrap(name, mod, sets)
    else:
        with_params(name, mod, sets[0])
    regen(name)


def mutant_file(name, mod, base, kind=None):
    with open("input.txt") as f:
        muts = [line.split(None, 1)[1] for line in f if line.strip()]
    design = "../../database/design.il"
    sets = base["params"]["params"]
    wrapped = bool(kind) and base["params"][kind]
    write_design(
        name, mod, sets, design, muts, not kind, wrapped, kind != "cosim"
    )


def cmd_test(kind, mod):
    use_defines(mod)
    work = os.path.abspath("../..")
    base = json.loads(read(os.path.join(work, "base.json")))
    if kind == "equiv":
        ok = equiv(mod, work, base)
    else:
        mutant_file("mutated.v", mod, base, kind)
        tree = os.path.abspath("tree")
        shadow(tree, mod, "mutated.v")
        limit = BENCH_SLACK * base[kind] + 60
        if kind == "bench":
            ok = run_bench(tree, mod, limit)[0]
        else:
            ok = run_cosim(tree, limit)[0]
    with open("output.txt", "w") as f:
        f.write(f"1 {'PASS' if ok else 'FAIL'}\n")
    return 0


def miter_cmds(mod, work, lib, flags=""):
    cmds = [f"read_verilog {f}" for f in lib]
    cmds += [
        f"read_verilog {os.path.join(work, 'gold.v')}",
        f"rename {mod} gold",
    ]
    cmds += [f"read_verilog {os.path.abspath('gate.v')}", f"rename {mod} gate"]
    cmds += ["setattr -mod -unset top", "hierarchy -check", "proc", "flatten"]
    cmds += ["memory_map", "opt_clean", "setundef -zero -init"]
    cmds += [
        f"miter -equiv -flatten{flags} gold gate miter",
        "hierarchy -top miter",
    ]
    return cmds


# Sequential equivalence by abc
def dprove(mod, work, lib):
    cmds = miter_cmds(mod, work, lib)
    cmds += ["async2sync", "techmap", "opt -fast", "dffunmap", "aigmap"]
    cmds += ["setundef -undriven -zero", "write_aiger -zinit miter.aig"]
    with open("dprove.log", "w") as log:
        rc, _ = timed(["yosys", "-q", "-p", "; ".join(cmds)], ".", EQ_SEC, log)
        if rc != 0:
            return None
        abc = ["yosys-abc", "-c", "read_aiger miter.aig; dprove"]
        timed(abc, ".", EQ_SEC, log)
    out = read("dprove.log")
    if "Networks are equivalent" in out:
        return True
    if "Networks are not equivalent" in out:
        return False
    return None


def equiv(mod, work, base):
    mutant_file("gate.v", mod, base)
    lib = [lib_file(c, BENCH_DEF or None) for c in closure(mod)]
    proved = dprove(mod, work, lib)
    if proved is not None:
        return proved
    sby = [
        "[options]",
        "mode prove",
        f"timeout {EQ_SEC}",
        "",
        "[engines]",
        "abc pdr",
        "",
        "[script]",
        *miter_cmds(mod, work, lib, " -make_assert"),
        "",
    ]
    with open("eq.sby", "w") as f:
        f.write("\n".join(sby))
    with open("eq.log", "w") as log:
        timed(["sby", "-f", "eq.sby"], ".", EQ_SEC + 60, log)
    try:
        return read(os.path.join("eq", "status")).split()[0] == "PASS"
    except (OSError, IndexError):
        return False


def jobs():
    if os.environ.get("MUTATION_JOBS"):
        return int(os.environ["MUTATION_JOBS"])
    try:
        return len(os.sched_getaffinity(0))
    except AttributeError:
        return os.cpu_count() or 2


def stop(p):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        time.sleep(5)
    p.wait()


def cmd_run(mod, shard, of):
    t0 = time.time()
    bench, cosim = has_bench(mod), mod in cosim_modules()
    use_defines(mod)
    work = os.path.join(WORK, f"{mod}.{shard}")
    os.makedirs(work, exist_ok=True)
    os.chdir(work)
    ps = params(mod)
    sets = ps["params"]
    with open("config.mcy", "w") as f:
        f.write(config(mod, bench, cosim, sets[0]))
    sh(["mcy", "init", "-f"])
    db = sqlite3.connect("database/db.sqlite3")
    total = db.execute("SELECT COUNT(*) FROM mutations").fetchone()[0]
    res = {"mod": mod, "shard": shard, "of": of, "total": total - 1}
    ids = [i for i in range(1, total + 1) if (i - 1) % of == shard]
    design = "database/design.il"
    write_design("gold.v", mod, sets, design, plain=True)
    base = {"params": ps}
    bad = []
    if bench:
        write_design("bench.v", mod, sets, design, wrapped=ps["bench"])
        tree = tempfile.mkdtemp(prefix="base", dir=work)
        shadow(tree, mod, "bench.v")
        ok, base["bench"] = run_bench(tree, mod, None)
        bad += [] if ok else ["bench"]
    if cosim:
        write_design(
            "cosim.v", mod, sets, design, wrapped=ps["cosim"], bench=False
        )
        tree = tempfile.mkdtemp(prefix="base", dir=work)
        shadow(tree, mod, "cosim.v")
        ok, base["cosim"] = run_cosim(tree, None)
        if not ok and bench and not bad:
            why = first_error(os.path.join(tree, "cosim.log"))
            res["note"] = f"cosim skipped, unmutated build fails it: {why}"
            with open("config.mcy", "w") as f:
                f.write(config(mod, bench, False, sets[0]))
        elif not ok:
            bad.append("cosim")
    with open("base.json", "w") as f:
        json.dump(base, f)
    res["base"] = base
    if bad:
        res["error"] = f"unmutated {mod} fails {' '.join(bad)} in {work}"
        return finish(res)
    if ids:
        left = STOP_MIN * 60 - (time.time() - t0)
        nproc = str(jobs())
        p = subprocess.Popen(
            ["mcy", "run", "-j", nproc, *map(str, ids)],
            start_new_session=True,
        )
        try:
            p.wait(timeout=max(60, left))
        except subprocess.TimeoutExpired:
            stop(p)
    db = sqlite3.connect("database/db.sqlite3")
    want = set(ids)
    tags = {
        m: t
        for m, t in db.execute("SELECT mutation_id, tag FROM tags")
        if m in want
    }
    none = {
        m
        for m, t in db.execute("SELECT mutation_id, mutation FROM mutations")
        if t.split()[1:3] == ["-mode", "none"]
    }
    for m in none & set(tags):
        if tags.pop(m) == "KILLED":
            res["error"] = f"unmutated control {m} killed"
    res["ids"] = len(want - none)
    for t in ("KILLED", "EQUIV", "SURVIVED"):
        res[t.lower()] = sum(1 for v in tags.values() if v == t)
    res["notrun"] = res["ids"] - len(tags)
    res["survivors"] = []
    for mid, t in sorted(tags.items()):
        if t == "SURVIVED":
            mut = db.execute(
                "SELECT mutation FROM mutations WHERE mutation_id = ?", [mid]
            ).fetchone()[0]
            res["survivors"].append(f"{mid} {mut}{where(mut)}")
    res["seconds"] = round(time.time() - t0)
    return finish(res)


def first_error(path):
    for line in read(path).splitlines():
        if "error" in line.lower() or "mismatch" in line.lower():
            return line.strip()[:200]
    return "no error line"


def where(mut):
    out = []
    for path, line in re.findall(r"-src (\S+?):(\d+)\.", mut):
        try:
            text = read(path).splitlines()[int(line) - 1].strip()
        except (OSError, IndexError):
            continue
        out.append(f"\n    {os.path.basename(path)}:{line} {text}")
    return "".join(dict.fromkeys(out))


def finish(res):
    out = os.path.join(WORK, f"{res['mod']}-{res['shard']}.json")
    with open(out, "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "survivors"}))
    for s in res.get("survivors", []):
        print(f"survived {s}")
    if res.get("error"):
        print(res["error"])
        return 1
    return 1 if res.get("notrun") else 0


def cmd_report(d):
    agg = {}
    for f in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
        r = json.loads(read(f))
        if not isinstance(r, dict) or "mod" not in r:
            continue
        a = agg.setdefault(r["mod"], {"of": r["of"], "total": r["total"]})
        a["shards"] = a.get("shards", 0) + 1
        for k in ("killed", "equiv", "survived", "notrun"):
            a[k] = a.get(k, 0) + r.get(k, 0)
        if r.get("error"):
            a["error"] = r["error"]
        if r.get("note"):
            a["note"] = r["note"]
    rows = [
        "| module | mutants | equivalent | killed | rate | verdict |",
        "|---|---|---|---|---|---|",
    ]
    bad = 0
    for mod in sorted(agg):
        a = agg[mod]
        den = a["total"] - a["equiv"]
        rate = 100.0 * a["killed"] / den if den else 100.0
        done = a["shards"] == a["of"] and not a["notrun"]
        done = done and not a.get("error")
        ok = done and rate >= FLOOR
        bad += not ok
        verdict = "pass" if ok else ("fail" if done else "incomplete")
        rows.append(
            f"| {mod} | {a['total']} | {a['equiv']} | {a['killed']} "
            f"| {rate:.1f}% | {verdict} |"
        )
    for mod in sorted(agg):
        for k in ("error", "note"):
            if agg[mod].get(k):
                rows.append(f"| {mod} | {k}: {agg[mod][k]} | | | | |")
    cos = cosim_modules()
    for mod, _ in modules():
        if not has_bench(mod):
            how = "cosim only" if mod in cos else "not mutated"
            rows.append(f"| {mod} | no bench, {how} | | | | |")
    text = "\n".join(rows) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(check.HASH * 2 + " Mutation kill rate\n\n" + text)
    return 1 if bad else 0


def main():
    a = sys.argv[1:]
    if a[:1] == ["list"]:
        return cmd_list()
    if a[:1] == ["run"] and len(a) == 4:
        return cmd_run(a[1], int(a[2]), int(a[3]))
    if a[:1] == ["test"] and len(a) == 3:
        return cmd_test(a[1], a[2])
    if a[:1] == ["report"] and len(a) == 2:
        return cmd_report(a[1])
    sys.exit("usage: mutate.py list | run MOD SHARD OF | report DIR")


if __name__ == "__main__":
    sys.exit(main())
