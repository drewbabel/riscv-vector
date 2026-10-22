#!/usr/bin/env python3
# Lockstep co-sim of the pipelined core against Spike
# python3 tests/cosim.py <prog> | --rand [count] [seed0]

import gzip
import json
import os
import random
import re
import shutil
import signal
import struct
import subprocess
import sys

BASE = 0x8000_0000  # Spike DRAM base
DEPTH = 256
MASK32 = 0xFFFF_FFFF
ABS_PC_OPS = {0x17, 0x6F, 0x67}  # auipc jal jalr
STORE_WIDTH = {0: 1, 1: 2, 2: 4}  # store funct3 to byte count

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
PKGS = [
    "arch_pkg.sv",
    "alu_pkg.sv",
    "csr_pkg.sv",
    "opcode_pkg.sv",
    "fp_pkg.sv",
    "muldiv_pkg.sv",
    "bp_pkg.sv",
    "cache_pkg.sv",
    "vec_pkg.sv",
]
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
FP_MARCH = "rv32imf_zicsr"
FP = False
VECTOR_FP_MARCH = "rv32imf_zicsr_zve32f_zvl128b"

VL_ADDR, VTYPE_ADDR, VSTART_ADDR = 0xC20, 0xC21, 0x008
VTYPE_RESET = 0x8000_0000  # vill set out of reset

GEN_MARCH = "rv32im_zicsr_zve32x_zvl128b"
ENV_DIR = os.path.join(ROOT, "tests", "rvv_env")
GEN_OUT = os.path.join(BUILD, "rvv")
GEN_CAP = 2_000_000
GEN_DEPTH = 131072
SPAN = None

STALL = False
STALL_PCT = 40  # Chance a transfer waits
STALL_MAX = 6  # Longest wait in cycles
STALL_SLOW = 8  # Cycle budget scale
STALLS = [0, 0]  # Fetch and data waits

IRQ = False
IRQ_RATE = 8  # Per mille per cycle
IRQ_SRC = os.path.join(ROOT, "tests", "spike_irq.cc")
IRQ_SIM = os.path.join(BUILD, "spike_irq")
MIP_MEIP, MIP_MTIP = 1 << 11, 1 << 7
MEPC_ADDR = 0x341


def march():
    if FP and VECTOR:
        return VECTOR_FP_MARCH
    if FP:
        return FP_MARCH
    if VECTOR:
        return VECTOR_MARCH
    return SCALAR_MARCH + ("_zicsr" if IRQ else "")


def gcc_common():
    return [
        f"-march={march()}",
        "-mabi=ilp32",
        "-nostdlib",
        "-nostartfiles",
        "-Os",
    ]


def sh(cmd):
    subprocess.run(cmd, check=True, cwd=ROOT)


# Compile the monitor
def compile_monitor():
    os.makedirs(BUILD, exist_ok=True)
    r = subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-DRISCV_FORMAL",
            f"-DCOSIM_DEPTH={DEPTH}",
            "-s",
            "cosim",
            "-o",
            SIM,
            *RTL,
            os.path.join("tb", "cosim.sv"),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    notes = [
        l for l in r.stderr.splitlines() if "sorry: constant selects" not in l
    ]
    if notes:
        print("\n".join(notes), file=sys.stderr)
    if r.returncode:
        sys.exit(r.returncode)


# Interrupt stepping Spike
def build_irq_sim():
    if os.path.exists(IRQ_SIM) and os.path.getmtime(
        IRQ_SIM
    ) >= os.path.getmtime(IRQ_SRC):
        return
    spike = shutil.which("spike")
    if not spike:
        sys.exit("spike not on PATH")
    prefix = os.path.dirname(os.path.dirname(os.path.realpath(spike)))
    os.makedirs(BUILD, exist_ok=True)
    sh(
        [
            os.environ.get("CXX", "c++"),
            "-std=c++20",
            "-O2",
            f"-I{prefix}/include",
            "-o",
            IRQ_SIM,
            IRQ_SRC,
            f"-L{prefix}/lib",
            f"-Wl,-rpath,{prefix}/lib",
            "-lriscv",
            "-lfesvr",
        ]
    )


# dut hex plus spike elf
def build_images(src, hexout, spike_elf):
    dut_elf = os.path.join(BUILD, "dut.elf")
    sh([RVGCC, *gcc_common(), "-T", "tests/link.ld", "-o", dut_elf, src])
    sh(
        [
            "riscv64-elf-objcopy",
            "-O",
            "verilog",
            "--verilog-data-width=4",
            dut_elf,
            hexout,
        ]
    )
    sh(
        [
            RVGCC,
            *gcc_common(),
            "-T",
            "tests/link_spike.ld",
            "-o",
            spike_elf,
            src,
        ]
    )


COMMIT_RE = re.compile(
    r"COMMIT ([0-9a-f]+) (\d+) ([0-9a-f]+) (\d+) ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+)"
    r" ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+)"
)


# dut commit trace
TRACE_RE = re.compile(r"TRACE (\d+) ([0-9a-f]+) ([0-9a-f]+)")
VCOMMIT_RE = re.compile(r"VCOMMIT (\d+) (\d+) ([0-9a-f]+)")
VMEM_RE = re.compile(r"VMEM ([0-9a-f]+) ([0-9a-f]{4}) ([0-9a-f]+)")
FCOMMIT_RE = re.compile(r"FCOMMIT (\d+) ([0-9a-f]+)")
FCSR_RE = re.compile(r"FCSR ([0-9a-f]+)")
STALLS_RE = re.compile(r"STALLS (\d+) (\d+)")
IRQ_RE = re.compile(r"IRQ (\d+) (\d) (\d)")
DUT_IRQ = []  # Retired count and lines
IRQ_LOST = []  # Enabled line not taken
SPK_IRQ_MISS = []  # Spike did not trap
SPIKE_F_RE = re.compile(r"(?:^|\s)f(\d+)\s+0x([0-9a-f]+)")
SPIKE_FCSR_RE = re.compile(r"\bc(1|2|3)_(?:fflags|frm|fcsr)\s+0x([0-9a-f]+)")
DUT_FWR = []
SPK_FWR = []
FCSR = {"dut": None, "spike": 0}
VCD = os.path.join(BUILD, "cosim.vcd")
TRACE = []  # Retirement times
DUT_VWR = []  # Vector writes
SPK_VWR = []  # Vector writes
DUT_VMEM = []  # Vector store bytes
FAULTS = []  # Monitor faults
HUNG = []  # Never reached the end
SPK_VMEM = []  # Vector store bytes
SPK_VWR_AT = []
SPK_VMEM_AT = []
DUT_TRAP = []
DTRAP_RE = re.compile(r"DTRAP (\d+) ([0-9a-f]+) ([0-9a-f]+)")
VEC_WIDTH = {0: 1, 5: 2, 6: 4}  # width field to byte count


