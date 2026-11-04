import argparse
import os
import random
import struct
import subprocess
import sys

from shrink import shrink

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (mnemonic, dst file, src files, takes rm)
OP_LIST = [
    ("fmadd.s", "f", "fff", True),
    ("fmsub.s", "f", "fff", True),
    ("fnmsub.s", "f", "fff", True),
    ("fnmadd.s", "f", "fff", True),
    ("fadd.s", "f", "ff", True),
    ("fsub.s", "f", "ff", True),
    ("fmul.s", "f", "ff", True),
    ("fdiv.s", "f", "ff", True),
    ("fsqrt.s", "f", "f", True),
    ("fsgnj.s", "f", "ff", False),
    ("fsgnjn.s", "f", "ff", False),
    ("fsgnjx.s", "f", "ff", False),
    ("fmin.s", "f", "ff", False),
    ("fmax.s", "f", "ff", False),
    ("fcvt.w.s", "x", "f", True),
    ("fcvt.wu.s", "x", "f", True),
    ("fcvt.s.w", "f", "x", True),
    ("fcvt.s.wu", "f", "x", True),
    ("fmv.x.w", "x", "f", False),
    ("fmv.w.x", "f", "x", False),
    ("feq.s", "x", "ff", False),
    ("flt.s", "x", "ff", False),
    ("fle.s", "x", "ff", False),
    ("fclass.s", "x", "f", False),
    ("flw", "f", "mem", False),
    ("fsw", "-", "mem", False),
]

PROLOGUE = [
    ".section .text",
    ".globl _start",
    "_start:",
    "li t0, 0x2000",
    "csrs mstatus, t0",
    "csrwi fflags, 0",  # both sims start with the same flags
    "lui x9, 0x80008",  # Spike memory starts at 0x80000000
]

PARK = "Ldone: beq x0, x0, Ldone"

LOAD_FLOAT_REG = "li t0, {val}\nfmv.w.x f{N}, t0"
LOAD_INT_REG = "li x{N}, {val}"
STORE_WORD = "li t0, {val}\nsw t0, {off}(x9)"


def cnv_flt_hexstring(n):
    hex_n = struct.unpack(">I", struct.pack(">f", n))[0]
    return f"0x{hex_n:08x}"


RV_VALUES = [
    "0x7f800001",  # sNaN
    "0x7fc00000",  # NaN
    "0x7fa5a5a5",  # sNaN with payload
    "0xffc12345",  # -NaN with payload
    "0x7f800000",  # +inf
    "0xff800000",  # -inf
    "0x00000001",  # denormalized smallest
    "0x007fffff",  # denorm largest
    "0x80400000",  # -denorm
    "0x00800000",  # norm smallest
    "0x7f7fffff",  # norm largest
    "0x7f000000",  # large, overflows when doubled
    "0x80000000",  # -zero
    "0x00000000",  # zero
    "0x3f800000",  # 1.0
    "0xbf800000",  # -1.0
    "0x4f000000",  # 2^31, fcvt.w.s saturates
    "0xcf000000",  # -2^31
    "0x4f800000",  # 2^32, fcvt.wu.s saturates
    cnv_flt_hexstring(1.5),  # ties when converted to int
    cnv_flt_hexstring(-2.5),
    cnv_flt_hexstring(1 / 3),  # inexact
    cnv_flt_hexstring(1e-38),  # near the subnormal edge
]

INT_VALUES = [
    "0",
    "1",
    "-1",
    "0x7fffffff",
    "0x80000000",
    "16777217",  # 2^24 + 1, inexact as a float
    "-7",
]

RMS = ["", ", rne", ", rtz", ", rdn", ", rup", ", rmm", ", dyn"]

X_REGS = list(range(10, 21))

WORDS = 16


def gen_val(rng):
    return rng.choice(RV_VALUES)


def gen_int(rng):
    return rng.choice(INT_VALUES)


def pick_reg(rng, kind, last):
    # reuse the previous result to test forwarding and stalls
    if last[kind] is not None and rng.random() < 0.5:
        return last[kind]
    return rng.randrange(32) if kind == "f" else rng.choice(X_REGS)


