`default_nettype none

`ifndef COSIM_DEPTH
`define COSIM_DEPTH 256
`endif

module cosim ();

  int checks = 0;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Vlen = arch_pkg::VLEN;
  localparam int Vregs = arch_pkg::NumRegs;
  localparam int VlW = $clog2(Vlen + 1);
  localparam int VstartW = $clog2(Vlen);
  localparam int Depth = `COSIM_DEPTH;

  logic             clk = 1'b0;
  logic             rst_n;
  logic  [Xlen-1:0] pc;
  logic  [Xlen-1:0] alu_result;
  logic  [Xlen-1:0] write_data;
  logic             mem_write;

  string            hexfile;
  string            vcdfile;
  int               max_commits;

  always #5 clk = ~clk;

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
  logic   [                     4:0] dbg_fflags;
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

  function automatic int draw_wait();
    if (stall_pct == 0) return 0;
    if ($urandom(stall_seed) % 100 >= stall_pct) return 0;
    return 1 + $urandom(stall_seed) % stall_max;
  endfunction

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

  // Random interrupt lines
  integer irq_seed;
  int     irq_rate;
  logic   ext_line;
  logic   timer_line;
  logic   trap_irq;
  int     trap_kinds [$];

  assign trap_irq = g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.trap_taken &&
      !(g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.illegal_any ||
        g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.exc_ecall ||
        g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.exc_ebreak ||
        g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.exc_instr_misaligned ||
        g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.exc_load_misaligned ||
        g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.exc_store_misaligned);

  always @(posedge clk) begin
    if (!rst_n) begin
      ext_line   <= 1'b0;
      timer_line <= 1'b0;
    end else begin
      if (g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.trap_taken)
        trap_kinds.push_back(trap_irq ? {29'd0, 1'b1, ext_line, timer_line} : 0);
      // Enabled line ignored
      if (dbg_ex_commit && dbg_mstatus[3] &&
          ((ext_line && dbg_mie[11]) || (timer_line && dbg_mie[7])))
        $display("IRQ LOST %0t ext %0d timer %0d", $time, ext_line, timer_line);
      // Taken line drops
      if (trap_irq) begin
        if (g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.ext_ready) ext_line <= 1'b0;
        else timer_line <= 1'b0;
      end else if (irq_rate != 0) begin
        if (!ext_line && $urandom(irq_seed) % 1000 < irq_rate) ext_line <= 1'b1;
        if (!timer_line && $urandom(irq_seed) % 1000 < irq_rate) timer_line <= 1'b1;
      end
    end
  end

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

  // RVFI retirement taps
  logic               r_valid;
  logic               r_trap;
  logic [   Xlen-1:0] r_pc;
  logic [   Xlen-1:0] r_insn;
  logic [   Xlen-1:0] r_wdata;
  logic               r_rw;
  logic [   Xlen-1:0] r_maddr;
  logic [ Xlen/8-1:0] r_wmask;
  logic [   Xlen-1:0] r_sdata;
  logic [    VlW-1:0] r_vl;
  logic [        7:0] r_vtype_bits;
  logic               r_vtype_ill;
  logic [VstartW-1:0] r_vstart;
  assign r_valid = dbg_valid;
  assign r_trap = dbg_trap;
  assign r_pc    = dbg_pc_rdata;
  assign r_insn  = dbg_insn;
  assign r_wdata = dbg_rd_wdata;
  assign r_rw    = dbg_reg_write;
  assign r_maddr = dbg_mem_addr;
  assign r_wmask = dbg_mem_wmask;
  assign r_sdata = dbg_mem_wdata;
  assign r_vl = dbg_vl;
  assign r_vtype_bits = dbg_vtype_bits;
  assign r_vtype_ill = dbg_vtype_ill;
  assign r_vstart = dbg_vstart;

  // Vector retirement taps
  logic [      7:0] r_vtag;
  logic             r_vretire;
  logic [Vregs-1:0] r_vwregs;
  logic             r_vidle;
  logic [ Vlen-1:0] vpeek     [Vregs];

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

  // Vector store beats
  logic                            r_vmreq;
  logic                            r_vmready;
  logic [                Xlen-1:0] r_vmaddr;
  logic [ cache_pkg::LineBits-1:0] r_vmdata;
  logic [cache_pkg::LineBytes-1:0] r_vmstrb;

  assign r_vmreq   = g_dut.riscv_pipelined_inst.v_req;
  assign r_vmready = g_dut.riscv_pipelined_inst.v_ready;
  assign r_vmaddr  = g_dut.riscv_pipelined_inst.v_addr;
  assign r_vmdata  = g_dut.riscv_pipelined_inst.v_wdata;
  assign r_vmstrb  = g_dut.riscv_pipelined_inst.v_wstrb;

  always @(negedge clk) begin
    // addr wstrb data
    if (rst_n && r_vmreq && r_vmready && r_vmstrb != '0)
      $display(
          "VMEM %08x %04x %032x", r_vmaddr & ~Xlen'(cache_pkg::LineBytes - 1), r_vmstrb, r_vmdata
      );
  end

  // Fence drains unit
  always @(negedge clk) begin
    if (rst_n && g_dut.riscv_pipelined_inst.datapath_inst.commit_valid &&
        g_dut.riscv_pipelined_inst.datapath_inst.is_fence_ex && !r_vidle)
      $display("FENCE BUSY %0t", $time);
  end

  // One accept each
  logic v_accepted = 1'b0;
  always @(posedge clk) begin
    if (rst_n && g_dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_issue.accept &&
        v_accepted)
      $display("VEC REISSUE %0t", $time);
    if (!rst_n || g_dut.riscv_pipelined_inst.datapath_inst.idex_en) v_accepted <= 1'b0;
    else if (g_dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_issue.accept)
      v_accepted <= 1'b1;
  end

  logic        r_fwe;
  logic [ 4:0] r_frd;
  logic [31:0] r_fdata;
  logic        r_fidle;
  logic        r_flwe;
  logic [ 4:0] r_flrd;
  logic [31:0] r_fldata;
  assign r_fwe    = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_valid;
  assign r_frd    = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_rd;
  assign r_fdata  = g_dut.riscv_pipelined_inst.datapath_inst.fp_wb_data;
  assign r_fidle  = g_dut.riscv_pipelined_inst.datapath_inst.fp_idle;
  assign r_flwe   = g_dut.riscv_pipelined_inst.datapath_inst.fp_load_wb;
  assign r_flrd   = g_dut.riscv_pipelined_inst.datapath_inst.rd_wb;
  assign r_fldata = g_dut.riscv_pipelined_inst.datapath_inst.load_data_wb;

  task automatic emit_fcommit();
    if (r_fwe) $display("FCOMMIT %0d %08x", r_frd, r_fdata);
    if (r_flwe) $display("FCOMMIT %0d %08x", r_flrd, r_fldata);
  endtask

  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
  endtask  // Automatic

  // Line per retirement
  task automatic emit_commit();
    logic [4:0] rd;
    rd = r_insn[11:7];
    // pc rd rd_val mem_write mem_addr wstrb store_data
    $display("COMMIT %08x %0d %08x %0d %08x %1x %08x %02x %02x %1x %02x", r_pc,
             (r_rw && rd != 0) ? rd : 0, r_wdata, |r_wmask, r_maddr, r_wmask, r_sdata, r_vl,
             r_vtype_bits, r_vtype_ill, r_vstart);
    $display("TRACE %0t %08x %08x", $time, r_pc, r_insn);
    checks++;
  endtask  // Automatic

  // Vector group written
  task automatic emit_vcommit();
    begin
      for (int g = 0; g < Vregs; g++)
      if (r_vwregs[g]) $display("VCOMMIT %0d %0d %032x", r_vtag, g, vpeek[g]);
    end
  endtask

  initial begin
    logic [Xlen-1:0] last_pc;
    logic            have_last;
    logic            stop;
    int              log_traps;
    int              preload;
    int              kind;

    if (!$value$plusargs("hex=%s", hexfile)) $fatal(1, "cosim needs +hex");
    if (!$value$plusargs("n=%d", max_commits)) max_commits = 4000;
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, cosim);
    end

    $readmemh(hexfile, g_dut.imem_inst.mem);
    if ($isunknown(g_dut.imem_inst.mem[0]) || g_dut.imem_inst.mem[0] == 32'h0)
      $fatal(1, "%s missing or empty", hexfile);
    if (!$value$plusargs("preload_dmem=%d", preload)) preload = 0;
    if (!$value$plusargs("log_traps=%d", log_traps)) log_traps = 0;
    if (!$value$plusargs("stall=%d", stall_pct)) stall_pct = 0;
    if (!$value$plusargs("stall_max=%d", stall_max)) stall_max = 4;
    if (!$value$plusargs("stall_seed=%d", stall_seed)) stall_seed = 1;
    if (!$value$plusargs("irq=%d", irq_rate)) irq_rate = 0;
    if (!$value$plusargs("irq_seed=%d", irq_seed)) irq_seed = 1;
    if (preload != 0)
      for (int l = 0; l < Depth / 4; l++)
      g_dut.dmem_inst.mem[l] = {
        g_dut.imem_inst.mem[4*l+3],
        g_dut.imem_inst.mem[4*l+2],
        g_dut.imem_inst.mem[4*l+1],
        g_dut.imem_inst.mem[4*l]
      };
    do_reset();

    // Park sentinel stops
    have_last = 0;
    stop      = 0;
    for (int i = 0; i < max_commits && !stop; i++) begin
      @(posedge clk);
      #1;
      if (r_vretire) emit_vcommit();
      emit_fcommit();
      if ((log_traps != 0) && r_valid && r_trap)
        $display("DTRAP %0t %08x %08x", $time, r_pc, r_insn);
      // Retired count at interrupt
      if (r_valid && r_trap) begin
        if (trap_kinds.size() == 0) $display("HUNG trap retired without a taken trap");
        else begin
          kind = trap_kinds.pop_front();
          if (kind[2]) $display("IRQ %0d %0d %0d", checks, kind[1], kind[0]);
        end
      end
      // Spike skips traps
      if (r_valid && !r_trap) begin
        if (have_last && r_pc === last_pc) stop = 1;
        else begin
          emit_commit();
          last_pc   = r_pc;
          have_last = 1;
        end
      end
    end

    if (!stop) $display("HUNG no park sentinel after %0d cycles", max_commits);

    // Drain the unit
    for (int i = 0; i < 2000 && !r_vidle; i++) begin
      @(posedge clk);
      #1;
      if (r_vretire) emit_vcommit();
    end
    if (!r_vidle) $display("HUNG vector unit not idle");

    for (int i = 0; i < 2000 && !r_fidle; i++) begin
      @(posedge clk);
      #1;
      emit_fcommit();
    end
    if (!r_fidle) $display("HUNG float unit not idle");
    $display("FCSR %02x", {g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.frm,
                           g_dut.riscv_pipelined_inst.datapath_inst.csr_inst.fflags});

    $display("STALLS %0d %0d", fetch_stalls, data_stalls);
    $display("MONITOR: %0d commits", checks);
    $finish;
  end

endmodule

`default_nettype wire