def run_dut(
    dut_hex, vcd=False, n=8000, gen=False, stall_seed=None, irq_seed=None
):
    if stall_seed is not None:
        n *= STALL_SLOW
    args = ["vvp", SIM, f"+hex={dut_hex}", f"+n={n}"]
    if stall_seed is not None:
        args += [
            f"+stall={STALL_PCT}",
            f"+stall_max={STALL_MAX}",
            f"+stall_seed={stall_seed}",
        ]
    if irq_seed is not None:
        args += [f"+irq={IRQ_RATE}", f"+irq_seed={irq_seed}"]
    if gen:
        args += ["+preload_dmem=1", "+log_traps=1"]
    if vcd:
        args.append(f"+vcd={VCD}")
    out = subprocess.run(
        args, cwd=ROOT, capture_output=True, text=True, check=False
    ).stdout
    FAULTS.clear()
    FAULTS.extend(
        l
        for l in out.splitlines()
        if l.startswith(("FENCE BUSY", "VEC REISSUE"))
    )
    HUNG.clear()
    HUNG.extend(l for l in out.splitlines() if l.startswith("HUNG"))
    IRQ_LOST.clear()
    IRQ_LOST.extend(l for l in out.splitlines() if l.startswith("IRQ LOST"))
    DUT_IRQ.clear()
    trace = []
    TRACE.clear()
    DUT_VWR.clear()
    DUT_VMEM.clear()
    DUT_TRAP.clear()
    DUT_FWR.clear()
    FCSR["dut"] = None
    for line in out.splitlines():
        fw = FCOMMIT_RE.match(line)
        if fw:
            DUT_FWR.append((int(fw.group(1)), int(fw.group(2), 16) & MASK32))
            continue
        iq = IRQ_RE.match(line)
        if iq:
            DUT_IRQ.append(
                (
                    int(iq.group(1)),
                    MIP_MEIP * int(iq.group(2)) | MIP_MTIP * int(iq.group(3)),
                )
            )
            continue
        st = STALLS_RE.match(line)
        if st:
            STALLS[0] += int(st.group(1))
            STALLS[1] += int(st.group(2))
            continue
        fc = FCSR_RE.match(line)
        if fc:
            FCSR["dut"] = int(fc.group(1), 16)
            continue
        dt = DTRAP_RE.match(line)
        if dt:
            DUT_TRAP.append(
                (
                    len(trace),
                    int(dt.group(1)),
                    int(dt.group(2), 16),
                    int(dt.group(3), 16),
                )
            )
            continue
        vm = VMEM_RE.match(line)
        if vm:  # strobed bytes of a beat
            addr, ws, wd = (
                int(vm.group(1), 16),
                int(vm.group(2), 16),
                int(vm.group(3), 16),
            )
            for k in range(16):
                if ws & (1 << k):
                    DUT_VMEM.append(
                        ((addr + k) & (DEPTH * 4 - 1), (wd >> (8 * k)) & 0xFF)
                    )
            continue
        v = VCOMMIT_RE.match(line)
        if v:
            DUT_VWR.append(
                (int(v.group(1)), int(v.group(2)), int(v.group(3), 16))
            )
            continue
        t = TRACE_RE.match(line)
        if t:
            TRACE.append(
                (int(t.group(1)), int(t.group(2), 16), int(t.group(3), 16))
            )
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
            store = (
                widx,
                tuple(
                    (i, (sd >> (8 * i)) & 0xFF)
                    for i in range(4)
                    if ws & (1 << i)
                ),
            )
        vec = None
        if VECTOR:  # vtype is the two raw fields recomposed
            vec = (
                int(vl, 16),
                (int(vti, 16) << 31) | int(vtb, 16),
                int(vst, 16),
            )
        trace.append((int(pc, 16), rd_i, val_i, store, vec))
    return trace


SPIKE_RE = re.compile(
    r"core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)"
)  # commit line

VCSR_RE = re.compile(
    r"\bc(\d+)_\w+\s+0x([0-9a-f]+)"
)  # a control register Spike changed

SPIKE_V_RE = re.compile(
    r"\bv(\d+)\s+0x([0-9a-f]{32})"
)  # a vector register Spike wrote


def elf_span(path):
    with open(path, "rb") as f:
        head = f.read(52)
        (phoff,) = struct.unpack_from("<I", head, 28)
        phentsize, phnum = struct.unpack_from("<HH", head, 42)
        f.seek(phoff)
        ph = f.read(phentsize * phnum)
    segs = [struct.unpack_from("<6I", ph, k * phentsize) for k in range(phnum)]
    loads = [(s[2], s[2] + s[5]) for s in segs if s[0] == 1 and s[5]]
    return min(a for a, _ in loads), max(b for _, b in loads)


