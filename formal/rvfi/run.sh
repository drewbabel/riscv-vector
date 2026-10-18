#!/usr/bin/env bash
# Build and run the riscv-formal suite against the core
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORE=rv32i_pipe
RVF="${RISCV_FORMAL_DIR:-$ROOT/build/riscv-formal}"

if [ ! -d "$RVF" ]; then
  git clone https://github.com/YosysHQ/riscv-formal.git "$RVF"
fi

DST="$RVF/cores/$CORE"
mkdir -p "$DST"
cat "$ROOT/rtl/opcode_pkg.sv" "$HERE/rvfi_wrapper.sv" > "$DST/wrapper.sv"
cp "$HERE/checks.cfg" "$DST/checks.cfg"

sv2v -D RISCV_FORMAL -D RISCV_FORMAL_ABSTRACT_XRES \
  $(ls "$ROOT"/rtl/*.sv | grep -v -e '/vec_unit\.sv$' -e '/fp_unit\.sv$') \
  "$HERE/vec_unit_stub.sv" "$HERE/fp_unit_stub.sv" \
  | sed -e 's/^\([[:space:]]*\)vec_unit #(/\1vec_unit_stub #(/' \
        -e 's/^\([[:space:]]*\)fp_unit #(/\1fp_unit_stub #(/' > "$DST/$CORE.v"

cd "$DST"
python3 "$RVF/checks/genchecks.py" >&2
if [ "${RVFI_SMT:-0}" != "1" ]; then
  ls checks/*.sby | xargs perl -i -pe 's/smtbmc yices/btor btormc/'
fi

# a failing check must fail the run
perl -i -ne 'print unless /^expect /' checks/*.sby

if [ "${1:-}" = "--list" ]; then
  ls checks/*.sby | xargs -n1 basename | sed 's/\.sby$//'
elif [ "$#" -gt 0 ]; then
  failed=""
  for c in "$@"; do sby -f "checks/$c.sby" || failed="$failed $c"; done
  if [ -n "$failed" ]; then
    echo "FAILED:$failed" >&2
    exit 1
  fi
else
  make -j"$(getconf _NPROCESSORS_ONLN)" -C checks
fi
