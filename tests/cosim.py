#!/usr/bin/env python3
# Lockstep co-sim of the pipelined core against Spike
# python3 tests/cosim.py <prog> | --rand [count] [seed0]

import os
import random
import re
import signal
import subprocess
import sys

BASE = 0x8000_0000  # Spike DRAM base
DEPTH = 64
MASK32 = 0xFFFF_FFFF
ABS_PC_OPS = {0x17, 0x6F, 0x67}  # auipc jal jalr
STORE_WIDTH = {0: 1, 1: 2, 2: 4}  # store funct3 to byte count

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
PKGS = ["alu_pkg.sv", "csr_pkg.sv", "opcode_pkg.sv", "muldiv_pkg.sv", "bp_pkg.sv", "cache_pkg.sv"]
RTL = [os.path.join(ROOT, "rtl", p) for p in PKGS] + [
    os.path.join(ROOT, "rtl", f)
    for f in sorted(os.listdir(os.path.join(ROOT, "rtl")))
    if f.endswith(".sv") and f not in PKGS
]

RVGCC = "riscv64-elf-gcc"
SIM = os.path.join(BUILD, "cosim_sim")

SCALAR_MARCH = "rv32im"
VECTOR_MARCH = "rv32im_zve32x_zvl128b"  # Zvl128b or VLEN reads 32
VECTOR = False

VL_ADDR, VTYPE_ADDR, VSTART_ADDR = 0xC20, 0xC21, 0x008
VTYPE_RESET = 0x8000_0000  # vill set out of reset


def march():
    return VECTOR_MARCH if VECTOR else SCALAR_MARCH


