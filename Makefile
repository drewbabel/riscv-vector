#   make MOD=pc                  compile rtl/ + that tb, run (FAIL exits nonzero)
#   make MOD=pc MAX_ERRORS=3     stop after 3 mismatches
#   make vsim MOD=pc             fast 2-state Verilator run (perf sweeps + regression; not X-debug)
#   make wave MOD=alu            same, then open the waveform in surfer (opens even on FAIL)
#   make view MOD=alu            open testbench waveform in surfer (no rerun) (error if .vcd missing)
#   make fmt MOD=alu             format rtl/$(MOD).sv and tb/$(MOD)_tb.sv in place
#   make formal MOD=alu          run every SymbiYosys task in formal/$(MOD).sby (FAIL exits nonzero)
#   make trace MOD=alu           print a formal counterexample as text
#   make view-formal MOD=alu     open a formal waveform in surfer; error if .vcd missing
#   make view-rvfi CHECK=insn_addi_ch0   open a riscv-formal counterexample in surfer
#   make hex PROG=program        assemble tests/$(PROG).s -> tests/$(PROG).hex for $readmemh
#   make dis PROG=program        disassemble the built elf (sanity-check the machine code)
#   make sw PROG=hello           build sw/hello/*.c into build/hello.hex
#   make sw-run PROG=hello       run it on the Nexys video board model
#   make cosim PROG=cosim1       lockstep-compare tests/cosim1.s against Spike (needs spike installed)
#   make cosim PROG=cosim1 TRACE=1   same, plus build/cosim1.trace, one line per retired instruction
#   make clean                   delete build artifacts (build/, *.vcd)

SHELL := /bin/bash

# packages must compile before any module that imports them
PKGS := rtl/arch_pkg.sv rtl/alu_pkg.sv rtl/csr_pkg.sv rtl/opcode_pkg.sv rtl/fp_pkg.sv rtl/muldiv_pkg.sv \
        rtl/bp_pkg.sv rtl/cache_pkg.sv rtl/vec_pkg.sv
