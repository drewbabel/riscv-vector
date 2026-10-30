# Running Mamba-3

## Prerequisites

- Put the `bin` directory of the xpack riscv-none-elf-gcc 14.2 release
  (https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases) on `PATH`, because
  the Homebrew riscv-gnu-toolchain build fails at link time.
- Install Verilator 5, for example from the OSS CAD Suite
  (https://github.com/YosysHQ/oss-cad-suite-build/releases), and a C++ compiler with make
  (on macOS, `xcode-select --install`).
- Install Python 3 with numpy.

## Run

    git clone -b mamba3-float https://github.com/drewbabel/riscv-vector.git
    cd riscv-vector
    python3 sw/mamba3/fetch.py mamba3-siso-187m 0 fp32
    make sw-run PROG=mamba3 | tee build/mamba3.log
    python3 sw/mamba3/check.py build/mamba3.log

`fetch.py <model> <layer> <fp32|bf16>` downloads the model from Hugging Face and prints
whether the layer fits in the simulated memory.

`make sw-run PROG=mamba3` runs one token through the layer with scalar instructions and then
with RVV instructions, printing each step's cycle count as the step finishes. Both runs take
hours. Adding `SWDEFS=-DSCALAR=0` to the same line runs the vector pass alone.

`check.py` finishes the model on the host from each run's layer output and prints the next
token from the float64 reference and from each run.