# Golden spike trace
def run_spike(spike_elf, n, isa=None, park=False):
    global SPAN
    SPAN = elf_span(spike_elf) if park else None
    maxlines = 4 * n + 200  # Spike ignores SIGPIPE
    cmd = [
        "spike",
        f"--isa={isa or march()}",
        f"--pc={hex(BASE)}",
        "-l",
        "--log-commits",
        spike_elf,
    ]
    if IRQ and not park:
        build_irq_sim()
        points = ",".join(f"{k}:{mask}" for k, mask in DUT_IRQ) or "-"
        cmd = [IRQ_SIM, isa or march(), str(n), points, spike_elf]
    if park:
        maxlines = GEN_CAP + 200
        cmd = [
            "spike",
            f"--isa={isa or march()}",
            f"--pc={hex(BASE)}",
            "--log-commits",
            f"--instructions={GEN_CAP}",
            spike_elf,
        ]
    proc = subprocess.Popen(
        cmd,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    lines = []
    last = None
    try:
        for line in proc.stdout:
            if park:
                pm = SPIKE_RE.match(line)
                if pm:
                    if pm.group(1) == last:
                        break
                    last = pm.group(1)
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
    SPK_IRQ_MISS.clear()
    SPK_IRQ_MISS.extend(l for l in lines if l.startswith("IRQ MISSED"))
    SPK_VWR.clear()
    SPK_VMEM.clear()
    SPK_VWR_AT.clear()
    SPK_VMEM_AT.clear()
    SPK_FWR.clear()
    fcsr = 0
    vtag = 0
    shadow = {VL_ADDR: 0, VTYPE_ADDR: VTYPE_RESET, VSTART_ADDR: 0}
    for line in out.splitlines():
        m = SPIKE_RE.match(line)
        if not m:
            continue
        pc_raw, instr_hex, tail = m.groups()
        insn = int(instr_hex, 16)
        opcode = insn & 0x7F
        rd, val = 0, 0
        rm = re.search(
            r"(?:^|\s)x(\d+)\s+0x([0-9a-f]+)", tail
        )  # register write
        if rm:
            rd = int(rm.group(1))
            val = int(rm.group(2), 16) & MASK32
            if opcode in ABS_PC_OPS and rd != 0:
                val = (val - BASE) & MASK32  # to dut space
            if IRQ and opcode == 0x73 and insn >> 20 == MEPC_ADDR:
                val = (val - BASE) & MASK32
        for freg, fhex in SPIKE_F_RE.findall(tail):
            SPK_FWR.append((int(freg), int(fhex, 16) & MASK32))
        for caddr, chex in SPIKE_FCSR_RE.findall(tail):
            cval = int(chex, 16)
            if caddr == "1":
                fcsr = (fcsr & 0xE0) | (cval & 0x1F)
            elif caddr == "2":
                fcsr = (fcsr & 0x1F) | ((cval & 0x7) << 5)
            else:
                fcsr = cval & 0xFF
        vwr = SPIKE_V_RE.findall(tail)
        if vwr:
            for vreg, vhex in vwr:
                SPK_VWR.append((vtag, int(vreg), int(vhex, 16)))
                SPK_VWR_AT.append(len(trace))
            vtag += 1
        for addr, hexval in VCSR_RE.findall(
            tail
        ):  # Spike prints only on change
            if int(addr) in shadow:
                shadow[int(addr)] = int(hexval, 16)
        vec = (
            (shadow[VL_ADDR], shadow[VTYPE_ADDR], shadow[VSTART_ADDR])
            if VECTOR
            else None
        )
        if opcode == 0x27:  # vector store elements
            size = VEC_WIDTH[(insn >> 12) & 0x7]
            for eaddr, ehex in re.findall(
                r"mem\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)", tail
            ):
                for k in range(size):
                    SPK_VMEM.append(
                        (
                            (int(eaddr, 16) + k) & (DEPTH * 4 - 1),
                            (int(ehex, 16) >> (8 * k)) & 0xFF,
                        )
                    )
                    SPK_VMEM_AT.append(len(trace))
        store = None
        sm = re.search(r"mem\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)", tail)
        if sm and opcode == 0x23:
            saddr, sval = int(sm.group(1), 16), int(sm.group(2), 16)
            width = STORE_WIDTH[(insn >> 12) & 0x7]  # sb=1 sh=2 sw=4
            off = saddr & 0x3
            widx = (saddr >> 2) & (DEPTH - 1)
            store = (
                widx,
                tuple(
                    (off + k, (sval >> (8 * k)) & 0xFF) for k in range(width)
                ),
            )
        pc = (int(pc_raw, 16) - BASE) & MASK32  # to dut space
        trace.append((pc, rd if rd != 0 else 0, val, store, vec))
        if len(trace) >= n:
            break
    FCSR["spike"] = fcsr
    return trace


def fmt(rec):
    pc, rd, val, store, vec = rec
    parts = [f"pc={pc:08x}", f"x{rd}={val:08x}" if rd else "x0"]
    if store is not None:
        widx, bs = store
        parts.append(
            f"mem[w{widx}] " + " ".join(f"b{i}={b:02x}" for i, b in bs)
        )
    if vec is not None:
        vl, vtype, vstart = vec
        parts += [f"vl={vl}", f"vtype={vtype:08x}", f"vstart={vstart}"]
    return "  ".join(parts)


# Disassemble words
def disasm(words):
    raw = os.path.join(BUILD, "disasm.bin")
    with open(raw, "wb") as f:
        f.writelines((w & MASK32).to_bytes(4, "little") for w in words)
    out = subprocess.run(
        [
            "riscv64-elf-objdump",
            "-D",
            "-b",
            "binary",
            "-m",
            "riscv:rv32",
            "-M",
            "numeric,no-aliases",
            raw,
        ],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    text = {}
    for line in out.splitlines():
        m = re.match(r"\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)", line)
        if m:
            text[int(m.group(1), 16) // 4] = (
                m.group(2).replace("\t", " ").strip()
            )
    return [text.get(i, "?") for i in range(len(words))]


# Tracer log
def write_trace(path, dut):
    asm = disasm([insn for _, _, insn in TRACE])
    with open(path, "w") as f:
        for (t, pc, insn), a, rec in zip(TRACE, asm, dut):
            rd, val = rec[1], rec[2]
            f.write(
                f"{t:>8} {pc:08x} {insn:08x}  {a:<28} "
                + (f"x{rd}={val:08x}" if rd else "")
                + "\n"
            )


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
        ron = (
            f.read()
            .replace("@TOP@", "cosim")
            .replace("@A@", "dut")
            .replace("@B@", "riscv_pipelined_inst")
        )
    with open(layout, "w") as f:
        f.write(ron)
    surfer = [
        "surfer",
        os.path.relpath(VCD, ROOT),
        "-s",
        os.path.relpath(layout, ROOT),
        "-c",
        os.path.relpath(cmd, ROOT),
    ]
    if sys.stdout.isatty() and not os.environ.get("CI"):  # Open the waveform
        subprocess.Popen(
            surfer,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    return f"\n  at time {t}  pc={pc:08x}  {a}\n  " + " ".join(surfer)


# First mismatch wins
# Vector writes
def compare_vec():
    n = min(len(DUT_VWR), len(SPK_VWR))
    for i in range(n):
        dt, dr, dv = DUT_VWR[i]
        st, sr, sv = SPK_VWR[i]
        if (dr, dv) != (sr, sv):
            return False, (
                f"vector write {i} (dut tag {dt}, spike tag {st})\n"
                f"  DUT   v{dr} {dv:032x}\n  Spike v{sr} {sv:032x}"
            )
    if len(DUT_VWR) != len(SPK_VWR):
        return (
            False,
            f"vector write count DUT {len(DUT_VWR)} Spike {len(SPK_VWR)}",
        )
    return True, n


def compare_fp():
    for r in range(32):
        d = [v for g, v in DUT_FWR if g == r]
        s = [v for g, v in SPK_FWR if g == r]
        for i in range(min(len(d), len(s))):
            if d[i] != s[i]:
                return (
                    False,
                    f"f{r} write {i}\n  DUT   {d[i]:08x}\n  Spike {s[i]:08x}",
                )
        if len(d) != len(s):
            return False, f"f{r} write count DUT {len(d)} Spike {len(s)}"
    if FCSR["dut"] != FCSR["spike"]:
        dut_fcsr = "none" if FCSR["dut"] is None else f"{FCSR['dut']:02x}"
        return False, f"final fcsr DUT {dut_fcsr} Spike {FCSR['spike']:02x}"
    return True, len(DUT_FWR)


# Vector store bytes
def compare_vmem():
    n = min(len(DUT_VMEM), len(SPK_VMEM))
    for i in range(n):
        if DUT_VMEM[i] != SPK_VMEM[i]:
            (da, dv), (sa, sv) = DUT_VMEM[i], SPK_VMEM[i]
            return False, (
                f"vector store byte {i}\n  DUT   b{da:02x}={dv:02x}\n"
                f"  Spike b{sa:02x}={sv:02x}"
            )
    if len(DUT_VMEM) != len(SPK_VMEM):
        return (
            False,
            f"vector store byte count DUT {len(DUT_VMEM)} Spike {len(SPK_VMEM)}",
        )
    return True, n


def rebased(d, s):
    if SPAN is None or not d[1] or d[:2] != s[:2] or d[3:] != s[3:]:
        return False
    return s[2] == (d[2] + BASE) & MASK32 and SPAN[0] <= s[2] <= SPAN[1]


def first_mismatch(dut, spike):
    for i in range(min(len(dut), len(spike))):
        if dut[i] != spike[i] and not rebased(dut[i], spike[i]):
            return i
    return None


def compare(dut, spike):
    n = min(len(dut), len(spike))
    i = first_mismatch(dut, spike)
    if i is not None:
        why = ""
        if dut[i][4] != spike[i][4] and dut[i][:4] == spike[i][:4]:
            names = ("vl", "vtype", "vstart")
            bad = [
                n for n, a, b in zip(names, dut[i][4], spike[i][4]) if a != b
            ]
            why = f" ({', '.join(bad)})"
        return (
            False,
            f"instr {i}{why}\n  DUT   {fmt(dut[i])}\n  Spike {fmt(spike[i])}"
            + locate(i),
        )
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
            pool = (
                ["r", "i", "sh", "lui", "mul", "div", "sw"]
                + (["lw"] if written else [])
                + mem_st
                + mem_ld
            )
        else:
            pool = [
                "r",
                "i",
                "sh",
                "lui",
                "mul",
                "div",
                "sw",
                "branch",
                "jal",
            ] + mem_st
        kind = rng.choice(pool)

        match kind:
            case "r":
                body.append(f"{rng.choice(R_OPS)} x{rd()}, x{rs()}, x{rs()}")
            case "i":
                body.append(
                    f"{rng.choice(I_OPS)} x{rd()}, x{rs()}, {rng.randint(-2048, 2047)}"
                )
            case "sh":
                body.append(
                    f"{rng.choice(SH_OPS)} x{rd()}, x{rs()}, {rng.randint(0, 31)}"
                )
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
                body.append(
                    f"sb x{rs()}, {word * 4 + rng.randint(0, 3)}(x{BASE_REG})"
                )
            case "sth":
                word = rng.choice(sorted(written))
                body.append(
                    f"sh x{rs()}, {word * 4 + rng.choice([0, 2])}(x{BASE_REG})"
                )
            case "ldb":
                word = rng.choice(sorted(written))
                body.append(
                    f"{rng.choice(['lb', 'lbu'])} x{rd()}, {word * 4 + rng.randint(0, 3)}(x{BASE_REG})"
                )
            case "ldh":
                word = rng.choice(sorted(written))
                body.append(
                    f"{rng.choice(['lh', 'lhu'])} x{rd()}, {word * 4 + rng.choice([0, 2])}(x{BASE_REG})"
                )
            case "branch":
                tgt = rng.choice([f"L{k}" for k in range(i + 1, n)] + ["Ldone"])
                body.append(f"{rng.choice(BR_OPS)} x{rs()}, x{rs()}, {tgt}")
            case "jal":
                tgt = rng.choice([f"L{k}" for k in range(i + 1, n)] + ["Ldone"])
                body.append(f"jal x0, {tgt}")

    # Base 0x80008000 clears the code in Spike
    lines = [
        "        .section .text",
        "        .globl _start",
        "_start:",
        f"        lui x{BASE_REG}, 0x80008",
    ]
    for i, insn in enumerate(body):
        lines.append(f"L{i}: {insn}")
    lines.append("Ldone: beq x0, x0, Ldone")  # park sentinel
    return "\n".join(lines) + "\n", mode


# Vector memory program
VSIZE = {8: 1, 16: 2, 32: 4}
VBASE, VSTRIDE = 9, 11  # base and stride registers


def whole_insn(store, width, rd, base):
    f3 = {8: 0, 16: 5, 32: 6}[width]
    op = 0x27 if store else 0x07
    return (1 << 25) | (8 << 20) | (base << 15) | (f3 << 12) | (rd << 7) | op


def gen_vec(seed):
    rng = random.Random(seed)
    sew, vl = 8, 0
    body = []

    def vset():
        nonlocal sew, vl
        sew = rng.choice([8, 16, 32])
        avl = rng.choice([0, 1, 2, 3, 5, 8, 8])
        vl = min(avl, 128 // sew)
        body.append(f"li x10, {avl}")
        body.append(f"vsetvli x5, x10, e{sew}, m1, tu, mu")
        if vl:  # element 0 always live
            body.append(
                f"addi x{VBASE}, x{BASE_REG}, {rng.randrange(0, 241, VSIZE[sew])}"
            )
            body.append(f"vle{sew}.v v0, (x{VBASE})")
            body.append("vor.vi v0, v0, 1")

    vset()
    for _ in range(rng.randint(16, 36)):
        size = VSIZE[sew]
        kind = rng.choice(
            [
                "vle",
                "vse",
                "vle",
                "vse",
                "vlse",
                "vsse",
                "whole",
                "sw",
                "lw",
                "sb",
                "lb",
                "vset",
                "fence",
                "wide",
                "widew",
                "narrow",
                "ext",
                "red",
                "wred",
                "movsx",
                "movxs",
                "cmp",
                "cmpgt",
                "mlogic",
                "mset",
                "miota",
                "mpop",
                "vlm",
            ]
        )
        mask = ", v0.t" if rng.random() < 0.3 else ""
        match kind:
            case "vle" | "vse":
                vd = rng.randint(1, 31) if kind == "vle" else rng.randint(0, 31)
                body.append(
                    f"addi x{VBASE}, x{BASE_REG}, {rng.randrange(0, 241, size)}"
                )
                body.append(f"{kind}{sew}.v v{vd}, (x{VBASE}){mask}")
            case "vlse" | "vsse":
                vd = (
                    rng.randint(1, 31) if kind == "vlse" else rng.randint(0, 31)
                )
                body.append(
                    f"addi x{VBASE}, x{BASE_REG}, {rng.randrange(96, 161, size)}"
                )
                body.append(f"li x{VSTRIDE}, {rng.randint(-3, 3) * size}")
                body.append(
                    f"{kind}{sew}.v v{vd}, (x{VBASE}), x{VSTRIDE}{mask}"
                )
            case "whole":
                store = rng.random() < 0.5
                width = 8 if store else rng.choice([8, 16, 32])
                body.append(
                    f"addi x{VBASE}, x{BASE_REG}, {rng.randrange(0, 241, 4)}"
                )
                body.append(
                    f".word 0x{whole_insn(store, width, rng.randint(1, 31), VBASE):08x}"
                )
            case "sw":
                body.append(
                    f"sw x{rng.randint(1, 31)}, {rng.randrange(0, 253, 4)}(x{BASE_REG})"
                )
            case "lw":
                body.append(
                    f"lw x{rng.choice([12, 13, 14])}, {rng.randrange(0, 253, 4)}(x{BASE_REG})"
                )
            case "sb":
                body.append(
                    f"sb x{rng.randint(1, 31)}, {rng.randint(0, 255)}(x{BASE_REG})"
                )
            case "lb":
                body.append(
                    f"lbu x{rng.choice([12, 13, 14])}, {rng.randint(0, 255)}(x{BASE_REG})"
                )
            case "wide":
                if sew < 32:
                    op = rng.choice(["vwaddu", "vwadd", "vwsubu", "vwsub"])
                    form = rng.choice([".vv", ".vx"])
                    src = (
                        f"v{rng.randint(1, 15)}"
                        if form == ".vv"
                        else f"x{rng.choice([12, 13, 14])}"
                    )
                    body.append(
                        f"{op}{form} v{rng.randrange(16, 31, 2)}, "
                        f"v{rng.randint(1, 15)}, {src}{mask}"
                    )
            case "widew":
                if sew < 32:
                    op = rng.choice(["vwaddu", "vwadd", "vwsubu", "vwsub"])
                    form = rng.choice([".wv", ".wx"])
                    src = (
                        f"v{rng.randint(1, 15)}"
                        if form == ".wv"
                        else f"x{rng.choice([12, 13, 14])}"
                    )
                    body.append(
                        f"{op}{form} v{rng.randrange(16, 31, 2)}, "
                        f"v{rng.randrange(16, 31, 2)}, {src}{mask}"
                    )
            case "narrow":
                if sew < 32:
                    op = rng.choice(["vnsrl", "vnsra"])
                    form = rng.choice([".wv", ".wx", ".wi"])
                    src = {
                        ".wv": f"v{rng.randint(1, 15)}",
                        ".wx": f"x{rng.choice([12, 13, 14])}",
                        ".wi": f"{rng.randint(0, 31)}",
                    }[form]
                    body.append(
                        f"{op}{form} v{rng.randint(1, 15)}, "
                        f"v{rng.randrange(16, 31, 2)}, {src}{mask}"
                    )
            case "ext":
                if sew > 8:
                    ops = ["vzext.vf2", "vsext.vf2"]
                    if sew == 32:
                        ops += ["vzext.vf4", "vsext.vf4"]
                    body.append(
                        f"{rng.choice(ops)} v{rng.randint(16, 31)}, "
                        f"v{rng.randint(1, 15)}{mask}"
                    )
            case "red":
                op = rng.choice(
                    [
                        "vredsum",
                        "vredand",
                        "vredor",
                        "vredxor",
                        "vredminu",
                        "vredmin",
                        "vredmaxu",
                        "vredmax",
                    ]
                )
                body.append(
                    f"{op}.vs v{rng.randint(16, 31)}, v{rng.randint(1, 15)}, "
                    f"v{rng.randint(1, 15)}{mask}"
                )
            case "wred":
                if sew < 32:
                    op = rng.choice(["vwredsum", "vwredsumu"])
                    body.append(
                        f"{op}.vs v{rng.randint(16, 31)}, v{rng.randint(1, 15)}, "
                        f"v{rng.randint(1, 15)}{mask}"
                    )
            case "cmp":
                op = rng.choice(
                    ["vmseq", "vmsne", "vmsltu", "vmslt", "vmsleu", "vmsle"]
                )
                form = rng.choice([".vv", ".vx", ".vi"])
                src = {
                    ".vv": f"v{rng.randint(1, 15)}",
                    ".vx": f"x{rng.choice([12, 13, 14])}",
                    ".vi": f"{rng.randint(-15, 15)}",
                }[form]
                body.append(
                    f"{op}{form} v{rng.randint(16, 31)}, "
                    f"v{rng.randint(1, 15)}, {src}{mask}"
                )
            case "cmpgt":
                op = rng.choice(["vmsgtu", "vmsgt"])
                form = rng.choice([".vx", ".vi"])
                src = (
                    f"x{rng.choice([12, 13, 14])}"
                    if form == ".vx"
                    else f"{rng.randint(-15, 15)}"
                )
                body.append(
                    f"{op}{form} v{rng.randint(16, 31)}, "
                    f"v{rng.randint(1, 15)}, {src}{mask}"
                )
            case "mlogic":
                op = rng.choice(
                    [
                        "vmand",
                        "vmnand",
                        "vmandn",
                        "vmor",
                        "vmnor",
                        "vmorn",
                        "vmxor",
                        "vmxnor",
                    ]
                )
                body.append(
                    f"{op}.mm v{rng.randint(16, 31)}, v{rng.randint(1, 15)}, "
                    f"v{rng.randint(1, 15)}"
                )
            case "mset":
                op = rng.choice(["vmsbf", "vmsif", "vmsof"])
                body.append(
                    f"{op}.m v{rng.randint(16, 31)}, v{rng.randint(1, 15)}{mask}"
                )
            case "miota":
                if rng.random() < 0.5:
                    body.append(
                        f"viota.m v{rng.randint(16, 31)}, v{rng.randint(1, 15)}{mask}"
                    )
                else:
                    body.append(f"vid.v v{rng.randint(16, 31)}{mask}")
            case "mpop":
                op = rng.choice(["vcpop", "vfirst"])
                body.append(
                    f"{op}.m x{rng.choice([12, 13, 14])}, v{rng.randint(1, 15)}{mask}"
                )
            case "vlm":
                body.append(
                    f"addi x{VBASE}, x{BASE_REG}, {rng.randrange(0, 241, 4)}"
                )
                if rng.random() < 0.5:
                    body.append(f"vlm.v v{rng.randint(16, 31)}, (x{VBASE})")
                else:
                    body.append(f"vsm.v v{rng.randint(1, 15)}, (x{VBASE})")
            case "movsx":
                body.append(
                    f"vmv.s.x v{rng.randint(16, 31)}, x{rng.choice([12, 13, 14])}"
                )
            case "movxs":
                body.append(
                    f"vmv.x.s x{rng.choice([12, 13, 14])}, v{rng.randint(1, 15)}"
                )
            case "wide":
                if sew < 32:
                    op = rng.choice(["vwaddu", "vwadd", "vwsubu", "vwsub"])
                    form = rng.choice([".vv", ".vx"])
                    src = (
                        f"v{rng.randint(1, 15)}"
                        if form == ".vv"
                        else f"x{rng.choice([12, 13, 14])}"
                    )
                    body.append(
                        f"{op}{form} v{rng.randrange(16, 31, 2)}, "
                        f"v{rng.randint(1, 15)}, {src}{mask}"
                    )
            case "widew":
                if sew < 32:
                    op = rng.choice(["vwaddu", "vwadd", "vwsubu", "vwsub"])
                    form = rng.choice([".wv", ".wx"])
                    src = (
                        f"v{rng.randint(1, 15)}"
                        if form == ".wv"
                        else f"x{rng.choice([12, 13, 14])}"
                    )
                    body.append(
                        f"{op}{form} v{rng.randrange(16, 31, 2)}, "
                        f"v{rng.randrange(16, 31, 2)}, {src}{mask}"
                    )
            case "narrow":
                if sew < 32:
                    op = rng.choice(["vnsrl", "vnsra"])
                    form = rng.choice([".wv", ".wx", ".wi"])
                    src = {
                        ".wv": f"v{rng.randint(1, 15)}",
                        ".wx": f"x{rng.choice([12, 13, 14])}",
                        ".wi": f"{rng.randint(0, 31)}",
                    }[form]
                    body.append(
                        f"{op}{form} v{rng.randint(1, 15)}, "
                        f"v{rng.randrange(16, 31, 2)}, {src}{mask}"
                    )
            case "ext":
                if sew > 8:
                    ops = ["vzext.vf2", "vsext.vf2"]
                    if sew == 32:
                        ops += ["vzext.vf4", "vsext.vf4"]
                    body.append(
                        f"{rng.choice(ops)} v{rng.randint(16, 31)}, "
                        f"v{rng.randint(1, 15)}{mask}"
                    )
            case "red":
                op = rng.choice(
                    [
                        "vredsum",
                        "vredand",
                        "vredor",
                        "vredxor",
                        "vredminu",
                        "vredmin",
                        "vredmaxu",
                        "vredmax",
                    ]
                )
                body.append(
                    f"{op}.vs v{rng.randint(16, 31)}, v{rng.randint(1, 15)}, "
                    f"v{rng.randint(1, 15)}{mask}"
                )
            case "wred":
                if sew < 32:
                    op = rng.choice(["vwredsum", "vwredsumu"])
                    body.append(
                        f"{op}.vs v{rng.randint(16, 31)}, v{rng.randint(1, 15)}, "
                        f"v{rng.randint(1, 15)}{mask}"
                    )
            case "movsx":
                body.append(
                    f"vmv.s.x v{rng.randint(16, 31)}, x{rng.choice([12, 13, 14])}"
                )
            case "movxs":
                body.append(
                    f"vmv.x.s x{rng.choice([12, 13, 14])}, v{rng.randint(1, 15)}"
                )
            case "vset":
                vset()
            case "fence":
                body.append("fence")

    lines = [
        "        .section .text",
        "        .globl _start",
        "_start:",
        "        li x5, 0x200",
        "        csrs mstatus, x5",
        f"        lui x{BASE_REG}, 0x80008",
        "        li x5, 64",
        f"        mv x6, x{BASE_REG}",
        f"        li x7, {rng.randint(1, 0x7FFFFFFF)}",
        "Lfill:  sw x7, 0(x6)",
        "        slli x8, x7, 13",
        "        xor x7, x7, x8",
        "        srli x8, x7, 17",
        "        xor x7, x7, x8",
        "        addi x6, x6, 4",
        "        addi x5, x5, -1",
        "        bnez x5, Lfill",
    ]
    lines += [f"        {insn}" for insn in body]
    lines.append("Ldone: beq x0, x0, Ldone")  # park sentinel
    return "\n".join(lines) + "\n", "vector"


# Handler around a program
def with_irq(asm):
    head, body = asm.split("_start:\n", 1)
    setup = [
        "_start:",
        "        jal x31, Lirqset",
        "        j Lirq",
        "Lirqset: csrw mtvec, x31",
        f"        li x31, {MIP_MEIP | MIP_MTIP}",
        "        csrs mie, x31",
        "        csrsi mstatus, 8",
        "        li x31, 0",
    ]
    handler = [
        "Lirq:   csrrw x31, mscratch, x31",
        "        csrr x31, mcause",
        "        csrr x31, mepc",
        "        csrrw x31, mscratch, x0",
        "        mret",
    ]
    return head + "\n".join(setup) + "\n" + body + "\n".join(handler) + "\n"


# Build run compare
def run_one(src, stall_seed=None, irq_seed=None):
    dut_hex = os.path.join(BUILD, "prog.hex")
    spike_elf = os.path.join(BUILD, "prog_spike.elf")
    build_images(src, dut_hex, spike_elf)
    dut = run_dut(dut_hex, stall_seed=stall_seed, irq_seed=irq_seed)
    if HUNG:
        return False, HUNG[0]
    if IRQ_LOST:
        return False, IRQ_LOST[0]
    spike = run_spike(spike_elf, len(dut))
    if SPK_IRQ_MISS:
        k = int(SPK_IRQ_MISS[0].split()[2])
        i = first_mismatch(dut, spike)
        if i is None or i >= k:
            return False, (
                f"interrupt at instr {k} taken by the core, not by Spike"
                + (
                    f"\n  DUT   {fmt(dut[k])}" + locate(k)
                    if k < len(dut)
                    else ""
                )
            )
    ok, why = compare(dut, spike)
    if ok and FAULTS:
        return False, FAULTS[0]
    if not ok or not VECTOR:
        return ok, why
    vok, vwhy = compare_vec()
    if not vok:
        return False, vwhy
    mok, mwhy = compare_vmem()
    if not mok:
        return False, mwhy
    return True, why


def gen_root(src):
    d = os.path.dirname(os.path.abspath(src))
    while d != os.path.dirname(d):
        if os.path.exists(
            os.path.join(d, "macros", "general", "test_macros.h")
        ):
            return d
        d = os.path.dirname(d)
    sys.exit(f"no generator tree above {src}")


# Generated test images
def gen_build(src, out):
    root = gen_root(src)
    flags = [
        f"-march={GEN_MARCH}",
        "-mabi=ilp32",
        "-static",
        "-mcmodel=medany",
        "-nostdlib",
        "-nostartfiles",
        "-DCOSIM_TEST_CASE",
        "-Wl,--no-warn-rwx-segments",
        "-mno-relax",
        "-Wl,--no-relax",
        f"-I{ENV_DIR}",
        f"-I{os.path.join(root, 'env', 'riscv-test-env')}",
        f"-I{os.path.join(root, 'macros', 'general')}",
    ]
    os.makedirs(out, exist_ok=True)
    sizes = {}
    for side in ("dut", "spike"):
        elf = os.path.join(out, f"{side}.elf")
        sh(
            [
                RVGCC,
                *flags,
                "-T",
                os.path.join(ENV_DIR, f"link_{side}.ld"),
                "-o",
                elf,
                os.path.abspath(src),
            ]
        )
        table = subprocess.run(
            ["riscv64-elf-size", "-A", elf],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()[2:]
        sizes[side] = [tuple(l.split()[:2]) for l in table if l.strip()]
    if sizes["dut"] != sizes["spike"]:
        sys.exit(f"image layouts differ for {src}")
    sh(
        [
            "riscv64-elf-objcopy",
            "-O",
            "verilog",
            "--verilog-data-width=4",
            os.path.join(out, "dut.elf"),
            os.path.join(out, "dut.hex"),
        ]
    )


# Trap probe
def gen_probe_build(src, out):
    root = gen_root(src)
    elf = os.path.join(out, "probe.elf")
    sh(
        [
            RVGCC,
            f"-march={GEN_MARCH}",
            "-mabi=ilp32",
            "-static",
            "-mcmodel=medany",
            "-nostdlib",
            "-nostartfiles",
            "-DCOSIM_TEST_CASE",
            "-DTRAP_SKIP",
            "-Wl,--no-warn-rwx-segments",
            "-mno-relax",
            "-Wl,--no-relax",
            f"-I{ENV_DIR}",
            f"-I{os.path.join(root, 'env', 'riscv-test-env')}",
            f"-I{os.path.join(root, 'macros', 'general')}",
            "-T",
            os.path.join(ENV_DIR, "link_dut.ld"),
            "-o",
            elf,
            os.path.abspath(src),
        ]
    )
    sh(
        [
            "riscv64-elf-objcopy",
            "-O",
            "verilog",
            "--verilog-data-width=4",
            elf,
            os.path.join(out, "probe.hex"),
        ]
    )


def gen_probe(out, cycles=None):
    spike, _ = gen_load(os.path.join(out, "spike.json.gz"))
    n = cycles or 40 * len(spike) + 20000
    run_dut(os.path.join(os.path.abspath(out), "probe.hex"), n=n, gen=True)
    words = {}
    for insn, k in [(t[2], 0) for t in TRACE] + [(t[3], 1) for t in DUT_TRAP]:
        if insn & 0x7F in (0x57, 0x07, 0x27):
            words.setdefault(f"{insn:08x}", [0, 0])[k] += 1
    return ("HUNG" if HUNG else "DONE"), json.dumps(
        words, separators=(",", ":")
    )


def gen_parks(spike_elf):
    out = subprocess.run(
        ["riscv64-elf-nm", spike_elf],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    parks = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) == 3 and f[2].startswith("park_"):
            parks[f[2][5:]] = (int(f[0], 16) - BASE) & MASK32
    return parks


# Trace cache
def gen_save(path, name, trace, parks, end):
    data = {
        "test": name,
        "span": list(SPAN),
        "parks": parks,
        "end": end,
        "trace": [
            [
                pc,
                rd,
                val,
                [s[0], [list(b) for b in s[1]]] if s else None,
                list(v) if v else None,
            ]
            for pc, rd, val, s, v in trace
        ],
        "vwr": [list(e) for e in SPK_VWR],
        "vwr_at": SPK_VWR_AT,
        "vmem": [list(e) for e in SPK_VMEM],
        "vmem_at": SPK_VMEM_AT,
    }
    with gzip.open(path, "wt") as f:
        json.dump(data, f, separators=(",", ":"))


def gen_load(path):
    global SPAN
    with gzip.open(path, "rt") as f:
        data = json.load(f)
    SPAN = tuple(data["span"])
    SPK_VWR[:] = [tuple(e) for e in data["vwr"]]
    SPK_VWR_AT[:] = data["vwr_at"]
    SPK_VMEM[:] = [tuple(e) for e in data["vmem"]]
    SPK_VMEM_AT[:] = data["vmem_at"]
    trace = [
        (
            pc,
            rd,
            val,
            (s[0], tuple(tuple(b) for b in s[1])) if s else None,
            tuple(v) if v else None,
        )
        for pc, rd, val, s, v in data["trace"]
    ]
    return trace, data


# Spike side
def gen_spike(src, out):
    name = os.path.splitext(os.path.basename(src))[0]
    gen_build(src, out)
    elf = os.path.join(out, "spike.elf")
    trace = run_spike(elf, GEN_CAP, isa=GEN_MARCH, park=True)
    parks = gen_parks(elf)
    end = next(
        (k for k, pc in parks.items() if trace and trace[-1][0] == pc), "cap"
    )
    gen_save(os.path.join(out, "spike.json.gz"), name, trace, parks, end)
    return name, len(trace), end


def first_elem(dut, spk, key):
    for j in range(min(len(dut), len(spk))):
        if key(dut[j]) != key(spk[j]):
            return j
    return None


# Compare one test
def gen_verdict(dut, spike, data):
    marks = []
    i = first_mismatch(dut, spike)
    if i is not None:
        insn = f" insn={TRACE[i][2]:08x}" if i < len(TRACE) else ""
        marks.append(
            (i, f"instr {i}{insn} DUT {fmt(dut[i])} | Spike {fmt(spike[i])}")
        )
    j = first_elem(DUT_VWR, SPK_VWR, lambda e: e[1:])
    if j is not None:
        (_, dr, dv), (_, sr, sv) = DUT_VWR[j], SPK_VWR[j]
        marks.append(
            (
                SPK_VWR_AT[j],
                (
                    f"vector write {j} at instr {SPK_VWR_AT[j]} "
                    f"DUT v{dr}={dv:032x} | Spike v{sr}={sv:032x}"
                ),
            )
        )
    j = first_elem(DUT_VMEM, SPK_VMEM, lambda e: e)
    if j is not None:
        (da, dv), (sa, sv) = DUT_VMEM[j], SPK_VMEM[j]
        marks.append(
            (
                SPK_VMEM_AT[j],
                (
                    f"vector store byte {j} at instr {SPK_VMEM_AT[j]} "
                    f"DUT b{da:x}={dv:02x} | Spike b{sa:x}={sv:02x}"
                ),
            )
        )
    first = min(marks, key=lambda m: m[0]) if marks else None
    if DUT_TRAP:
        k, _, pc, insn = DUT_TRAP[0]
        if first is None or first[0] >= k:
            both = (
                " spike also trapped"
                if i is None and data["end"] == "trap"
                else ""
            )
            return "TRAP", f"pc={pc:08x} insn={insn:08x}{both}"
    if first is not None:
        return "DIVERGE", first[1]
    if HUNG:
        return "HUNG", f"{HUNG[0][5:]} at instr {len(dut)} of {len(spike)}"
    for what, a, b in (
        ("length", len(dut), len(spike)),
        ("vector write count", len(DUT_VWR), len(SPK_VWR)),
        ("vector store byte count", len(DUT_VMEM), len(SPK_VMEM)),
    ):
        if a != b:
            return "DIVERGE", f"{what} DUT {a} Spike {b}"
    if FAULTS:
        return "DIVERGE", FAULTS[0]
    if data["end"] != "pass":
        return "DIVERGE", f"Spike ended at {data['end']}"
    return (
        "PASS",
        f"{len(dut)} instrs {len(DUT_VWR)} vreg writes {len(DUT_VMEM)} vstore bytes",
    )


# DUT side
def gen_dut(out, cycles=None):
    spike, data = gen_load(os.path.join(out, "spike.json.gz"))
    n = cycles or 40 * len(spike) + 20000
    dut = run_dut(os.path.join(os.path.abspath(out), "dut.hex"), n=n, gen=True)
    return gen_verdict(dut, spike, data)


# Sweep entry
def gen_main(mode, args):
    global VECTOR, DEPTH
    VECTOR = True
    DEPTH = GEN_DEPTH
    build_sim = "--no-compile" not in args
    args = [a for a in args if a != "--no-compile"]
    cycles = None
    if "--cycles" in args:
        k = args.index("--cycles")
        cycles = int(args[k + 1])
        del args[k : k + 2]
    if mode == "--compile":
        compile_monitor()
        return 0
    if mode == "--gen-probe-build":
        gen_probe_build(*args)
        print("BUILT")
        return 0
    if mode == "--gen-probe":
        if build_sim:
            compile_monitor()
        verdict, detail = gen_probe(args[0], cycles)
        print(f"{verdict} {detail}")
        return 0
    if mode in ("--gen", "--gen-spike"):
        if len(args) not in (1, 2):
            sys.exit(f"usage: python3 tests/cosim.py {mode} <test.S> [outdir]")
        src = args[0]
        out = (
            args[1]
            if len(args) == 2
            else os.path.join(
                GEN_OUT, os.path.splitext(os.path.basename(src))[0]
            )
        )
        name, count, end = gen_spike(src, out)
        if mode == "--gen-spike":
            print(f"SPIKE {name} {count} instrs end={end}")
            return 0
    else:
        if len(args) != 1:
            sys.exit(
                "usage: python3 tests/cosim.py --gen-dut <outdir> [--no-compile] [--cycles N]"
            )
        out = args[0]
    if build_sim:
        compile_monitor()
    verdict, detail = gen_dut(out, cycles)
    print(f"{verdict} {detail}")
    return 0 if verdict == "PASS" else 1


def main():
    global VECTOR, FP, STALL, IRQ
    if len(sys.argv) >= 2 and sys.argv[1] in (
        "--gen",
        "--gen-spike",
        "--gen-dut",
        "--compile",
        "--gen-probe-build",
        "--gen-probe",
    ):
        sys.exit(gen_main(sys.argv[1], sys.argv[2:]))
    if "--vec" in sys.argv[1:]:
        VECTOR = True
        sys.argv.remove("--vec")
    if "--fp" in sys.argv[1:]:
        FP = True
        sys.argv.remove("--fp")
    if "--stall" in sys.argv[1:]:
        STALL = True
        sys.argv.remove("--stall")
    if "--irq" in sys.argv[1:]:
        IRQ = True
        sys.argv.remove("--irq")

    if len(sys.argv) >= 2 and sys.argv[1] == "--rand":  # random regression
        count = int(sys.argv[2]) if len(sys.argv) >= 3 else 200
        seed0 = int(sys.argv[3]) if len(sys.argv) >= 4 else 0
        compile_monitor()
        total = 0
        irqs = 0
        for seed in range(seed0, seed0 + count):
            asm, mode = gen_vec(seed) if VECTOR else gen(seed)
            if IRQ:
                asm = with_irq(asm)
            src = os.path.join(BUILD, "rand.s")
            with open(src, "w") as f:
                f.write(asm)
            ok, detail = run_one(
                src, seed if STALL else None, seed if IRQ else None
            )
            if not ok:
                fail = os.path.join(
                    BUILD, f"fail_{seed}.s"
                )  # reproducible seed
                with open(fail, "w") as f:
                    f.write(asm)
                flags = (
                    ("--vec " if VECTOR else "")
                    + ("--stall " if STALL else "")
                    + ("--irq " if IRQ else "")
                )
                print(
                    f"FAIL seed={seed} mode={mode}\n{detail}\nprogram saved to {fail}"
                    f"\nrerun: python3 tests/cosim.py {flags}--rand 1 {seed}"
                )
                sys.exit(1)
            total += detail
            irqs += len(DUT_IRQ)
        waits = (
            f", {STALLS[0]} fetch and {STALLS[1]} data wait cycles"
            if STALL
            else ""
        )
        if IRQ:
            waits += f", {irqs} interrupts taken"
        print(
            f"RANDOM PASS: {count} programs from seed {seed0}, "
            f"{total} instructions matched Spike{waits}"
        )
        return

    if IRQ:
        sys.exit("--irq needs --rand, directed programs carry no handler")
    want_trace = "--trace" in sys.argv
    if want_trace:
        sys.argv.remove("--trace")
    if len(sys.argv) != 2:
        sys.exit(
            "usage: python3 tests/cosim.py [--vec] [--fp] [--stall] [--trace] <prog>"
            " | --rand [count] [seed0]"
        )
    prog = sys.argv[1]  # single program, assembly or C
    compile_monitor()
    src_c = os.path.join("tests", f"{prog}.c")
    src = src_c if os.path.exists(src_c) else os.path.join("tests", f"{prog}.s")
    dut_hex = os.path.join("tests", f"{prog}.hex")
    spike_elf = os.path.join(BUILD, f"{prog}_spike.elf")
    build_images(src, dut_hex, spike_elf)
    dut = run_dut(dut_hex, vcd=True, stall_seed=1 if STALL else None)
    spike = run_spike(spike_elf, len(dut))
    if want_trace:
        log = os.path.join(BUILD, f"{prog}.trace")
        write_trace(log, dut)
        print(f"trace written to {os.path.relpath(log, ROOT)}")
    ok, detail = compare(dut, spike)
    if not ok:
        print(f"DIVERGENCE {detail}")
        sys.exit(1)
    if FAULTS:
        print(f"DIVERGENCE {FAULTS[0]}")
        sys.exit(1)
    if HUNG:
        print(f"DIVERGENCE {HUNG[0]}")
        sys.exit(1)
    extra = ""
    if VECTOR:
        vok, vdetail = compare_vec()
        if not vok:
            print(f"DIVERGENCE {vdetail}")
            sys.exit(1)
        mok, mdetail = compare_vmem()
        if not mok:
            print(f"DIVERGENCE {mdetail}")
            sys.exit(1)
        extra = (
            f", {vdetail} vector register writes, {mdetail} vector store bytes"
        )
    if FP:
        fok, fdetail = compare_fp()
        if not fok:
            print(f"DIVERGENCE {fdetail}")
            sys.exit(1)
        extra += (
            f", {fdetail} float register writes, final fcsr {FCSR['dut']:02x}"
        )
    print(f"LOCKSTEP PASS: {detail} instructions match Spike{extra} ({prog})")


if __name__ == "__main__":
    main()