RTL := $(PKGS) $(filter-out $(PKGS),$(wildcard rtl/*.sv)) $(wildcard rtl/boards/bram/*.sv) \
       $(wildcard rtl/single_cycle/*.sv)
TB  := tb/$(MOD)_tb.sv
SIM := build/sim
VDIR := build/vobj_$(MOD)
VCD := $(MOD)_tb.vcd
WAVE_STATE := $(shell test -f tb/$(MOD).ron && echo tb/$(MOD).ron || \
  (grep -qs riscv_pipelined tb/$(MOD)_tb.sv && echo build/pipeline_$(MOD).ron))
PIPE_LAYOUT := tb/surfer/pipeline.ron.in
RVFI_DIR := $(or $(RISCV_FORMAL_DIR),build/riscv-formal)/cores/rv32i_pipe/checks
FORMAL := formal/$(MOD).sby

# program build: RISC-V assembly -> hex words for $readmemh
RVPREFIX ?= riscv64-elf-
RVGCC   := $(RVPREFIX)gcc
RVCOPY  := $(RVPREFIX)objcopy
RVDUMP  := $(RVPREFIX)objdump
RVFLAGS := -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T tests/link.ld

# TestFloat reference files
SOFTFLOAT_SHA := a0c6494cdc11865811dec815d5c0049fba9d82a8
TESTFLOAT_SHA := a9c849f1b0eb0264b626d9686ffae167d996e3be
SOFTFLOAT_SRC := build/berkeley-softfloat-3
TESTFLOAT_SRC := build/berkeley-testfloat-3
TF_PLATFORM   := Linux-x86_64-GCC
TF_GEN        := $(TESTFLOAT_SRC)/build/$(TF_PLATFORM)/testfloat_gen
TF_DIR        := build/testfloat
TF_RMS        := rne rtz rdn rup rmm
TF_RM_rne     := near_even
TF_RM_rtz     := minMag
TF_RM_rdn     := min
TF_RM_rup     := max
TF_RM_rmm     := near_maxMag
TF_ROUNDED    := f32_add f32_sub f32_mul f32_div i32_to_f32 ui32_to_f32 \
                 f64_add f64_sub f64_mul f64_div i32_to_f64 ui32_to_f64 \
                 f16_add f16_sub f16_mul f16_div
TF_SQRT       := f32_sqrt f64_sqrt f16_sqrt
TF_SQRT_OPTS  := -level 2 -n 46464
TF_EXACT      := f32_to_i32 f32_to_ui32 f64_to_i32 f64_to_ui32
TF_CMP        := f32_eq f32_le f32_lt f64_eq f64_le f64_lt f16_eq f16_le f16_lt
TF_MULADD     := f32_mulAdd f64_mulAdd f16_mulAdd
TF_MULADD_STRIDE := 31
TF_FLAGS      := -tininessafter

run:
	@test -n "$(MOD)" || { echo "usage: make MOD=<module>  (e.g. MOD=alu)"; exit 1; }
	@mkdir -p build
	iverilog -g2012 -DSIM_BACKDOOR -s $(MOD)_tb -o $(SIM) $(RTL) $(TB)
	vvp $(SIM) $(if $(MAX_ERRORS),+max_errors=$(MAX_ERRORS))

vsim:
	@test -n "$(MOD)" || { echo "usage: make vsim MOD=<module>  (fast 2-state Verilator run)"; exit 1; }
	@mkdir -p build
	verilator --binary --timing -O3 -j 4 -DSIM_BACKDOOR -Wno-fatal -Wno-WIDTH \
		--top-module $(MOD)_tb -Mdir $(VDIR) -o $(MOD)_vsim $(RTL) $(TB)
	$(VDIR)/$(MOD)_vsim $(PLUSARGS) $(if $(MAX_ERRORS),+max_errors=$(MAX_ERRORS))

prog:
	@test -n "$(PROG)" || { echo "usage: make prog PROG=<name>  (tests/<name>.s, PASS = x28==1)"; exit 1; }
	@mkdir -p build
	$(RVGCC) $(RVFLAGS) -o build/$(PROG).elf tests/$(PROG).s
	$(RVCOPY) -O verilog --verilog-data-width=4 build/$(PROG).elf tests/$(PROG).hex
	iverilog -g2012 -s prog_tb -o $(SIM) $(RTL) tb/prog_tb.sv
	vvp $(SIM) +HEX=tests/$(PROG).hex $(if $(MAX_ERRORS),+max_errors=$(MAX_ERRORS))

wave:
	@test -n "$(MOD)" || { echo "usage: make wave MOD=<module>"; exit 1; }
	@mkdir -p build
	iverilog -g2012 -DSIM_BACKDOOR -s $(MOD)_tb -o $(SIM) $(RTL) $(TB)
	-vvp $(SIM) $(if $(MAX_ERRORS),+max_errors=$(MAX_ERRORS))
	@$(if $(WAVE_STATE),$(MAKE) -s $(WAVE_STATE),true)
	surfer $(VCD) $$(test -n "$(WAVE_STATE)" && echo "-s $(WAVE_STATE)") &

build/pipeline_%.ron: $(PIPE_LAYOUT)
	@mkdir -p build
	sed -e 's/@TOP@/$*_tb/' -e 's/@A@/dut/' -e 's/@B@/riscv_pipelined_inst/' $< > $@

build/pipeline_rvfi.ron: $(PIPE_LAYOUT)
	@mkdir -p build
	sed -e 's/@TOP@/rvfi_testbench/' -e 's/@A@/wrapper/' -e 's/@B@/uut/' $< > $@

fmt:
	@test -n "$(MOD)" || { echo "usage: make fmt MOD=<module>  (e.g. MOD=alu)"; exit 1; }
	verible-verilog-format --inplace $(wildcard rtl/$(MOD).sv tb/$(MOD)_tb.sv)

formal:
	@test -n "$(MOD)" || { echo "usage: make formal MOD=<module>  (e.g. MOD=alu)"; exit 1; }
	@mkdir -p build
	sv2v -E Assert -D RISCV_FORMAL -D RISCV_FORMAL_ABSTRACT_XRES $(RTL) formal/$(MOD)_formal.sv > build/$(MOD)_formal.v
	@sby -f $(FORMAL) $(TASK) 2>&1 | tee build/$(MOD)_sby.log; rc=$${PIPESTATUS[0]}; \
	  grep -oE '$(MOD)_formal\.v:[0-9]+' build/$(MOD)_sby.log | sort -u | while read -r hit; do \
	    ln=$${hit##*:}; \
	    printf '  %s:%s  %s\n' "$(MOD)_formal.v" "$$ln" \
	      "$$(sed -n "$${ln}p" build/$(MOD)_formal.v | sed 's/^[[:space:]]*//')"; \
	  done; \
	  exit $$rc

view:
	@test -n "$(MOD)" || { echo "usage: make view MOD=<module>"; exit 1; }
	@test -f "$(VCD)" || { echo "Error: $(VCD) not found (run make MOD=$(MOD) first)"; exit 1; }
	@$(if $(WAVE_STATE),$(MAKE) -s $(WAVE_STATE),true)
	surfer $(VCD) $$(test -n "$(WAVE_STATE)" && echo "-s $(WAVE_STATE)") &

view-rvfi:
	@test -n "$(CHECK)" || { echo "usage: make view-rvfi CHECK=<check>  (e.g. CHECK=insn_addi_ch0)"; exit 1; }
	@vcd=$$(find $(RVFI_DIR)/$(CHECK) -name '*.vcd' 2>/dev/null | head -1); \
	test -n "$$vcd" || { echo "Error: no .vcd under $(RVFI_DIR)/$(CHECK)/ (run formal/rvfi/run.sh $(CHECK) first)"; exit 1; }; \
	$(MAKE) -s build/pipeline_rvfi.ron; \
	echo "surfer $$vcd"; \
	surfer $$vcd -s build/pipeline_rvfi.ron &

# Echoes MOD's run directory, prompting when the .sby split into several tasks
define pick_run
	test -n "$(MOD)" || { echo "usage: make $@ MOD=<module>  (e.g. MOD=alu)" >&2; exit 1; }; \
	runs=$$(for d in formal/$(MOD)/ formal/$(MOD)_*/; do [ -f "$$d/status" ] && echo "$${d%/}"; done); \
	[ -n "$$runs" ] || { echo "No runs for $(MOD), try: make formal MOD=$(MOD)" >&2; exit 1; }; \
	if [ $$(echo "$$runs" | wc -l) -eq 1 ]; then echo "$$runs"; else \
	  i=0; for d in $$runs; do i=$$((i+1)); \
	    printf '  %d) %-12s %-6s%s\n' $$i "$$(basename $$d | sed 's/^$(MOD)_//')" \
	      "$$(cut -d' ' -f1 $$d/status)" \
	      "$$(find $$d -name trace.yw 2>/dev/null | head -1 | sed 's/.*/counterexample/')" >&2; \
	  done; \
	  printf 'Select task: ' >&2; read n; \
	  sel=$$(echo "$$runs" | sed -n "$${n}p" 2>/dev/null); \
	  [ -d "$$sel" ] || { echo "No task $$n" >&2; exit 1; }; \
	  echo "$$sel"; fi
endef

trace:
	@dir=$$($(pick_run)); test -n "$$dir" || exit 1; \
	yw=$$(find $$dir -name 'trace.yw' 2>/dev/null | head -1); \
	test -n "$$yw" || { echo "Error: no trace.yw in $$dir/, that run has no counterexample"; exit 1; }; \
	yosys-witness display $$yw | cat

view-formal:
	@dir=$$($(pick_run)); test -n "$$dir" || exit 1; \
	vcd=$$(find $$dir -name '*.vcd' 2>/dev/null | head -1); \
	test -n "$$vcd" || { echo "Error: no .vcd found in $$dir/"; exit 1; }; \
	echo "surfer $$vcd"; \
	surfer $$vcd $$(test -f $$dir.ron && echo "-s $$dir.ron") &

hex:
	@test -n "$(PROG)" || { echo "usage: make hex PROG=<name>  (tests/<name>.s -> tests/<name>.hex)"; exit 1; }
	@mkdir -p build
	$(RVGCC) $(RVFLAGS) -o build/$(PROG).elf tests/$(PROG).s
	$(RVCOPY) -O verilog --verilog-data-width=4 build/$(PROG).elf tests/$(PROG).hex
	@echo "built tests/$(PROG).hex"

dis:
	@test -n "$(PROG)" || { echo "usage: make dis PROG=<name>"; exit 1; }
	$(RVDUMP) -d build/$(PROG).elf

cosim:
	@test -n "$(PROG)" || { echo "usage: make cosim PROG=<name>  (lockstep tests/$(PROG).s vs Spike)"; exit 1; }
	python3 tests/cosim.py $(if $(TRACE),--trace) $(PROG)

SWPREFIX  ?= riscv-none-elf-
SWCOMMON  := sw/common
SWARCH    := rv32imf_zicsr_zve32f_zvl128b
SWDEFS    ?=
SWCFLAGS  := -march=$(SWARCH) -mabi=ilp32f -O2 -fno-tree-vectorize -I$(SWCOMMON) $(SWDEFS)
SWLDFLAGS := -march=$(SWARCH) -mabi=ilp32f -specs=nano.specs -nostartfiles -Wl,--no-warn-rwx-segments -T $(SWCOMMON)/board.ld
SWLIMIT   ?= 4294967295
BOARD_RTL := $(PKGS) $(filter-out $(PKGS),$(wildcard rtl/*.sv)) $(wildcard rtl/single_cycle/*.sv) rtl/boards/nexys_video/board_top.sv

sw:
	@test -n "$(PROG)" || { echo "usage: make sw PROG=<name>  (sources in sw/<name>/)"; exit 1; }
	@mkdir -p build
	$(SWPREFIX)gcc $(SWCFLAGS) $(SWLDFLAGS) -o build/$(PROG).elf $(SWCOMMON)/crt.S $(SWCOMMON)/sys.c sw/$(PROG)/*.c -lm
	$(SWPREFIX)objcopy -O binary build/$(PROG).elf build/$(PROG).bin
	python3 $(SWCOMMON)/bin2hex.py build/$(PROG).bin build/$(PROG).hex
	@echo "built build/$(PROG).hex"

build/board_sim: $(BOARD_RTL) tb/mig_7series_0.sv tb/board_run_tb.sv
	@mkdir -p build
	verilator --binary --timing -O3 -j 8 -Wno-fatal -Wno-WIDTH -Wno-MULTITOP \
		--top-module board_run_tb -Mdir build/obj_board -o board_sim \
		$(BOARD_RTL) tb/mig_7series_0.sv tb/board_run_tb.sv
	cp build/obj_board/board_sim build/board_sim

sw-run:
	@test -n "$(PROG)" || { echo "usage: make sw-run PROG=<name>"; exit 1; }
	$(MAKE) -s sw PROG=$(PROG)
	$(MAKE) -s build/board_sim
	build/board_sim +HEX=build/$(PROG).hex +LIMIT=$(SWLIMIT)

$(SOFTFLOAT_SRC):
	git clone -q https://github.com/ucb-bar/berkeley-softfloat-3.git $@
	git -C $@ checkout -q $(SOFTFLOAT_SHA)

$(TESTFLOAT_SRC):
	git clone -q https://github.com/ucb-bar/berkeley-testfloat-3.git $@
	git -C $@ checkout -q $(TESTFLOAT_SHA)

$(TF_GEN): | $(SOFTFLOAT_SRC) $(TESTFLOAT_SRC)
	$(MAKE) -s -C $(SOFTFLOAT_SRC)/build/$(TF_PLATFORM) SPECIALIZE_TYPE=RISCV
	$(MAKE) -s -C $(TESTFLOAT_SRC)/build/$(TF_PLATFORM) testfloat_gen

testfloat: $(TF_GEN)
	@mkdir -p $(TF_DIR)
	@set -o pipefail && $(foreach r,$(TF_RMS),\
	  $(foreach o,$(TF_ROUNDED),$(TF_GEN) $(TF_FLAGS) -r$(TF_RM_$(r)) $(o) > $(TF_DIR)/$(o)_$(r).txt &&) \
	  $(foreach o,$(TF_EXACT),$(TF_GEN) $(TF_FLAGS) -r$(TF_RM_$(r)) -exact $(o) > $(TF_DIR)/$(o)_$(r).txt &&) \
	  $(foreach o,$(TF_SQRT),$(TF_GEN) $(TF_FLAGS) -r$(TF_RM_$(r)) $(TF_SQRT_OPTS) $(o) > $(TF_DIR)/$(o)_$(r).txt &&) \
	  $(foreach o,$(TF_MULADD),$(TF_GEN) $(TF_FLAGS) -r$(TF_RM_$(r)) $(o) | awk 'NR % $(TF_MULADD_STRIDE) == 0' > $(TF_DIR)/$(o)_$(r).txt &&)) \
	  $(foreach o,$(TF_CMP),$(TF_GEN) $(TF_FLAGS) $(o) > $(TF_DIR)/$(o).txt &&) true
	@echo "wrote $$(ls $(TF_DIR) | wc -l | tr -d ' ') files to $(TF_DIR)"

clean:
	rm -rf build *.vcd sim_build results.xml

.DEFAULT_GOAL := run
.PHONY: run vsim prog wave fmt formal view view-rvfi trace view-formal hex dis cosim testfloat clean sw sw-run
