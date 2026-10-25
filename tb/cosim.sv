`default_nettype none

module cosim ();

  cosim_bench #(.Depth(256)) bench ();

endmodule

module cosim_gen ();

  cosim_bench #(.Depth(131072)) bench ();

endmodule

module cosim_bench #(
    parameter int Depth = 256
) ();

  import csr_pkg::*;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Vlen = arch_pkg::VLEN;
  localparam int Vregs = arch_pkg::NumRegs;
  localparam int AddrW = arch_pkg::RegAddrW;
  localparam int Flen = fp_pkg::FLEN;
  localparam int FlagW = $bits(fp_pkg::FlagNv);
  localparam int CauseW = $bits(CauseMachineExternalIrq);
  localparam int VlW = $clog2(Vlen + 1);
  localparam int VstartW = $clog2(Vlen);
  localparam int LineWords = cache_pkg::LineWords;
  localparam int DrainCycles = 2000;
  localparam int MinChecks = 10;

  int                                checks = 0;
  int                                errors = 0;
  int                                max_errors = 0;
  int                                commits = 0;

  logic                              clk = 1'b0;
  logic                              rst_n;
  logic   [                Xlen-1:0] pc;
  logic   [                Xlen-1:0] alu_result;
  logic   [                Xlen-1:0] write_data;
  logic                              mem_write;

  string                             hexfile;
  string                             vcdfile;
  int                                max_commits;
  int                                preload;
  int                                log_traps;
  logic                              parked;

  // Debug ports
  logic                              dbg_valid;
  logic   [                Xlen-1:0] dbg_insn;
  logic   [                Xlen-1:0] dbg_pc_rdata;
  logic   [                Xlen-1:0] dbg_pc_wdata;
  logic   [                Xlen-1:0] dbg_rs1_rdata;
  logic   [                Xlen-1:0] dbg_rs2_rdata;
  logic   [                Xlen-1:0] dbg_rd_wdata;
  logic                              dbg_reg_write;
  logic   [                Xlen-1:0] dbg_mem_addr;
  logic   [              Xlen/8-1:0] dbg_mem_wmask;
  logic   [                Xlen-1:0] dbg_mem_wdata;
  logic   [                Xlen-1:0] dbg_mem_rdata;
  logic                              dbg_trap;
  logic   [                Xlen-1:0] dbg_csr_wdata;
  logic   [                Xlen-1:0] dbg_mscratch;
  logic   [                Xlen-1:0] dbg_mstatus;
  logic   [                Xlen-1:0] dbg_mtvec;
  logic   [                Xlen-1:0] dbg_mepc;
  logic   [                Xlen-1:0] dbg_mcause;
  logic   [                Xlen-1:0] dbg_mtval;
  logic   [                Xlen-1:0] dbg_mie;
  logic   [                Xlen-1:0] dbg_mip;
  logic   [                Xlen-1:0] dbg_mcycle;
  logic   [                Xlen-1:0] dbg_minstret;
  logic   [                Xlen-1:0] dbg_mcycleh;
  logic   [                Xlen-1:0] dbg_minstreth;
  logic   [               FlagW-1:0] dbg_fflags;
  logic   [                 VlW-1:0] dbg_vl;
  logic   [                     7:0] dbg_vtype_bits;
  logic                              dbg_vtype_ill;
  logic   [             VstartW-1:0] dbg_vstart;
  logic   [                     7:0] dbg_vec_tag;
  logic                              dbg_vec_retire;
  logic   [               Vregs-1:0] dbg_vec_wregs;
  logic                              dbg_vec_idle;
  logic                              dbg_ex_commit;
  logic   [                Xlen-1:0] dbg_ex_insn;
  logic                              dbg_s_take;
  logic                              dbg_v_take;

  // Bus wait model
  integer                            stall_seed;
  int                                stall_pct;
  int                                stall_max;
  int                                fetch_wait;
  int                                data_wait;
  int                                fetch_stalls = 0;
  int                                data_stalls = 0;
  logic                              imem_ready;
  logic                              dmem_ready;
  logic                              dmem_req;
  logic   [                Xlen-1:0] instr;
  logic   [                Xlen-1:0] imem_word;
  logic   [                Xlen-1:0] mem_addr;
  logic   [ cache_pkg::LineBits-1:0] read_data;
  logic   [ cache_pkg::LineBits-1:0] dmem_line;
  logic   [ cache_pkg::LineBits-1:0] store_data;
  logic   [cache_pkg::LineBytes-1:0] store_wstrb;

  // Random interrupt lines
  integer                            irq_seed;
  int                                irq_rate;
  logic                              ext_line;
  logic                              timer_line;
  logic                              irq_ready;
  logic                              irq_ready_q;
  logic                              ext_q;
  logic                              timer_q;
  logic                              irq_take;
  logic                              irq_ext;
  logic   [                     1:0] irq_lines         [    $];

  // RVFI retirement taps
  logic                              r_valid;
  logic                              r_trap;
  logic   [                Xlen-1:0] r_pc;
  logic   [                Xlen-1:0] r_insn;
  logic   [                Xlen-1:0] r_wdata;
  logic                              r_rw;
  logic   [                Xlen-1:0] r_maddr;
  logic   [              Xlen/8-1:0] r_wmask;
  logic   [                Xlen-1:0] r_sdata;
  logic   [                 VlW-1:0] r_vl;
  logic   [                     7:0] r_vtype_bits;
  logic                              r_vtype_ill;
  logic   [             VstartW-1:0] r_vstart;

  // Vector retirement taps
  logic   [                     7:0] r_vtag;
  logic                              r_vretire;
  logic   [               Vregs-1:0] r_vwregs;
  logic                              r_vidle;
  logic   [                Vlen-1:0] vpeek             [Vregs];

  logic                              v_accepted = 1'b0;

  logic                              r_fwe;
  logic   [               AddrW-1:0] r_frd;
  logic   [                Flen-1:0] r_fdata;
  logic                              r_fidle;
  logic                              r_flwe;
  logic   [               AddrW-1:0] r_flrd;
  logic   [                Xlen-1:0] r_fldata;

  always #5 clk = ~clk;

  if (1) begin : g_dut
    riscv_pipelined #(
        .XLEN(Xlen)
    ) riscv_pipelined_inst (
        .dbg_valid     (dbg_valid),
        .dbg_insn      (dbg_insn),
        .dbg_pc_rdata  (dbg_pc_rdata),
        .dbg_pc_wdata  (dbg_pc_wdata),
        .dbg_rs1_rdata (dbg_rs1_rdata),
        .dbg_rs2_rdata (dbg_rs2_rdata),
        .dbg_rd_wdata  (dbg_rd_wdata),
        .dbg_reg_write (dbg_reg_write),
        .dbg_mem_addr  (dbg_mem_addr),
        .dbg_mem_wmask (dbg_mem_wmask),
        .dbg_mem_wdata (dbg_mem_wdata),
        .dbg_mem_rdata (dbg_mem_rdata),
        .dbg_trap      (dbg_trap),
        .dbg_csr_wdata (dbg_csr_wdata),
        .dbg_mscratch  (dbg_mscratch),
        .dbg_mstatus   (dbg_mstatus),
        .dbg_mtvec     (dbg_mtvec),
        .dbg_mepc      (dbg_mepc),
        .dbg_mcause    (dbg_mcause),
        .dbg_mtval     (dbg_mtval),
        .dbg_mie       (dbg_mie),
        .dbg_mip       (dbg_mip),
        .dbg_mcycle    (dbg_mcycle),
        .dbg_minstret  (dbg_minstret),
        .dbg_mcycleh   (dbg_mcycleh),
        .dbg_minstreth (dbg_minstreth),
        .dbg_fflags    (dbg_fflags),
        .dbg_vl        (dbg_vl),
        .dbg_vtype_bits(dbg_vtype_bits),
        .dbg_vtype_ill (dbg_vtype_ill),
        .dbg_vstart    (dbg_vstart),
        .dbg_vec_tag   (dbg_vec_tag),
        .dbg_vec_retire(dbg_vec_retire),
        .dbg_vec_wregs (dbg_vec_wregs),
        .dbg_vec_idle  (dbg_vec_idle),
        .dbg_ex_commit (dbg_ex_commit),
        .dbg_ex_insn   (dbg_ex_insn),
        .dbg_s_take    (dbg_s_take),
        .dbg_v_take    (dbg_v_take),
        .clk           (clk),
        .core_en       (1'b1),
        .rst_n         (rst_n),
        .instr         (instr),
        .read_data     (read_data),
        .timer_irq     (timer_line),
        .ext_irq       (ext_line),
        .imem_ready    (imem_ready),
        .dmem_ready    (dmem_ready),
        .dmem_req      (dmem_req),
        .pc            (pc),
        .mem_write     (mem_write),
        .alu_result    (alu_result),
        .write_data    (write_data),
        .store_wstrb   (store_wstrb),
        .store_data    (store_data),
        .mem_addr      (mem_addr)
    );

    imem #(
        .XLEN (Xlen),
        .DEPTH(Depth)
    ) imem_inst (
        .clk  (clk),
        .we   (1'b0),
        .waddr('0),
        .wdata('0),
        .addr (pc),
        .instr(imem_word)
    );

    // Write on accept
    dmem #(
        .XLEN (Xlen),
        .DEPTH(Depth)
    ) dmem_inst (
        .clk  (clk),
        .wstrb((dmem_req && dmem_ready) ? store_wstrb : '0),
        .addr (mem_addr),
        .wdata(store_data),
        .rdata(dmem_line)
    );
  end

  assign r_valid = dbg_valid;
  assign r_trap = dbg_trap;
  assign r_pc = dbg_pc_rdata;
  assign r_insn = dbg_insn;
  assign r_wdata = dbg_rd_wdata;
  assign r_rw = dbg_reg_write;
  assign r_maddr = dbg_mem_addr;
  assign r_wmask = dbg_mem_wmask;
  assign r_sdata = dbg_mem_wdata;
  assign r_vl = dbg_vl;
  assign r_vtype_bits = dbg_vtype_bits;
  assign r_vtype_ill = dbg_vtype_ill;
  assign r_vstart = dbg_vstart;

  assign r_vtag = dbg_vec_tag;
  assign r_vretire = dbg_vec_retire;
  assign r_vwregs = dbg_vec_wregs;
  assign r_vidle = dbg_vec_idle;

  for (genvar b = 0; b < Vlen; b++) begin : g_vtap
    for (genvar r = 0; r < Vregs; r++) begin : g_vreg
      assign vpeek[r][b] =
          g_dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_regfile.g_bit[b].bmem[r];
    end
  end

  assign r_fwe    = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_valid;
  assign r_frd    = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_rd;
  assign r_fdata  = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_data;
  assign r_fidle  = g_dut.riscv_pipelined_inst.datapath_inst.fp_idle;
  assign r_flwe   = g_dut.riscv_pipelined_inst.datapath_inst.fp_load_wb;
  assign r_flrd   = g_dut.riscv_pipelined_inst.datapath_inst.rd_wb;
  assign r_fldata = g_dut.riscv_pipelined_inst.datapath_inst.load_data_wb;

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic read_args();
    if (!$value$plusargs("hex=%s", hexfile)) $fatal(1, "cosim needs +hex");
    if (!$value$plusargs("n=%d", max_commits)) max_commits = 4000;
    if (!$value$plusargs("preload_dmem=%d", preload)) preload = 0;
    if (!$value$plusargs("log_traps=%d", log_traps)) log_traps = 0;
    if (!$value$plusargs("stall=%d", stall_pct)) stall_pct = 0;
    if (!$value$plusargs("stall_max=%d", stall_max)) stall_max = 4;
    if (!$value$plusargs("stall_seed=%d", stall_seed)) stall_seed = 1;
    if (!$value$plusargs("irq=%d", irq_rate)) irq_rate = 0;
    if (!$value$plusargs("irq_seed=%d", irq_seed)) irq_seed = 1;
    void'($value$plusargs("max_errors=%d", max_errors));
  endtask  // Automatic

  task automatic open_dump();
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, cosim_bench);
    end
  endtask  // Automatic

  task automatic load_image();
    $readmemh(hexfile, g_dut.imem_inst.mem);
    if ($isunknown(g_dut.imem_inst.mem[0]) || g_dut.imem_inst.mem[0] == '0)
      $fatal(1, "%s missing or empty", hexfile);
    if (preload != 0)
      for (int l = 0; l < Depth / LineWords; l++)
        for (int w = 0; w < LineWords; w++)
          g_dut.dmem_inst.mem[l][Xlen*w+:Xlen] = g_dut.imem_inst.mem[LineWords*l+w];
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic emit_fcommit();
    if (r_fwe) $display("FCOMMIT %0d %08x", r_frd, r_fdata);
    if (r_flwe) $display("FCOMMIT %0d %08x", r_flrd, r_fldata);
  endtask  // Automatic

  // Line per retirement
  task automatic emit_commit();
    logic [AddrW-1:0] rd;
    rd = r_insn[11:7];
    // pc rd rd_val mem_write mem_addr wstrb store_data
    $display("COMMIT %08x %0d %08x %0d %08x %1x %08x %02x %02x %1x %02x", r_pc,
             (r_rw && rd != 0) ? rd : 0, r_wdata, |r_wmask, r_maddr, r_wmask, r_sdata, r_vl,
             r_vtype_bits, r_vtype_ill, r_vstart);
    $display("TRACE %0t %08x %08x", $time, r_pc, r_insn);
    commits++;
  endtask  // Automatic

  // Vector group written
  task automatic emit_vcommit();
    for (int g = 0; g < Vregs; g++)
      if (r_vwregs[g]) $display("VCOMMIT %0d %0d %032x", r_vtag, g, vpeek[g]);
  endtask  // Automatic

  // Interrupt retire count
  task automatic retire_trap();
    logic [1:0] lines;
    if (log_traps != 0) $display("DTRAP %0t %08x %08x", $time, r_pc, r_insn);
    if (dbg_mcause[Xlen-1]) begin
      check("HUNG interrupt retired without a take", irq_lines.size() != 0, 1'b1);
      if (irq_lines.size() != 0) begin
        lines = irq_lines.pop_front();
        $display("IRQ %0d %0d %0d", commits, lines[1], lines[0]);
      end
    end
  endtask  // Automatic

  // Park sentinel stops
  task automatic run_commits(input int cycles);
    logic [Xlen-1:0] last_pc;
    logic            have_last = 1'b0;
    parked = 1'b0;
    for (int i = 0; i < cycles && !parked; i++) begin
      @(negedge clk);
      if (r_vretire) emit_vcommit();
      emit_fcommit();
      if (r_valid && r_trap) retire_trap();
      if (r_valid && !r_trap) begin
        if (have_last && r_pc === last_pc) parked = 1'b1;
        else begin
          emit_commit();
          last_pc   = r_pc;
          have_last = 1'b1;
        end
      end
    end
    check("HUNG no park sentinel", parked, 1'b1);
  endtask  // Automatic

  task automatic drain_units(input int cycles);
    for (int i = 0; i < cycles && !r_vidle; i++) begin
      @(negedge clk);
      if (r_vretire) emit_vcommit();
    end
    check("HUNG vector unit not idle", r_vidle, 1'b1);
    for (int i = 0; i < cycles && !r_fidle; i++) begin
      @(negedge clk);
      emit_fcommit();
    end
    check("HUNG float unit not idle", r_fidle, 1'b1);
  endtask  // Automatic

  task automatic report_state();
    $display("FCSR %02x", {g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.frm, dbg_fflags});
    $display("STALLS %0d %0d", fetch_stalls, data_stalls);
    $display("MONITOR: %0d commits", commits);
  endtask  // Automatic

  // Enabled line ignored
  task automatic check_irq();
    check("IRQ LOST", irq_ready, 1'b0);
  endtask  // Automatic

  // Fence drains unit
  task automatic check_fence();
    check("FENCE BUSY", r_vidle, 1'b1);
  endtask  // Automatic

  // One accept each
  task automatic check_accept();
    check("VEC REISSUE", v_accepted, 1'b0);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  function automatic int draw_wait();
    if (stall_pct == 0) return 0;
    if ($urandom(stall_seed) % 100 >= stall_pct) return 0;
    return 1 + $urandom(stall_seed) % stall_max;
  endfunction

  function automatic logic is_fence(input logic [Xlen-1:0] insn);
    return insn[$bits(opcode_pkg::OpcodeMiscMem)-1:0] == opcode_pkg::OpcodeMiscMem &&
        insn[14:12] == '0;
  endfunction

  initial begin
    read_args();
    open_dump();
    load_image();
    do_reset();
    run_commits(max_commits);
    drain_units(DrainCycles);
    report_state();
    do_verdict();
  end

  assign imem_ready = (fetch_wait == 0);
  assign dmem_ready = (data_wait == 0);

  // Poison until ready
  assign instr = imem_ready ? imem_word : '1;
  assign read_data = dmem_ready ? dmem_line : '1;

  always @(posedge clk) begin
    if (!rst_n) begin
      fetch_wait <= 0;
      data_wait  <= 0;
    end else begin
      if (g_dut.riscv_pipelined_inst.datapath_inst.pc_en) fetch_wait <= draw_wait();
      else if (fetch_wait != 0) begin
        fetch_wait <= fetch_wait - 1;
        fetch_stalls++;
      end
      if (dmem_req && dmem_ready) data_wait <= draw_wait();
      else if (dmem_req && data_wait != 0) begin
        data_wait <= data_wait - 1;
        data_stalls++;
      end
    end
  end

  assign irq_ready = dbg_mstatus[MstatusMie] &&
      ((ext_line && dbg_mie[Meie]) || (timer_line && dbg_mie[Mtie]));
  assign irq_take = irq_ready_q && !dbg_mstatus[MstatusMie] && dbg_mcause[Xlen-1];
  assign irq_ext = dbg_mcause[CauseW-1:0] == CauseMachineExternalIrq;

  always @(posedge clk) begin
    if (!rst_n) begin
      ext_line    <= 1'b0;
      timer_line  <= 1'b0;
      irq_ready_q <= 1'b0;
      ext_q       <= 1'b0;
      timer_q     <= 1'b0;
    end else begin
      irq_ready_q <= irq_ready;
      ext_q       <= ext_line;
      timer_q     <= timer_line;
      if (irq_take) irq_lines.push_back({ext_q, timer_q});
      // Taken line drops
      if (irq_take) begin
        if (irq_ext) ext_line <= 1'b0;
        else timer_line <= 1'b0;
      end else if (irq_rate != 0) begin
        if (!ext_line && $urandom(irq_seed) % 1000 < irq_rate) ext_line <= 1'b1;
        if (!timer_line && $urandom(irq_seed) % 1000 < irq_rate) timer_line <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n || g_dut.riscv_pipelined_inst.datapath_inst.idex_en) v_accepted <= 1'b0;
    else if (g_dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_issue.accept)
      v_accepted <= 1'b1;
  end

  always @(negedge clk) begin
    if (rst_n && dbg_ex_commit) check_irq();
    if (rst_n && dbg_ex_commit && is_fence(dbg_ex_insn)) check_fence();
    if (rst_n && g_dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_issue.accept)
      check_accept();
  end

  // Vector store beats
  always @(negedge clk) begin
    // addr wstrb data
    if (rst_n && dbg_v_take && store_wstrb != '0)
      $display(
          "VMEM %08x %04x %032x",
          mem_addr & ~Xlen'(cache_pkg::LineBytes - 1),
          store_wstrb,
          store_data
      );
  end

endmodule

`default_nettype wire
