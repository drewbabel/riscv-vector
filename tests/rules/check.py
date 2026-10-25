#!/usr/bin/env python3
import argparse
import fnmatch
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import tokenize
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
HERE = os.path.join(ROOT, "tests", "rules")
PKGS = [
    "rtl/arch_pkg.sv",
    "rtl/alu_pkg.sv",
    "rtl/csr_pkg.sv",
    "rtl/opcode_pkg.sv",
    "rtl/fp_pkg.sv",
    "rtl/muldiv_pkg.sv",
    "rtl/bp_pkg.sv",
    "rtl/cache_pkg.sv",
    "rtl/vec_pkg.sv",
]
HASH = "\x23"
MAX_WORDS = 4
ARTICLES = {"a", "an", "the"}
PRAGMA = re.compile(
    r"^\s*(verilator|verible|synopsys|pragma|yosys|spyglass|noqa|type:|shellcheck|fmt:)"
)
RESET_PORT = re.compile(
    r"^(rst|rst_n|rstn|reset|reset_n|resetn|areset|aresetn|rst_ni)$"
)
CLOCK_NAME = re.compile(r"^(clk|clock)(_\w+)?$")
CAMEL = re.compile(r"^[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*$")
LOWER_SNAKE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
SV_EXT = (".sv", ".v")
HASH_EXT = (".py", ".sh", ".mk", ".tcl", ".yml", ".yaml", ".sby", ".cfg")
EXPR_TAGS = {
    "kExpression",
    "kConditionExpression",
    "kBinaryExpression",
    "kUnaryPrefixExpression",
    "kParenGroup",
    "kConcatenationExpression",
    "kBraceGroup",
    "kFunctionCall",
    "kReferenceCallBase",
    "kReference",
    "kCast",
    "kExpressionList",
    "kOpenRangeList",
    "kAssignmentPattern",
    "kBracketGroup",
    "kDimensionScalar",
    "kDimensionRange",
    "kDimensionSlice",
    "kHierarchyExtension",
    "kLocalRoot",
    "kQualifiedId",
    "kUnqualifiedId",
    "kNumber",
    "kSystemTFCall",
    "kIncrementDecrementExpression",
    "kSelectVariableDimension",
    "kPatternExpression",
}
DECL_TAGS = {
    "kPortDeclaration",
    "kDataDeclaration",
    "kNetDeclaration",
    "kTypeDeclaration",
    "kStructUnionMember",
    "kPortItem",
    "kFunctionHeader",
}
MUL_OPS = {"*", "/", "%", "<<", ">>", "<<<", ">>>", "**"}


class Report:
    def __init__(self):
        self.items = []

    def add(self, path, line, col, rule, msg):
        self.items.append((path, line, col, rule, msg))

    def emit(self, out):
        for p, l, c, r, m in sorted(set(self.items)):
            out.write(f"{p}:{l}:{c}: [{r}] {m}\n")
        return len(set(self.items))


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout


def tracked():
    return [
        f
        for f in git("ls-files").splitlines()
        if os.path.isfile(os.path.join(ROOT, f))
    ]


def added_lines(base):
    out = {}
    if not base:
        return out
    diff = git(
        "diff", "-U0", "--no-color", "--diff-filter=AM", f"{base}...HEAD"
    )
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@") and path:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, n = int(m.group(1)), int(m.group(2) or 1)
            out.setdefault(path, set()).update(range(start, start + n))
    return out