def gcc_common():
    return [f"-march={march()}", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-Os"]


def sh(cmd):
    subprocess.run(cmd, check=True, cwd=ROOT)


# Compile the monitor
def compile_monitor():
    os.makedirs(BUILD, exist_ok=True)
    r = subprocess.run(["iverilog", "-g2012", "-DRISCV_FORMAL", "-s", "cosim", "-o", SIM, *RTL,
                        os.path.join("tb", "cosim.sv")], cwd=ROOT, capture_output=True, text=True)
    notes = [l for l in r.stderr.splitlines() if "sorry: constant selects" not in l]
    if notes:
        print("\n".join(notes), file=sys.stderr)
    if r.returncode:
        sys.exit(r.returncode)


# dut hex plus spike elf
def build_images(src, hexout, spike_elf):
    dut_elf = os.path.join(BUILD, "dut.elf")
    sh([RVGCC, *gcc_common(), "-T", "tests/link.ld", "-o", dut_elf, src])
    sh(["riscv64-elf-objcopy", "-O", "verilog", "--verilog-data-width=4", dut_elf, hexout])
    sh([RVGCC, *gcc_common(), "-T", "tests/link_spike.ld", "-o", spike_elf, src])


COMMIT_RE = re.compile(
    r"COMMIT ([0-9a-f]+) (\d+) ([0-9a-f]+) (\d+) ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+)"
    r" ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+)")


# dut commit trace
TRACE_RE = re.compile(r"TRACE (\d+) ([0-9a-f]+) ([0-9a-f]+)")
VCD = os.path.join(BUILD, "cosim.vcd")
TRACE = []  # Retirement times


def run_dut(dut_hex, vcd=False):
    args = ["vvp", SIM, f"+hex={dut_hex}", "+n=8000"]
    if vcd:
        args.append(f"+vcd={VCD}")
    out = subprocess.run(args, cwd=ROOT, capture_output=True, text=True).stdout
    trace = []
    TRACE.clear()
    for line in out.splitlines():
        t = TRACE_RE.match(line)
        if t:
            TRACE.append((int(t.group(1)), int(t.group(2), 16), int(t.group(3), 16)))
            continue
        m = COMMIT_RE.match(line)
        if not m:
            continue
        pc, rd, val, mw, maddr, wstrb, sdata, vl, vtb, vti, vst = m.groups()
        rd_i = int(rd)
        val_i = (int(val, 16) & MASK32) if rd_i else 0  # x0 carries no value
        store = None
        if mw == "1":  # written bytes, one entry per strobed lane
            ws, sd = int(wstrb, 16), int(sdata, 16)
            widx = (int(maddr, 16) >> 2) & (DEPTH - 1)
            store = (widx, tuple((i, (sd >> (8 * i)) & 0xFF) for i in range(4) if ws & (1 << i)))
        vec = None
        if VECTOR:  # vtype is the two raw fields recomposed
            vec = (int(vl, 16), (int(vti, 16) << 31) | int(vtb, 16), int(vst, 16))
        trace.append((int(pc, 16), rd_i, val_i, store, vec))
    return trace


SPIKE_RE = re.compile(r"core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)")  # commit line

VCSR_RE = re.compile(r"\bc(\d+)_\w+\s+0x([0-9a-f]+)")  # a control register Spike changed


# Golden spike trace
def run_spike(spike_elf, n):
    maxlines = 4 * n + 200  # Spike ignores SIGPIPE
    cmd = ["spike", f"--isa={march()}", f"--pc={hex(BASE)}", "-l",
           "--log-commits", spike_elf]
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            start_new_session=True)
    lines = []
    try:
        for line in proc.stdout:
            lines.append(line)
            if len(lines) >= maxlines:
                break
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.stdout.close()
        proc.wait(timeout=10)
    out = "".join(lines)
    trace = []
    shadow = {VL_ADDR: 0, VTYPE_ADDR: VTYPE_RESET, VSTART_ADDR: 0}
    for line in out.splitlines():
        m = SPIKE_RE.match(line)
        if not m:
            continue
        pc_raw, instr_hex, tail = m.groups()
        insn = int(instr_hex, 16)
        opcode = insn & 0x7F
        rd, val = 0, 0
        rm = re.search(r"(?:^|\s)x(\d+)\s+0x([0-9a-f]+)", tail)  # register write
        if rm:
            rd = int(rm.group(1))
            val = int(rm.group(2), 16) & MASK32
            if opcode in ABS_PC_OPS and rd != 0:
                val = (val - BASE) & MASK32  # to dut space
        for addr, hexval in VCSR_RE.findall(tail):  # Spike prints only on change
            if int(addr) in shadow:
                shadow[int(addr)] = int(hexval, 16)
        vec = (shadow[VL_ADDR], shadow[VTYPE_ADDR], shadow[VSTART_ADDR]) if VECTOR else None
        store = None
        sm = re.search(r"mem\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)", tail)
        if sm:
            saddr, sval = int(sm.group(1), 16), int(sm.group(2), 16)
            width = STORE_WIDTH[(insn >> 12) & 0x7]  # sb=1 sh=2 sw=4
            off = saddr & 0x3
            widx = (saddr >> 2) & (DEPTH - 1)
            store = (widx, tuple((off + k, (sval >> (8 * k)) & 0xFF) for k in range(width)))
        pc = (int(pc_raw, 16) - BASE) & MASK32  # to dut space
        trace.append((pc, rd if rd != 0 else 0, val, store, vec))
        if len(trace) >= n:
            break
    return trace


def fmt(rec):
    pc, rd, val, store, vec = rec
    parts = [f"pc={pc:08x}", f"x{rd}={val:08x}" if rd else "x0"]
    if store is not None:
        widx, bs = store
        parts.append(f"mem[w{widx}] " + " ".join(f"b{i}={b:02x}" for i, b in bs))
    if vec is not None:
        vl, vtype, vstart = vec
        parts += [f"vl={vl}", f"vtype={vtype:08x}", f"vstart={vstart}"]
    return "  ".join(parts)


