`default_nettype none

module cosim ();

  int checks = 0;

  localparam int Xlen = 32;
  localparam int Depth = 64;

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

  top #(
      .XLEN (Xlen),
      .DEPTH(Depth)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .pc        (pc),
      .alu_result(alu_result),
      .write_data(write_data),
      .mem_write (mem_write)
  );

  // RVFI retirement taps
  logic            r_valid;
  logic [Xlen-1:0] r_pc;
  logic [Xlen-1:0] r_insn;
  logic [Xlen-1:0] r_wdata;
  logic            r_rw;
  logic [Xlen-1:0] r_maddr;
  logic [     3:0] r_wmask;
  logic [Xlen-1:0] r_sdata;
  logic [     7:0] r_vl;
  logic [     7:0] r_vtype_bits;
  logic            r_vtype_ill;
  logic [     6:0] r_vstart;
  assign r_valid = dut.riscv_pipelined_inst.dbg_valid;
  assign r_pc    = dut.riscv_pipelined_inst.dbg_pc_rdata;
  assign r_insn  = dut.riscv_pipelined_inst.dbg_insn;
  assign r_wdata = dut.riscv_pipelined_inst.dbg_rd_wdata;
  assign r_rw    = dut.riscv_pipelined_inst.dbg_reg_write;
  assign r_maddr = dut.riscv_pipelined_inst.dbg_mem_addr;
  assign r_wmask = dut.riscv_pipelined_inst.dbg_mem_wmask;
  assign r_sdata = dut.riscv_pipelined_inst.dbg_mem_wdata;
  assign r_vl = dut.riscv_pipelined_inst.dbg_vl;
  assign r_vtype_bits = dut.riscv_pipelined_inst.dbg_vtype_bits;
  assign r_vtype_ill = dut.riscv_pipelined_inst.dbg_vtype_ill;
  assign r_vstart = dut.riscv_pipelined_inst.dbg_vstart;

  // Vector retirement taps
  localparam int Vlen = 128;
  localparam int Vregs = 32;

  logic [     7:0] r_vtag;
  logic            r_vretire;
  logic [     4:0] r_vvd;
  logic [     3:0] r_vregs;
  logic            r_vidle;
  logic [Vlen-1:0] vpeek     [Vregs];

  assign r_vtag = dut.riscv_pipelined_inst.dbg_vec_tag;
  assign r_vretire = dut.riscv_pipelined_inst.dbg_vec_retire;
  assign r_vvd = dut.riscv_pipelined_inst.dbg_vec_vd;
  assign r_vregs = dut.riscv_pipelined_inst.dbg_vec_regs;
  assign r_vidle = dut.riscv_pipelined_inst.dbg_vec_idle;

  for (genvar b = 0; b < Vlen; b++) begin : g_vtap
    for (genvar r = 0; r < Vregs; r++) begin : g_vreg
      assign vpeek[r][b] =
          dut.riscv_pipelined_inst.datapath_inst.vec_unit_inst.u_regfile.g_bit[b].bmem[r];
    end
  end

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
    // time pc insn
    $display("TRACE %0t %08x %08x", $time, r_pc, r_insn);
    checks++;
  endtask  // Automatic

  // Vector group written
  task automatic emit_vcommit();
    int base;
    begin
      base = int'(r_vvd);
      for (int g = 0; g < int'(r_vregs); g++)
      $display("VCOMMIT %0d %0d %032x", r_vtag, (base + g) % Vregs, vpeek[(base+g)%Vregs]);
    end
  endtask

  initial begin
    logic [Xlen-1:0] last_pc;
    logic            have_last;
    logic            stop;

    if (!$value$plusargs("hex=%s", hexfile)) $fatal(1, "cosim needs +hex");
    if (!$value$plusargs("n=%d", max_commits)) max_commits = 4000;
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, cosim);
    end

    $readmemh(hexfile, dut.imem_inst.mem);
    if ($isunknown(dut.imem_inst.mem[0]) || dut.imem_inst.mem[0] == 32'h0)
      $fatal(1, "%s missing or empty", hexfile);
    do_reset();

    // Park sentinel stops
    have_last = 0;
    stop      = 0;
    for (int i = 0; i < max_commits && !stop; i++) begin
      @(posedge clk);
      #1;
      if (r_vretire) emit_vcommit();
      if (r_valid) begin
        if (have_last && r_pc === last_pc) stop = 1;
        else begin
          emit_commit();
          last_pc   = r_pc;
          have_last = 1;
        end
      end
    end

    // Drain the unit
    for (int i = 0; i < 2000 && !r_vidle; i++) begin
      @(posedge clk);
      #1;
      if (r_vretire) emit_vcommit();
    end

    $display("MONITOR: %0d commits", checks);
    $finish;
  end

endmodule

`default_nettype wire
