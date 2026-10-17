#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
PKGS="rtl/arch_pkg.sv rtl/alu_pkg.sv rtl/csr_pkg.sv rtl/opcode_pkg.sv rtl/fp_pkg.sv rtl/muldiv_pkg.sv rtl/bp_pkg.sv rtl/cache_pkg.sv rtl/vec_pkg.sv"
T=$(mktemp -d)
fail=0

good() {
  local mod=$1 e=$2 f=$3
  if ! verilator --lint-only -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD -Wno-WIDTH --top-module "$mod" -GExpW="$e" -GFracW="$f" $PKGS "rtl/$mod.sv" >"$T/v.log" 2>&1; then
    echo "FAIL $mod ExpW=$e FracW=$f rejected by verilator"; cat "$T/v.log"; fail=1
  fi
  if ! iverilog -g2012 -P "$mod.ExpW=$e" -P "$mod.FracW=$f" -o "$T/i" $PKGS "rtl/$mod.sv" >"$T/i.log" 2>&1; then
    echo "FAIL $mod ExpW=$e FracW=$f rejected by iverilog"; cat "$T/i.log"; fail=1
  fi
}

bad() {
  local mod=$1 e=$2 f=$3
  verilator --lint-only -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD -Wno-WIDTH --top-module "$mod" -GExpW="$e" -GFracW="$f" $PKGS "rtl/$mod.sv" >"$T/v.log" 2>&1
  if ! grep -q USERERROR "$T/v.log"; then
    echo "FAIL $mod ExpW=$e FracW=$f accepted by verilator"; fail=1
  fi
  iverilog -g2012 -P "$mod.ExpW=$e" -P "$mod.FracW=$f" -o "$T/i" $PKGS "rtl/$mod.sv" >"$T/i.log" 2>&1
  if ! grep -q "outside the supported range" "$T/i.log"; then
    echo "FAIL $mod ExpW=$e FracW=$f accepted by iverilog"; fail=1
  fi
}

for mod in fp_add fp_mul fp_fma fp_div_sqrt fp_cvt fp_misc fp_rec7; do
  good "$mod" 8 23
  good "$mod" 11 52
done
good fp_add 5 10
good fp_mul 5 10
good fp_div_sqrt 5 10
good fp_fma 5 10
good fp_misc 5 10
good fp_rec7 5 10
bad fp_add 1 23
bad fp_mul 4 23
bad fp_mul 15 64
bad fp_fma 5 23
bad fp_div_sqrt 5 23
bad fp_cvt 5 23
bad fp_misc 8 1
bad fp_rec7 8 7

if [ "$fail" -eq 0 ]; then echo "FLOAT WIDTH GUARD PASS"; else exit 1; fi
