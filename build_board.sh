#!/usr/bin/env bash
# Usage build_board.sh [clkdiv] [flash]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
CLKDIV=""
FLASH=""
for arg in "$@"; do
  case "$arg" in
    flash) FLASH=flash ;;
    *) CLKDIV="$arg" ;;
  esac
done
CLKDIV="${CLKDIV:-$(sed -n 's/^CLKDIV *?*= *\([0-9]*\).*/\1/p' config.mk)}"
mkdir -p build

: "${NEXTPNR_XILINX_DIR:?set NEXTPNR_XILINX_DIR to a nextpnr-xilinx checkout}"
CHIPDB="$NEXTPNR_XILINX_DIR/xilinx/xc7a35t.bin"
DBROOT="$NEXTPNR_XILINX_DIR/xilinx/external/prjxray-db/artix7"
PARTYAML="$DBROOT/xc7a35tcpg236-1/part.yaml"
PART=xc7a35tcpg236-1

PKGS="rtl/arch_pkg.sv $(ls rtl/*_pkg.sv | grep -v arch_pkg)"
REST=$(ls rtl/*.sv | grep -v '_pkg\.sv$')

echo "sv2v"
sv2v -D SYNTHESIS $PKGS $REST rtl/boards/basys3/board_top.sv > build/design.v
echo "synth (ClkDiv=${CLKDIV}, keep pc_plus4)"
# Keep pc_plus4 nets
yosys -q -p "read_verilog build/design.v; hierarchy -top board_top -chparam ClkDiv ${CLKDIV}; setattr -set keep 1 w:*pc_plus4*; synth_xilinx -top board_top -flatten; write_json build/design.json"
echo "pnr"
nextpnr-xilinx --chipdb "$CHIPDB" --xdc constraints/basys3.xdc \
  --json build/design.json --fasm build/design.fasm --router router2 2>&1 | grep -iE "Max frequency for clock"
echo "bitstream"
fasm2frames --db-root "$DBROOT" --part "$PART" build/design.fasm build/design.frames 2>/dev/null
xc7frames2bit --part_file "$PARTYAML" --part_name "$PART" --frm_file build/design.frames --output_file build/design.bit 2>/dev/null
echo "wrote build/design.bit"

if [ "$FLASH" = "flash" ]; then
  echo "flash"
  openFPGALoader -b basys3 build/design.bit
fi