def gen_instruction(rng, last):
    r = rng.random()
    if r < 0.05:
        return f"fsrmi {rng.randrange(5)}"
    # read flags midprogram - cosim only checks at end
    if r < 0.12:
        rd = rng.choice(X_REGS)
        last["x"] = rd
        return f"frflags x{rd}"
    if r < 0.15:
        return "fsflagsi 0"
    op, dst, srcs, rm = rng.choice(OP_LIST)
    if srcs == "mem":
        off = rng.randrange(WORDS) * 4
        if op == "fsw":
            return f"fsw f{pick_reg(rng, 'f', last)}, {off}(x9)"
        rd = rng.randrange(32)
        last["f"] = rd
        return f"flw f{rd}, {off}(x9)"
    ss = [f"{c}{pick_reg(rng, c, last)}" for c in srcs]
    rd = rng.randrange(32) if dst == "f" else rng.choice(X_REGS)
    last[dst] = rd
    suffix = rng.choice(RMS) if rm else ""
    return f"{op} {dst}{rd}, {', '.join(ss)}{suffix}"


def gen_fp(seed):
    rng = random.Random(seed)
    seed_lines = [f"fsrmi {rng.randrange(5)}"]
    for i in range(32):
        seed_lines.append(LOAD_FLOAT_REG.format(val=gen_val(rng), N=i))
    for i in X_REGS:
        seed_lines.append(LOAD_INT_REG.format(val=gen_int(rng), N=i))
    # write words so mem is initialized
    for i in range(WORDS):
        seed_lines.append(STORE_WORD.format(val=gen_val(rng), off=i * 4))
    c = rng.randint(20, 50)
    last = {"f": None, "x": None}
    body = []
    for i in range(c):
        body.append(gen_instruction(rng, last))
    return seed_lines, body


def render(seed_lines, body):
    lines = PROLOGUE + seed_lines + body + [PARK]
    return "\n".join(lines) + "\n"


# run per program with --fp
def run(name, text):
    with open(os.path.join(ROOT, "build", name + ".s"), "w") as f:
        f.write(text)
    r = subprocess.run(
        ["python3", "tests/cosim.py", "--fp", f"../build/{name}"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    out = (r.stdout + r.stderr).strip().splitlines()
    for i, l in enumerate(out):
        if l.startswith("DIVERGENCE"):
            return False, "\n".join(out[i:])
    return r.returncode == 0, out[-1] if out else "no output"


def clean(name):
    for ext in [".s", ".hex", "_spike.elf"]:
        path = os.path.join(ROOT, "build", name + ext)
        if os.path.exists(path):
            os.remove(path)


def signature(line):
    # shrink only while the same register diverges - no drift to a different bug
    words = line.split()
    return words[1] if len(words) > 1 else line


def shrink_fail(name, seed_lines, body, line):
    sig = signature(line)

    def still_fails(b):
        ok, out = run(name + "_try", render(seed_lines, b))
        return not ok and signature(out) == sig

    small = shrink(body, still_fails)
    clean(name + "_try")
    return small


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--shrink", action="store_true")
    args = ap.parse_args()
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)

    fails = []
    # run sequentially - each cosim rebuilds build/cosim_sim
    for seed in range(args.seed, args.seed + args.count):
        name = f"gen_fp_{seed}"
        seed_lines, body = gen_fp(seed)
        ok, line = run(name, render(seed_lines, body))
        if ok:
            print(f"PASS seed={seed}")
            clean(name)
            continue
        print(f"FAIL seed={seed} " + line.replace("\n", "\n  "))
        fails.append(seed)
        if args.shrink:
            small = shrink_fail(name, seed_lines, body, line)
            with open(os.path.join(ROOT, "build", name + "_min.s"), "w") as f:
                f.write(render(seed_lines, small))
            print(
                f"  shrunk {len(body)} -> {len(small)} instructions, build/{name}_min.s:"
            )
            for insn in small:
                print(f"    {insn}")

    print(f"{args.count - len(fails)}/{args.count} passed")
    if fails:
        print("failing seeds: " + " ".join(str(s) for s in fails))
        sys.exit(1)


if __name__ == "__main__":
    main()
