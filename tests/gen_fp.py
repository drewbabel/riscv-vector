import struct
import random
import subprocess
import argparse

PROLOGUE = [
       ".section .text",
       ".globl _start",
       "_start:",
       "li t0, 0x2000",
       "csrs mstatus, t0",
       "csrwi fflags, 0" # no initial flags
]

PARK = "Ldone: beq x0, x0, Ldone"

LOAD_FLOAT_REG = "li t0, {val}\nfmv.w.x f{N}, t0"

TWO_SOURCE_OPS = ["fadd.s", "fsub.s", "fmul.s"]

RV_VALUES = [
       "0x7f800001", # sNaN
       "0x7fc00000", # NaN
       "0x7f800000", # +inf
       "0xff800000", # -inf
       "0x00000001", # denormalized smallest
       "0x007fffff", # denorm largest
       "0x00800000", # norm smallest
       "0x7f7fffff", # norm largest
       "0x80000000", # -zero
       "0x3f800000", # 1.0
]

def cnv_flt_hexstring(n):
    hex_n = struct.unpack('>I'  , struct.pack('>f', n))[0]
    return f"0x{hex_n:08x}"

def gen_val(rng):
    return rng.choice(RV_VALUES)

def gen_instruction(rng):
    op = rng.choice(TWO_SOURCE_OPS)
    rd, rs1, rs2 = [rng.randrange(32) for _ in range(3)]
    return f"{op} f{rd}, f{rs1}, f{rs2}"

def gen_fp(seed):
    rng = random.Random(seed)
    seed_lines = []
    for i in range(32):
        seed_lines.append(LOAD_FLOAT_REG.format(val=gen_val(rng), N=str(i)))
    c = rng.randint(20, 50)
    body = []
    for i in range(c):
        body.append(gen_instruction(rng))
    lines = PROLOGUE + seed_lines + body + [PARK]
    return "\n".join(lines) + "\n"

ap = argparse.ArgumentParser()
ap.add_argument("--count", type=int, default=10)
ap.add_argument("--seed", type=int, default=0)
args = ap.parse_args()


