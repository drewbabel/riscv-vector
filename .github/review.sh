#!/bin/sh
set -u
base=$1
reporter=$2
PKGS="rtl/arch_pkg.sv rtl/alu_pkg.sv rtl/csr_pkg.sv rtl/opcode_pkg.sv rtl/fp_pkg.sv rtl/muldiv_pkg.sv rtl/bp_pkg.sv
  rtl/cache_pkg.sv rtl/vec_pkg.sv"
CLANG_STYLE='{BasedOnStyle: LLVM, IndentWidth: 4, ColumnLimit: 80}'
t=$(mktemp -d)
rc=0

git diff --name-only --diff-filter=AM "$base...HEAD" > "$t/changed" || exit 1
grep -E '\.s?v$' "$t/changed" > "$t/sv" || true
grep -E '\.py$' "$t/changed" > "$t/py" || true
grep -E '\.(c|h)$' "$t/changed" | grep -v '^tests/rvv_env/' > "$t/c" || true
grep -vE '\.(s?v|py|c|h|md)$|^Makefile$|\.mk$|\.(bin|hex|pdf|png|svg|zip)$' "$t/changed" > "$t/text" || true

diff_cmd=""
if [ "$reporter" = local ]; then
  GIT_DIR=$(git rev-parse --absolute-git-dir)
  GIT_WORK_TREE="$t/w"
  GIT_INDEX_FILE="$t/index"
  export GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  mkdir "$t/w"
  git read-tree HEAD || exit 1
  git archive HEAD | tar -x -C "$t/w" || exit 1
  cd "$t/w" || exit 1
  diff_cmd="git diff $base...HEAD"
fi

rd() {
  reviewdog "$@" -reporter="$reporter" -filter-mode=added -fail-level=none ${diff_cmd:+"-diff=$diff_cmd"}
}

while read -r f; do verible-verilog-lint "$f" 2>&1 || true; done < "$t/sv" \
  | rd -efm='%f:%l:%c-%*[0-9]: %m' -efm='%f:%l:%c: %m' -name=verible-lint || rc=1

while read -r f; do
  case "$f" in formal/rvfi/*) continue ;; esac
  top=$(basename "$f" | sed -E 's/\.s?v$//')
  pkgs=$(echo $PKGS | tr ' ' '\n' | grep -vx "$f" | tr '\n' ' ')
  opts="--top-module $top"
  case "$f" in tb/cosim.sv) opts="$opts --timing -DRISCV_FORMAL" ;; tb/*) opts="$opts --timing -DSIM_BACKDOOR" ;; formal/*) opts="$opts -DRISCV_FORMAL" ;; *_pkg.sv) opts="" ;; rtl/boards/nexys_video/*) opts="$opts -Wno-MODMISSING" ;; esac
  board=rtl/boards/bram
  srcs="$f"
  case "$f" in tb/board_run_tb.sv) board=rtl/boards/nexys_video; srcs="tb/mig_7series_0.sv $f" ;; esac
  verilator --lint-only -Wno-TIMESCALEMOD $opts -y rtl -y $board -y rtl/single_cycle +libext+.v+.sv \
    $pkgs $srcs 2>&1 || true
done < "$t/sv" \
  | rd -efm='%%%tarning-%*[A-Z0-9_]: %f:%l:%c: %m' -efm='%%%trror-%*[A-Z0-9_]: %f:%l:%c: %m' \
      -efm='%%%trror: %f:%l:%c: %m' -efm='%-G%.%#' -name=verilator || rc=1

rtl=$(ls rtl/*.sv rtl/boards/bram/*.sv rtl/single_cycle/*.sv | grep -v '_pkg\.sv$')
while read -r f; do
  case "$f" in formal/rvfi/*|rtl/boards/nexys_video/*) continue ;; esac
  pkgs=$(echo $PKGS | tr ' ' '\n' | grep -vx "$f" | tr '\n' ' ')
  others=$(echo "$rtl" | grep -vx "$f" | tr '\n' ' ')
  case "$f" in *_pkg.sv) others="" ;; tb/board_run_tb.sv) others="$(echo "$rtl" | grep -vx rtl/boards/bram/board_top.sv | tr '\n' ' ') rtl/boards/nexys_video/board_top.sv tb/mig_7series_0.sv" ;; esac
  defs=""
  case "$f" in formal/*|tb/cosim.sv) defs="-DRISCV_FORMAL" ;; tb/*) defs="-DSIM_BACKDOOR" ;; esac
  iverilog -g2012 $defs -o /dev/null $pkgs $others "$f" 2>&1 || true
done < "$t/sv" \
  | { grep -vE '^formal/[^:]+:[0-9]+: warning: (System task \(\$[a-z]+\) cannot be synthesized in an always_(comb|ff)|always_comb process has no sensitivities)' || true; } \
  | rd -efm='%f:%l: %trror: %m' -efm='%f:%l: %tarning: %m' -efm='%-G%.%#' -name=iverilog || rc=1

if [ -s "$t/py" ]; then
  ruff check --output-format=concise --line-length 80 $(cat "$t/py") || true
fi | rd -efm='%f:%l:%c: %m' -efm='%-G%.%#' -name=ruff || rc=1

[ -s "$t/sv" ] && verible-verilog-format --inplace $(cat "$t/sv") || true
[ -s "$t/py" ] && ruff format --line-length 80 $(cat "$t/py") >&2 || true
[ -s "$t/c" ] && clang-format -i -style="$CLANG_STYLE" $(cat "$t/c") || true
while read -r f; do
  sed -E 's/[[:blank:]]+$//' "$f" > "$t/strip" && cat "$t/strip" > "$f" || rc=1
  if [ -n "$(tail -c1 "$f")" ]; then echo >> "$f"; fi
done < "$t/text"

if [ "$reporter" = local ]; then
  git diff | rd -f=diff -f.diff.strip=1 -name=format || rc=1
fi
exit $rc
