# Software for the core

This directory holds C programs that run on the core in `rtl/`, the startup code and board support they link against, and an example program. Programs are compiled for RV32IMF with the RVV vector extension and run in a Verilator model of the Nexys Video board.

## What the core runs today

- RV32IM: base integer instructions with multiply and divide.
- Zicsr: CSR access, used for the cycle counter and the mstatus enable bits.
- F: scalar single-precision float, including float loads and stores.
- Vector unit: RVV 1.0, Zve32f, VLEN 128 bits, so one vector register holds four int32 or four float elements. Integer, fixed-point, and single-precision float instructions: arithmetic, fused multiply-add, divide and square root, conversions, moves, slides, reductions, classify, and the reciprocal estimates. Widening float arithmetic traps, since Zve32f has no 64-bit float elements.
- Not yet available: exp or any other transcendental instruction. `-lm` provides `expf`, `sinf`, and the rest in software.

## Toolchain

1. A bare-metal RISC-V GCC of version 14 or newer, which has the RVV intrinsics, built with newlib. The project uses riscv64-unknown-elf-gcc from the Homebrew riscv-gnu-toolchain formula.
2. Verilator 5 with `--timing` support, and Python 3. The OSS CAD Suite (https://github.com/YosysHQ/oss-cad-suite-build/releases) includes Verilator. The project CI uses the 2026-07-24 release.

The sw targets use the prefix `SWPREFIX`, default `riscv64-unknown-elf-`. Pass `SWPREFIX=<prefix>` to use another toolchain. The hex targets keep their own prefix, `RVPREFIX`, default `riscv64-elf-`.

## Build and run

A program is a directory `sw/<name>/` holding one or more `.c` files. The files in `sw/common/` are linked into every program.

    make sw PROG=hello
    make sw-run PROG=hello

- `make sw` writes `build/hello.elf`, `build/hello.bin`, and `build/hello.hex`.
- `make sw-run` builds the board model on the first run (`build/board_sim`), then runs the program in it. The model is rebuilt only when the RTL or the testbench changes.
- The run ends when the program prints `END`. A run that reaches the cycle limit stops with `TIMEOUT`.
- The cycle limit is `SWLIMIT`, in core cycles, default 4294967295, the 32-bit wrap of `mcycle`. Override it on the command line, for example `make sw-run PROG=hello SWLIMIT=50000000`.

The example prints this shape of output, with numbers that vary by program:

    hello from the riscv-vector core
    MATCH
    scalar cycles <n>
    vector cycles <n>
    END

## Reading cycles

    #include "board.h"

    uint32_t t0 = read_cycles();
    /* work */
    uint32_t cycles = read_cycles() - t0;

`read_cycles()` returns the low 32 bits of the `mcycle` counter, which counts core clock cycles. The core runs at 50 MHz on the board, so the counter wraps after about 86 seconds.

## Printing

`board.h` declares `board_puts(const char *)` and `board_putu(uint32_t)`. Both send bytes to the UART and wait until the transmitter is ready. In simulation the bytes appear on the terminal.

`printf` also works. Newlib's `_write` in `sw/common/sys.c` sends each byte through the same UART path, and `sw/hello/hello.c` uses it.

## Float and vector setup and compiler flags

`sw/common/crt.S` sets the FS and VS fields of mstatus before `main`, which turns on the float and vector state.

The build links `-lm`, so `<math.h>` functions work.

The build passes `-fno-tree-vectorize`, so the compiler does not turn scalar loops into vector code. Write vector code with the RVV intrinsics from `<riscv_vector.h>`, as `sw/hello/hello.c` does.

## Memory

- Code and data share one 16 MB RAM that starts at address 0. The program image is loaded at address 0 before the core starts, so a program can be up to 16 MB.
- The stack starts at the top of the 16 MB and grows down. The heap starts after the bss section and grows up. Keep the two apart.
- The core has an 8 KB instruction cache and an 8 KB data cache.

## Simulation time

The Verilator model runs about 100,000 core cycles per second of wall time on the lab machine atlas2, measured as the slope between two runs of 8 million cycles apart. Twenty million core cycles take about 3 to 4 minutes. The rate depends on the machine.

## Files

- `sw/common/crt.S`: startup code. Turns on float and vector state, sets the stack, zeroes bss, runs libc init, calls `main`.
- `sw/common/sys.c`: UART output, heap growth, newlib stubs.
- `sw/common/board.ld`: linker script, 16 MB RAM at address 0.
- `sw/common/board.h`: UART output, cycle counter.
- `sw/common/bin2hex.py`: converts the binary image to one 32-bit word per line.
- `sw/hello/hello.c`: example, scalar and RVV int32 addition.
- `tb/board_run_tb.sv`: testbench that loads the hex image and prints UART output.
- `tb/mig_7series_0.sv`: behavioral DDR3 memory controller and clock models for `rtl/boards/nexys_video/board_top.sv`.