class Src:
    def __init__(self, path):
        self.path = path
        with open(os.path.join(ROOT, path), "rb") as f:
            self.raw = f.read()
        self.text = self.raw.decode("utf-8", "replace")
        self.starts = [0]
        for i, b in enumerate(self.raw):
            if b == 10:
                self.starts.append(i + 1)

    def pos(self, off):
        lo, hi = 0, len(self.starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.starts[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1, off - self.starts[lo] + 1

    def slice(self, a, b):
        return self.raw[a:b].decode("utf-8", "replace")

    def rest_of_line(self, off):
        end = self.raw.find(b"\n", off)
        return self.slice(off, len(self.raw) if end < 0 else end)


def cst(path, text=None):
    arg = path
    tmp = None
    if text is not None:
        fd, tmp = tempfile.mkstemp(suffix=".sv")
        with os.fdopen(fd, "w") as f:
            f.write(text)
        arg = tmp
    r = subprocess.run(
        [
            "verible-verilog-syntax",
            "--export_json",
            "--printtree",
            "--printtokens",
            arg,
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if tmp:
        os.unlink(tmp)
    try:
        return json.loads(r.stdout)[arg]
    except (ValueError, KeyError):
        return {"error": r.stderr.strip() or "no output"}


def blank(text):
    return re.sub(r"[^\n]", " ", text)


def defined_variant(text):
    out = []
    stack = []
    for line in text.splitlines(keepends=True):
        m = re.match(r"\s*`(ifdef|ifndef|elsif|else|endif)\b", line)
        if m:
            d = m.group(1)
            if d in ("ifdef", "ifndef"):
                stack.append(d == "ifdef")
            elif d == "elsif":
                if stack:
                    stack[-1] = False
            elif d == "else":
                if stack:
                    stack[-1] = not stack[-1]
            elif stack:
                stack.pop()
            out.append(blank(line))
            continue
        out.append(line if all(stack) else blank(line))
    return "".join(out)


def is_leaf(n):
    return n is not None and "children" not in n


def kids(n):
    return [c for c in n.get("children", []) if c is not None]


def walk(n, anc=()):
    if n is None:
        return
    yield n, anc
    for c in kids(n):
        yield from walk(c, anc + (n,))


def leaves(n):
    if n is None:
        return
    if is_leaf(n):
        yield n
    for c in kids(n):
        yield from leaves(c)


def first_leaf(n):
    return next(leaves(n), None)


def span(n):
    ls = list(leaves(n))
    return (ls[0]["start"], ls[-1]["end"]) if ls else (0, 0)


def ident(leaf):
    return leaf.get("tag") in ("SymbolIdentifier", "EscapedIdentifier")


def sv_number(text):
    t = text.replace("_", "").strip()
    m = re.fullmatch(r"(\d*)\s*'[sS]?([bBoOdDhH])\s*([0-9a-fA-FxXzZ?]+)", t)
    if m:
        digits = m.group(3)
        if re.search(r"[xXzZ?]", digits):
            return None
        return int(
            digits, {"b": 2, "o": 8, "d": 10, "h": 16}[m.group(2).lower()]
        )
    if re.fullmatch(r"'[01]", t):
        return int(t[1])
    if re.fullmatch(r"\d+", t):
        return int(t)
    return None


def number_value(node):
    return sv_number("".join(l.get("text", "") for l in leaves(node)))


def sv_comments(src):
    out = []
    t = src.text
    i, n = 0, len(t)
    while i < n:
        c = t[i]
        if c == '"':
            i += 1
            while i < n and t[i] != '"':
                i += 2 if t[i] == "\\" else 1
            i += 1
        elif t.startswith("//", i):
            j = t.find("\n", i)
            j = n if j < 0 else j
            out.append((i, j, "line", t[i + 2 : j]))
            i = j
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append((i, j, "block", t[i + 2 : j - 2]))
            i = j
        else:
            i += 1
    return out


def hash_comments(path, text):
    out = []
    if path.endswith(".py"):
        try:
            for tok in tokenize.generate_tokens(io.StringIO(text).readline):
                if tok.type == tokenize.COMMENT:
                    out.append((tok.start[0], tok.string[1:]))
        except (tokenize.TokenError, IndentationError, SyntaxError):
            pass
        return out
    for no, line in enumerate(text.splitlines(), 1):
        q = None
        for k, ch in enumerate(line):
            if q:
                if ch == q:
                    q = None
            elif ch in "'\"":
                q = ch
            elif ch == HASH and (k == 0 or line[k - 1] in " \t"):
                out.append((no, line[k + 1 :]))
                break
    return out


def py_names(path, text):
    if not path.endswith(".py"):
        return set()
    try:
        return {
            t.string
            for t in tokenize.generate_tokens(io.StringIO(text).readline)
            if t.type == tokenize.NAME
        }
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return set()


def comment_problems(body, names, line_no):
    s = body.strip()
    if not s or PRAGMA.match(s) or s.startswith("!"):
        return []
    probs = []
    if line_no == 1:
        probs.append("comment on line 1")
    words = s.split()
    if len(words) > MAX_WORDS:
        probs.append(f"{len(words)} words, limit {MAX_WORDS}")
    if any(w.lower() in ARTICLES for w in words):
        probs.append("article")
    if re.search(r"[.,;:!?'\"()`{}<>=+*/\\-]", s):
        probs.append("punctuation")
    lead = re.sub(r"\W.*", "", words[0])
    if s[0].isalpha() and not s[0].isupper() and lead not in names:
        probs.append("lowercase first word that is not a signal")
    return probs


class Unit:
    def __init__(self, path):
        self.path = path
        self.src = Src(path)
        self.cst = cst(path)
        self.tree = self.cst.get("tree")
        self.tokens = self.cst.get("tokens", [])
        self.trees = [self.tree] if self.tree else []
        if re.search(r"^\s*`if", self.src.text, re.MULTILINE):
            alt = cst(path, defined_variant(self.src.text))
            if alt.get("tree"):
                self.trees.append(alt["tree"])
                seen = {t["start"] for t in self.tokens}
                extra = [
                    t for t in alt.get("tokens", []) if t["start"] not in seen
                ]
                self.tokens = sorted(
                    self.tokens + extra, key=lambda t: t["start"]
                )
        self.names = {t["text"] for t in self.tokens if ident(t)}
        self._params = None

    def walk(self):
        for t in self.trees:
            yield from walk(t)

    def at(self, off):
        return self.src.pos(off)

    def params(self):
        if self._params is None:
            self._params = param_decls(self)
        return self._params


def rule_parse(u, rep):
    if not u.tree:
        rep.add(
            u.path,
            1,
            1,
            "parse",
            f"verible could not parse: {u.cst.get('error', '')[:200]}",
        )
        return False
    return True


def rule_nettype(u, rep):
    toks = [
        t
        for t in u.cst.get("tokens", [])
        if t.get("tag") not in ("$end", "end of file")
    ]
    head = toks[:2]
    tail = toks[-2:]
    if not (
        len(head) == 2
        and head[0]["tag"] == "`default_nettype"
        and head[1].get("text") == "none"
    ):
        rep.add(
            u.path,
            1,
            1,
            "nettype",
            "file does not open with `default_nettype none",
        )
    if not (
        len(tail) == 2
        and tail[0]["tag"] == "`default_nettype"
        and tail[1].get("tag") == "wire"
    ):
        line = u.src.text.count("\n") or 1
        rep.add(
            u.path,
            line,
            1,
            "nettype",
            "file does not close with `default_nettype wire",
        )


def rule_ternary(u, rep):
    groups = {}
    for n, anc in u.walk():
        if n.get("tag") != "kConditionExpression":
            continue
        boundary = None
        for a in reversed(anc):
            if a.get("tag") not in EXPR_TAGS:
                boundary = a
                break
        groups.setdefault(id(boundary), []).append(n)
    for ns in groups.values():
        if len(ns) > 1:
            off = min(first_leaf(x)["start"] for x in ns)
            line, col = u.at(off)
            rep.add(
                u.path,
                line,
                col,
                "ternary",
                f"{len(ns)} ?: in one expression, use if/else or case",
            )


def decl_name(decl, after):
    ls = [l for l in leaves(decl) if ident(l)]
    for l in ls:
        if l["start"] >= after:
            return l["text"]
    return ls[-1]["text"] if ls else "?"


def exempt_literal(num, anc):
    for a in reversed(anc):
        if a.get("tag") == "kBinaryExpression":
            ops = [c for c in kids(a) if is_leaf(c) and c.get("tag") in MUL_OPS]
            if ops:
                others = [c for c in kids(a) if c is not num and not is_leaf(c)]
                return any(ident(l) for o in others for l in leaves(o))
            return False
        if a.get("tag") in ("kExpression", "kParenGroup", "kNumber"):
            continue
        return False
    return False


def load_allow():
    path = os.path.join(HERE, "widths.allow")
    entries = []
    if not os.path.exists(path):
        return entries
    with open(path) as f:
        for no, line in enumerate(f, 1):
            parts = line.split(None, 3)
            if not parts:
                continue
            if len(parts) < 4:
                entries.append({"line": no, "bad": True})
                continue
            entries.append(
                {
                    "line": no,
                    "file": parts[0],
                    "name": parts[1],
                    "dim": parts[2],
                    "reason": parts[3].strip(),
                    "used": False,
                }
            )
    return entries


def rule_width(u, rep, allow):
    if not u.path.startswith("rtl/"):
        return
    for n, anc in u.walk():
        if n.get("tag") != "kDeclarationDimensions":
            continue
        decl = None
        for a in reversed(anc):
            t = a.get("tag")
            if t in ("kParamDeclaration", "kEnumType"):
                decl = None
                break
            if t in DECL_TAGS:
                decl = a
                break
        if decl is None:
            continue
        bad = []
        for m, manc in walk(n, anc):
            if m.get("tag") != "kNumber":
                continue
            v = number_value(m)
            if v is None or v in (0, 1) or exempt_literal(m, manc):
                continue
            bad.append(v)
        if not bad:
            continue
        a, b = span(n)
        name = decl_name(decl, b)
        dim = re.sub(r"\s+", "", u.src.slice(a, b))
        hit = next(
            (
                e
                for e in allow
                if not e.get("bad")
                and fnmatch.fnmatch(u.path, e["file"])
                and fnmatch.fnmatch(name, e["name"])
                and e["dim"] == dim
            ),
            None,
        )
        if hit:
            hit["used"] = True
            continue
        line, col = u.at(a)
        rep.add(
            u.path,
            line,
            col,
            "width",
            f"literal width {u.src.slice(a, b)} in declaration of {name}",
        )


def param_decls(u):
    out = []
    seen = set()
    for n, anc in u.walk():
        if n.get("tag") != "kParamDeclaration":
            continue
        kw = first_leaf(n).get("tag")
        if kw not in ("parameter", "localparam"):
            continue
        pt = next((c for c in kids(n) if c.get("tag") == "kParamType"), None)
        if pt is None:
            continue
        nm = next((c for c in kids(pt) if is_leaf(c) and ident(c)), None)
        if nm is None or nm["start"] in seen:
            continue
        seen.add(nm["start"])
        scope = next(
            (
                a
                for a in reversed(anc)
                if a.get("tag") in ("kModuleDeclaration", "kPackageDeclaration")
            ),
            None,
        )
        if scope is None:
            continue
        out.append(
            {
                "kw": kw,
                "name": nm["text"],
                "tok": nm,
                "header": any(
                    a.get("tag") == "kFormalParameterList" for a in anc
                ),
                "scope": scope,
                "kind": "package"
                if scope["tag"] == "kPackageDeclaration"
                else "module",
                "scope_name": next(
                    l["text"] for l in leaves(scope) if ident(l)
                ),
                "rhs": next(
                    (c for c in kids(n) if c.get("tag") == "kTrailingAssign"),
                    None,
                ),
                "unit": u,
            }
        )
    return out


def imports(u):
    pk = set()
    toks = u.tokens
    for i, t in enumerate(toks):
        if (
            t.get("tag") == "import"
            and i + 2 < len(toks)
            and toks[i + 2].get("tag") == "::"
        ):
            pk.add(toks[i + 1].get("text"))
    return pk


def rule_consts(units, rep):
    decls = [d for u in units for d in u.params()]
    qualified = {}
    for u in units:
        toks = u.tokens
        for i in range(len(toks) - 2):
            if (
                ident(toks[i])
                and toks[i + 1].get("tag") == "::"
                and ident(toks[i + 2])
            ):
                key = (toks[i]["text"], toks[i + 2]["text"])
                qualified[key] = qualified.get(key, 0) + 1
    imp = {u.path: imports(u) for u in units}
    for d in decls:
        u, name = d["unit"], d["name"]
        a, b = span(d["scope"])
        reads = sum(
            1
            for t in u.tokens
            if ident(t)
            and t["text"] == name
            and a <= t["start"] < b
            and t["start"] != d["tok"]["start"]
        )
        if d["kind"] == "package":
            reads += qualified.get((d["scope_name"], name), 0)
            for v in units:
                if v is u or d["scope_name"] not in imp[v.path]:
                    continue
                if any(x["name"] == name for x in v.params()):
                    continue
                reads += sum(
                    1 for t in v.tokens if ident(t) and t["text"] == name
                )
        if reads or (d["header"] and u.path.startswith("tb/")):
            continue
        line, col = u.at(d["tok"]["start"])
        if d["header"]:
            rep.add(
                u.path,
                line,
                col,
                "param-unused",
                f"parameter {name} is never read in {d['scope_name']}",
            )
        else:
            what = "package constant" if d["kind"] == "package" else d["kw"]
            rep.add(
                u.path,
                line,
                col,
                "const-unused",
                f"{what} {name} is never read",
            )
    lits = {}
    for d in decls:
        if not d["unit"].path.startswith("rtl/") or d["rhs"] is None:
            continue
        ls = [l for l in leaves(d["rhs"]) if l.get("tag") != "="]
        if not ls or any(
            ident(l) or l.get("tag", "").startswith("Sys") for l in ls
        ):
            continue
        nums = [n for n, _ in walk(d["rhs"]) if n.get("tag") == "kNumber"]
        if len(nums) != 1:
            continue
        v = number_value(nums[0])
        if v is not None:
            lits.setdefault(v, []).append(d)
    for v, ds in lits.items():
        for d in ds:
            path = d["unit"].path
            same = [
                x
                for x in ds
                if x["unit"].path != path and x["name"] == d["name"]
            ]
            if same:
                hits = same
            else:
                continue
            names = ", ".join(
                sorted(f"{x['scope_name']}::{x['name']}" for x in hits)
            )
            line, col = d["unit"].at(d["tok"]["start"])
            rep.add(
                path,
                line,
                col,
                "const-dup",
                f"{d['name']} = {v} is also defined as {names}",
            )


def rule_naming(u, rep):
    if not u.path.startswith("rtl/"):
        return
    for d in u.params():
        if d["header"] or d["kind"] == "package":
            continue
        if not CAMEL.match(d["name"]):
            line, col = u.at(d["tok"]["start"])
            rep.add(
                u.path,
                line,
                col,
                "localparam-name",
                f"body localparam {d['name']} is not CamelCase",
            )
    for n, anc in u.walk():
        t = n.get("tag")
        if t == "kTypeDeclaration" and not any(
            a.get("tag") == "kPackageDeclaration" for a in anc
        ):
            ls = [l for l in leaves(n) if ident(l)]
            if (
                ls
                and ls[-1]["text"].endswith("_e")
                and any(l.get("tag") == "enum" for l in leaves(n))
            ):
                line, col = u.at(ls[-1]["start"])
                rep.add(
                    u.path,
                    line,
                    col,
                    "enum-name",
                    f"module-local enum {ls[-1]['text']} takes _t",
                )
        if t == "kPortDeclaration":
            ls = list(leaves(n))
            ids = [l for l in ls if ident(l)]
            if (
                ls
                and ls[0].get("tag") == "input"
                and not any(l.get("tag") == "wire" for l in ls)
            ):
                line, col = u.at(ls[0]["start"])
                rep.add(
                    u.path,
                    line,
                    col,
                    "input-wire",
                    f"input {ids[-1]['text'] if ids else '?'} does not say wire",
                )
            if ids and ids[-1]["text"].endswith("_nxt"):
                line, col = u.at(ids[-1]["start"])
                rep.add(
                    u.path,
                    line,
                    col,
                    "next-name",
                    f"{ids[-1]['text']} is a next value, name it <pin>_next",
                )
        if t == "kGateInstance":
            nm = next((l for l in leaves(n) if ident(l)), None)
            if nm and not LOWER_SNAKE.match(nm["text"]):
                line, col = u.at(nm["start"])
                rep.add(
                    u.path,
                    line,
                    col,
                    "instance-name",
                    f"instance {nm['text']} is not lower_snake",
                )
        if t in ("kRegisterVariable", "kNetVariable"):
            nm = next((l for l in leaves(n) if ident(l)), None)
            if nm and nm["text"].endswith("_nxt"):
                line, col = u.at(nm["start"])
                rep.add(
                    u.path,
                    line,
                    col,
                    "next-name",
                    f"{nm['text']} is a next value, name it <pin>_next",
                )


def subroutine_name(n):
    hdr = next(
        c for c in kids(n) if c.get("tag") in ("kTaskHeader", "kFunctionHeader")
    )
    return hdr, next((l["text"] for l in leaves(hdr) if ident(l)), "?")


def rule_bench_syntax(u, rep):
    if not is_bench(u.path):
        return
    for n, anc in u.walk():
        t = n.get("tag")
        if t in ("kTaskDeclaration", "kFunctionDeclaration"):
            ls = list(leaves(n))
            hdr, name = subroutine_name(n)
            line, col = u.at(ls[0]["start"])
            if not any(l.get("tag") == "automatic" for l in leaves(hdr)):
                rep.add(
                    u.path,
                    line,
                    col,
                    "bench-automatic",
                    f"{ls[0]['tag']} {name} is not automatic",
                )
            if t == "kTaskDeclaration":
                if not re.fullmatch(
                    r"\s*//\s*Automatic\s*", u.src.rest_of_line(ls[-1]["end"])
                ):
                    eline, ecol = u.at(ls[-1]["start"])
                    rep.add(
                        u.path,
                        eline,
                        ecol,
                        "bench-automatic",
                        f"endtask of {name} is not commented Automatic",
                    )
                if name == "check":
                    a, b = span(hdr)
                    sig = re.sub(r"\s+", " ", u.src.slice(a, b))
                    if (
                        "(input string name, input logic got, input logic exp)"
                        not in sig
                    ):
                        rep.add(
                            u.path,
                            line,
                            col,
                            "bench-check",
                            "check is not (input string name, input logic got, input logic exp)",
                        )
        if t == "kSystemTFCall":
            fn = first_leaf(n)
            txt = fn.get("text", fn.get("tag"))
            line, col = u.at(fn["start"])
            if txt == "$urandom":
                if "kCast" not in [a.get("tag") for a in anc[-4:]]:
                    rep.add(
                        u.path,
                        line,
                        col,
                        "bench-urandom",
                        "$urandom without a cast",
                    )
                nxt = next(
                    (tk for tk in u.tokens if tk["start"] >= span(n)[1]), None
                )
                if nxt and nxt.get("tag") == "%":
                    rep.add(
                        u.path,
                        line,
                        col,
                        "bench-urandom",
                        "$urandom % N, use $urandom_range",
                    )
            if txt == "$urandom_range":
                a, b = span(n)
                args = re.sub(r"\s+", "", u.src.slice(a, b))
                if args in (
                    "$urandom_range(1)",
                    "$urandom_range(0,1)",
                    "$urandom_range(1,0)",
                ):
                    rep.add(
                        u.path,
                        line,
                        col,
                        "bench-urandom",
                        "coin flip by $urandom_range, use 1'($urandom)",
                    )
        if t in (
            "kIncrementDecrementExpression",
            "kBlockingAssignmentStatement",
            "kAssignModifyStatement",
            "kNetVariableAssignment",
        ):
            a, b = span(n)
            txt = re.sub(r"\s+", "", u.src.slice(a, b))
            if re.match(
                r"^(\+\+errors|errors\+\+|errors\+=|errors=errors\+)", txt
            ):
                task = next(
                    (
                        x
                        for x in reversed(anc)
                        if x.get("tag") == "kTaskDeclaration"
                    ),
                    None,
                )
                if task is None or subroutine_name(task)[1] != "check":
                    line, col = u.at(a)
                    rep.add(
                        u.path,
                        line,
                        col,
                        "bench-check",
                        "errors counted outside check()",
                    )
    comments = sv_comments(u.src)
    for n, _ in u.walk():
        if n.get("tag") != "kInitialStatement":
            continue
        a, b = span(n)
        for ca, _, _, _ in comments:
            if a <= ca < b:
                line, col = u.at(ca)
                rep.add(
                    u.path,
                    line,
                    col,
                    "bench-call-comment",
                    "comment in the initial block, put it above the task",
                )


def is_bench(path):
    if not path.startswith("tb/") or not path.endswith(".sv"):
        return False
    base = os.path.basename(path)
    return base.endswith("_tb.sv") or base == "cosim.sv"


def rtl_files(root=ROOT):
    fs = sorted(
        os.path.relpath(os.path.join(d, f), root)
        for sub in ("rtl", "rtl/single_cycle")
        for d in [os.path.join(root, sub)]
        for f in os.listdir(d)
        if f.endswith(".sv")
    )
    return PKGS + [f for f in fs if f not in PKGS]


def bench_build(path, root=ROOT):
    srcs = rtl_files(root)
    defs = ["-DSIM_BACKDOOR"]
    if path == "tb/cosim.sv":
        defs = ["-DRISCV_FORMAL", "-DCOSIM_DEPTH=256"]
    board = "rtl/boards/bram"
    extra = []
    if path == "tb/board_run_tb.sv":
        board = "rtl/boards/nexys_video"
        extra = ["tb/mig_7series_0.sv"]
    srcs += sorted(
        os.path.join(board, f)
        for f in os.listdir(os.path.join(root, board))
        if f.endswith(".sv")
    )
    return srcs + extra, defs


def slang_json(top, srcs, defs, out, root=ROOT, extra=(), keep=False):
    cmd = [
        "slang",
        "-q",
        "--top",
        top,
        *defs,
        *extra,
        "--timescale=1ns/1ps",
        "-Wno-multiple-always-assigns",
        "--error-limit=0",
        "--ast-json",
        out,
        "--ast-json-source-info",
        *srcs,
    ]
    r = subprocess.run(
        cmd, cwd=root, capture_output=True, text=True, check=False
    )
    if not os.path.exists(out) or os.path.getsize(out) == 0:
        return None, r.stdout + r.stderr
    try:
        with open(out) as f:
            data = json.load(f)
    except ValueError as e:
        data = None
        r.stderr += f"\nunreadable AST JSON: {e}"
    if not keep:
        os.unlink(out)
    return data, r.stdout + r.stderr


def jwalk(n, fn):
    stack = [n]
    while stack:
        x = stack.pop()
        if isinstance(x, dict):
            fn(x)
            stack.extend(x.values())
        elif isinstance(x, list):
            stack.extend(x)


def sym_addr(ref):
    return ref.split(" ", 1)[0] if isinstance(ref, str) else None


def named_symbols(expr):
    out = []
    jwalk(
        expr,
        lambda x: (
            out.append(x["symbol"])
            if x.get("kind") in ("NamedValue", "HierarchicalValue")
            and "symbol" in x
            else None
        ),
    )
    return out


def assign_targets(stmt):
    out = []
    jwalk(
        stmt,
        lambda x: (
            out.append(x["left"])
            if x.get("kind") == "Assignment" and "left" in x
            else None
        ),
    )
    return out


def index_design(data):
    ix = {
        "addr": {},
        "Instance": [],
        "Subroutine": [],
        "Parameter": [],
        "ProceduralBlock": [],
        "HierarchicalValue": [],
    }

    def f(x):
        if "addr" in x and "source_file" in x:
            ix["addr"][str(x["addr"])] = x["source_file"]
        k = x.get("kind")
        if k in ix:
            ix[k].append(x)

    jwalk(data.get("design", data), f)
    return ix


def body_source(inst, ix):
    b = inst.get("body")
    if isinstance(b, dict):
        return b.get("source_file", "")
    return ix["addr"].get(sym_addr(b), "")


def rule_bench_semantic(path, rep, tmp):
    srcs, defs = bench_build(path)
    top = os.path.basename(path)[:-3]
    data, log = slang_json(
        top, srcs + [path], defs, os.path.join(tmp, top + ".json")
    )
    if data is None:
        rep.add(
            path,
            1,
            1,
            "bench-elab",
            f"slang could not elaborate {top}: {log.strip()[:300]}",
        )
        return
    ix = index_design(data)
    duts = [
        i
        for i in ix["Instance"]
        if body_source(i, ix).startswith("rtl/")
        and i.get("source_file", "").startswith("tb/")
    ]
    inputs = {}
    resets = set()
    for i in duts:
        for c in i.get("connections") or []:
            p = c.get("port", {})
            if p.get("direction") not in ("In", "InOut"):
                continue
            for s in named_symbols(c.get("expr", {})):
                inputs[sym_addr(s)] = p.get("name")
            if RESET_PORT.match(p.get("name", "")):
                resets.add(p.get("name"))
    for h in ix["HierarchicalValue"]:
        if h.get("source_file_start") != path:
            continue
        tf = ix["addr"].get(sym_addr(h.get("symbol")), "?")
        if tf != path:
            rep.add(
                path,
                h["source_line_start"],
                h["source_column_start"],
                "bench-hier",
                f"hierarchical reference to {h['symbol'].split(' ', 1)[-1]} in {tf}",
            )
    own = {
        s["name"]: s for s in ix["Subroutine"] if s.get("source_file") == path
    }
    if resets and "do_reset" not in own:
        rep.add(
            path,
            1,
            1,
            "bench-reset",
            f"DUT takes {', '.join(sorted(resets))} but the bench has no do_reset task",
        )
    v = own.get("do_verdict")
    floors = [
        p
        for p in ix["Parameter"]
        if p.get("source_file") == path
        and p.get("name", "").startswith("MinChecks")
    ]
    if v is None:
        rep.add(path, 1, 1, "bench-verdict", "no do_verdict task")
    else:
        names = [s.split(" ", 1)[-1] for s in named_symbols(v)]
        strings = []
        jwalk(
            v,
            lambda x: (
                strings.append(str(x.get("literal", x.get("value", ""))))
                if x.get("kind") == "StringLiteral"
                else None
            ),
        )
        where = (v["source_line"], v["source_column"])
        if not floors:
            rep.add(path, *where, "bench-verdict", "no MinChecks localparam")
        if not any(n.startswith("MinChecks") for n in names):
            rep.add(
                path,
                *where,
                "bench-verdict",
                "do_verdict does not read MinChecks",
            )
        if not any("TB UNDER-RAN" in s for s in strings):
            rep.add(
                path,
                *where,
                "bench-verdict",
                "do_verdict has no TB UNDER-RAN failure",
            )
    for p in ix["ProceduralBlock"]:
        if p.get("procedureKind") != "Initial" or p.get("source_file") != path:
            continue
        targets = [
            sym_addr(s) for t in assign_targets(p) for s in named_symbols(t)[:1]
        ]
        if targets and all(
            CLOCK_NAME.match(inputs.get(t) or "") for t in targets
        ):
            continue
        for line, col, msg in initial_problems(p.get("body"), inputs):
            rep.add(path, line, col, "bench-initial", msg)


def initial_problems(stmt, inputs):
    out = []
    if not isinstance(stmt, dict):
        return out
    k = stmt.get("kind")
    where = (
        stmt.get("source_line_start", 1),
        stmt.get("source_column_start", 1),
    )
    if k in ("Empty", "VariableDeclaration", None):
        return out
    if k == "Block":
        return initial_problems(stmt.get("body"), inputs)
    if k == "List":
        for s in stmt.get("list", []):
            out += initial_problems(s, inputs)
        return out
    if k == "ExpressionStatement":
        e = stmt.get("expr", {})
        if e.get("kind") == "Call":
            return out
        if e.get("kind") == "Assignment":
            for s in named_symbols(e.get("left", {}))[:1]:
                port = inputs.get(sym_addr(s))
                if port:
                    out.append(
                        (
                            *where,
                            f"raw poke of DUT input {port} ({s.split(' ', 1)[-1]})",
                        )
                    )
            return out
        return out + [(*where, f"inline {e.get('kind')} expression")]
    if k == "Timed":
        if stmt.get("timing", {}).get("kind") in ("Delay", "CycleDelay"):
            out.append((*where, "raw delay in the initial block"))
        return out + initial_problems(stmt.get("stmt"), inputs)
    if k == "RepeatLoop":
        b = stmt.get("body", {})
        if (
            b.get("kind") == "Timed"
            and b.get("timing", {}).get("kind") not in ("Delay", "CycleDelay")
            and b.get("stmt", {}).get("kind") == "Empty"
        ):
            return out
        return [(*where, "inline repeat loop")]
    if k == "Wait":
        return initial_problems(stmt.get("stmt"), inputs)
    if k == "Conditional":
        return initial_problems(stmt.get("ifTrue"), inputs) + initial_problems(
            stmt.get("ifFalse"), inputs
        )
    if k in (
        "ForLoop",
        "WhileLoop",
        "DoWhileLoop",
        "ForeverLoop",
        "ForeachLoop",
    ):
        return [(*where, f"inline {k}")]
    return [(*where, f"inline {k} statement")]


def rule_comments(path, src, lines, names, rep):
    if path.endswith(SV_EXT):
        for a, _, kind, body in sv_comments(src):
            line, col = src.pos(a)
            if line not in lines:
                continue
            if kind == "block":
                rep.add(path, line, col, "comment", "block comment")
                continue
            for p in comment_problems(body, names, line):
                rep.add(path, line, col, "comment", f"{p}: //{body.rstrip()}")
        return
    for line, body in hash_comments(path, src.text):
        if line not in lines or (line == 1 and body.startswith("!")):
            continue
        for p in comment_problems(body, names, line):
            rep.add(path, line, 1, "comment", f"{p}: {HASH}{body.rstrip()}")


def commentable(path):
    return (
        path.endswith(SV_EXT + HASH_EXT) or os.path.basename(path) == "Makefile"
    )


def bench_one(path, tmp):
    r = Report()
    rule_bench_semantic(path, r, tmp)
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--base", help="git ref, comments are checked on lines added since it"
    )
    ap.add_argument(
        "--no-elab", action="store_true", help="skip the slang bench checks"
    )
    ap.add_argument("--only", nargs="*", help="limit to these rules")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    rep = Report()
    sv = [
        f
        for f in tracked()
        if f.endswith(SV_EXT) and f.split("/")[0] in ("rtl", "tb", "formal")
    ]
    workers = os.cpu_count() or 4
    with ThreadPoolExecutor(max_workers=workers) as ex:
        units = list(ex.map(Unit, sv))
    units = [u for u in units if rule_parse(u, rep)]
    allow = load_allow()
    for u in units:
        rule_nettype(u, rep)
        rule_ternary(u, rep)
        rule_width(u, rep, allow)
        rule_naming(u, rep)
        rule_bench_syntax(u, rep)
    for e in allow:
        if e.get("bad"):
            rep.add(
                "tests/rules/widths.allow",
                e["line"],
                1,
                "width-allow",
                "entry needs file, signal, width and reason",
            )
        elif not e["used"]:
            rep.add(
                "tests/rules/widths.allow",
                e["line"],
                1,
                "width-allow",
                f"stale entry {e['file']} {e['name']}",
            )
    rule_consts(units, rep)
    if not args.no_elab:
        with tempfile.TemporaryDirectory() as tmp:
            benches = [u.path for u in units if is_bench(u.path)]
            with ThreadPoolExecutor(max_workers=workers) as ex:
                for r in ex.map(lambda p: bench_one(p, tmp), benches):
                    rep.items += r.items
    by_path = {u.path: u for u in units}
    every = set().union(*(u.names for u in units))
    for path, lines in added_lines(args.base).items():
        if not commentable(path) or not os.path.isfile(
            os.path.join(ROOT, path)
        ):
            continue
        u = by_path.get(path)
        src = u.src if u else Src(path)
        names = every | py_names(path, src.text)
        rule_comments(path, src, lines, names, rep)
    if args.files:
        rep.items = [i for i in rep.items if i[0] in args.files]
    if args.only:
        rep.items = [i for i in rep.items if i[3] in args.only]
    n = rep.emit(sys.stdout)
    print(f"{n} rule violations", file=sys.stderr)
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main())