# Disassemble words
def disasm(words):
    raw = os.path.join(BUILD, "disasm.bin")
    with open(raw, "wb") as f:
        for w in words:
            f.write((w & MASK32).to_bytes(4, "little"))
    out = subprocess.run(["riscv64-elf-objdump", "-D", "-b", "binary", "-m", "riscv:rv32",
                          "-M", "numeric,no-aliases", raw], capture_output=True, text=True).stdout
    text = {}
    for line in out.splitlines():
        m = re.match(r"\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)", line)
        if m:
            text[int(m.group(1), 16) // 4] = m.group(2).replace("\t", " ").strip()
    return [text.get(i, "?") for i in range(len(words))]


# Tracer log
def write_trace(path, dut):
    asm = disasm([insn for _, _, insn in TRACE])
    with open(path, "w") as f:
        for (t, pc, insn), a, rec in zip(TRACE, asm, dut):
            rd, val = rec[1], rec[2]
            f.write(f"{t:>8} {pc:08x} {insn:08x}  {a:<28} " + (f"x{rd}={val:08x}" if rd else "") + "\n")


# Locate divergence
def locate(i):
    if i >= len(TRACE):
        return ""
    t, pc, insn = TRACE[i]
    a = disasm([insn])[0]
    cmd = os.path.join(BUILD, "cosim_goto.sucl")
    with open(cmd, "w") as f:
        f.write(f"goto_time {t}\n")
    layout = os.path.join(BUILD, "pipeline_cosim.ron")
    with open(os.path.join(ROOT, "tb", "surfer", "pipeline.ron.in")) as f:
        ron = f.read().replace("@TOP@", "cosim").replace("@A@", "dut").replace("@B@", "riscv_pipelined_inst")
    with open(layout, "w") as f:
        f.write(ron)
    surfer = ["surfer", os.path.relpath(VCD, ROOT), "-s", os.path.relpath(layout, ROOT),
              "-c", os.path.relpath(cmd, ROOT)]
    if sys.stdout.isatty() and not os.environ.get("CI"):  # Open the waveform
        subprocess.Popen(surfer, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    return f"\n  at time {t}  pc={pc:08x}  {a}\n  " + " ".join(surfer)


# First mismatch wins
def compare(dut, spike):
    n = min(len(dut), len(spike))
    for i in range(n):
        if dut[i] != spike[i]:
            why = ""
            if dut[i][4] != spike[i][4] and dut[i][:4] == spike[i][:4]:
                names = ("vl", "vtype", "vstart")
                bad = [n for n, a, b in zip(names, dut[i][4], spike[i][4]) if a != b]
                why = f" ({', '.join(bad)})"
            return False, f"instr {i}{why}\n  DUT   {fmt(dut[i])}\n  Spike {fmt(spike[i])}" + locate(i)
    if len(dut) != len(spike):
        return False, f"length DUT {len(dut)} Spike {len(spike)}"
    return True, n


# Randomized program generation

R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
BR_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
MUL_OPS = ["mul", "mulh", "mulhsu", "mulhu"]
DIV_OPS = ["div", "divu", "rem", "remu"]
BASE_REG = 3  # data pointer
DSTS = [r for r in range(1, 32) if r != BASE_REG]


# Program for one seed
def gen(seed):
    rng = random.Random(seed)
    mode = "linear" if seed % 2 == 0 else "control"
    n = rng.randint(24, 50)
    written = set()
    body = []

    def rd():
        return rng.choice(DSTS)

    def rs():
        return rng.randint(0, 31)

    for i in range(n):
        # Linear loads, no base-relative ops
        mem_st = ["stb", "sth"] if written else []
        mem_ld = ["ldb", "ldh"] if written else []
        if mode == "linear":
            pool = ["r", "i", "sh", "lui", "mul", "div", "sw"] + (["lw"] if written else []) + mem_st + mem_ld
        else:
            pool = ["r", "i", "sh", "lui", "mul", "div", "sw", "branch", "jal"] + mem_st
        kind = rng.choice(pool)

        match kind:
            case "r":
                body.append(f"{rng.choice(R_OPS)} x{rd()}, x{rs()}, x{rs()}")
            case "i":
                body.append(f"{rng.choice(I_OPS)} x{rd()}, x{rs()}, {rng.randint(-2048, 2047)}")
            case "sh":
                body.append(f"{rng.choice(SH_OPS)} x{rd()}, x{rs()}, {rng.randint(0, 31)}")
            case "lui":
                body.append(f"lui x{rd()}, {rng.randint(0, 0xFFFFF)}")
            case "mul":
                body.append(f"{rng.choice(MUL_OPS)} x{rd()}, x{rs()}, x{rs()}")
            case "div":
                body.append(f"{rng.choice(DIV_OPS)} x{rd()}, x{rs()}, x{rs()}")
            case "sw":
                word = rng.randint(0, DEPTH - 1)
                written.add(word)
                body.append(f"sw x{rs()}, {word * 4}(x{BASE_REG})")
            case "lw":
                word = rng.choice(sorted(written))
                body.append(f"lw x{rd()}, {word * 4}(x{BASE_REG})")
            case "stb":
                word = rng.choice(sorted(written))
                body.append(f"sb x{rs()}, {word * 4 + rng.randint(0, 3)}(x{BASE_REG})")
            case "sth":
                word = rng.choice(sorted(written))
                body.append(f"sh x{rs()}, {word * 4 + rng.choice([0, 2])}(x{BASE_REG})")
            case "ldb":
                word = rng.choice(sorted(written))
                body.append(f"{rng.choice(['lb', 'lbu'])} x{rd()}, {word * 4 + rng.randint(0, 3)}(x{BASE_REG})")
            case "ldh":
                word = rng.choice(sorted(written))
                body.append(f"{rng.choice(['lh', 'lhu'])} x{rd()}, {word * 4 + rng.choice([0, 2])}(x{BASE_REG})")
            case "branch":
                tgt = rng.choice([f"L{k}" for k in range(i + 1, n)] + ["Ldone"])
                body.append(f"{rng.choice(BR_OPS)} x{rs()}, x{rs()}, {tgt}")
            case "jal":
                tgt = rng.choice([f"L{k}" for k in range(i + 1, n)] + ["Ldone"])
                body.append(f"jal x0, {tgt}")

    # Base 0x80008000 clears the code in Spike
    lines = ["        .section .text", "        .globl _start", "_start:",
             f"        lui x{BASE_REG}, 0x80008"]
    for i, insn in enumerate(body):
        lines.append(f"L{i}: {insn}")
    lines.append("Ldone: beq x0, x0, Ldone")  # park sentinel
    return "\n".join(lines) + "\n", mode


# Build run compare
def run_one(src):
    dut_hex = os.path.join(BUILD, "prog.hex")
    spike_elf = os.path.join(BUILD, "prog_spike.elf")
    build_images(src, dut_hex, spike_elf)
    dut = run_dut(dut_hex)
    spike = run_spike(spike_elf, len(dut))
    return compare(dut, spike)


def main():
    global VECTOR
    if "--vec" in sys.argv[1:]:
        VECTOR = True
        sys.argv.remove("--vec")

    if len(sys.argv) >= 2 and sys.argv[1] == "--rand":  # random regression
        count = int(sys.argv[2]) if len(sys.argv) >= 3 else 200
        seed0 = int(sys.argv[3]) if len(sys.argv) >= 4 else 0
        compile_monitor()
        total = 0
        for seed in range(seed0, seed0 + count):
            asm, mode = gen(seed)
            src = os.path.join(BUILD, "rand.s")
            with open(src, "w") as f:
                f.write(asm)
            ok, detail = run_one(src)
            if not ok:
                fail = os.path.join(BUILD, f"fail_{seed}.s")  # reproducible seed
                with open(fail, "w") as f:
                    f.write(asm)
                print(f"FAIL seed={seed} mode={mode}\n{detail}\nprogram saved to {fail}")
                sys.exit(1)
            total += detail
        print(f"RANDOM PASS: {count} programs, {total} instructions matched Spike")
        return

    want_trace = "--trace" in sys.argv
    if want_trace:
        sys.argv.remove("--trace")
    if len(sys.argv) != 2:
        sys.exit("usage: python3 tests/cosim.py [--vec] [--trace] <prog> | --rand [count] [seed0]")
    prog = sys.argv[1]  # single program, assembly or C
    compile_monitor()
    src_c = os.path.join("tests", f"{prog}.c")
    src = src_c if os.path.exists(src_c) else os.path.join("tests", f"{prog}.s")
    dut_hex = os.path.join("tests", f"{prog}.hex")
    spike_elf = os.path.join(BUILD, f"{prog}_spike.elf")
    build_images(src, dut_hex, spike_elf)
    dut = run_dut(dut_hex, vcd=True)
    spike = run_spike(spike_elf, len(dut))
    if want_trace:
        log = os.path.join(BUILD, f"{prog}.trace")
        write_trace(log, dut)
        print(f"trace written to {os.path.relpath(log, ROOT)}")
    ok, detail = compare(dut, spike)
    if not ok:
        print(f"DIVERGENCE {detail}")
        sys.exit(1)
    print(f"LOCKSTEP PASS: {detail} instructions match Spike ({prog})")


if __name__ == "__main__":
    main()
