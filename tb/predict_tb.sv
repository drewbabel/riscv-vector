`default_nettype none

module predict_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Depth = 64;
  localparam int MaxCycles = 400;

  logic            clk = 1'b0;
  logic            rst_n;
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] alu_result;
  logic [Xlen-1:0] write_data;
  logic            mem_write;

  int              branches = 0;
  int              mispredicts = 0;
  int              taken = 0;
  logic            last_taken = 1'b0;

  int              checks = 0;
  int              errors = 0;

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

  // Resolve taps
  logic core_valid_ex, core_branch_ex, core_taken_ex, core_mispred;
  assign core_valid_ex  = dut.riscv_pipelined_inst.datapath_inst.valid_ex;
  assign core_branch_ex = dut.riscv_pipelined_inst.datapath_inst.branch_ex;
  assign core_taken_ex  = dut.riscv_pipelined_inst.datapath_inst.branch_taken_ex;
  assign core_mispred   = dut.riscv_pipelined_inst.datapath_inst.mispredict;

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      $error("%s = %0d, expected %0d", name, got, exp);
      errors++;
    end
  endtask

  task automatic load_program();
    for (int i = 0; i < Depth; i++) dut.imem_inst.mem[i] = 32'h00000013;  // NOP fill
    $readmemh("tests/pl_predict.hex", dut.imem_inst.mem);
  endtask

  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic run_to_sentinel();
    int cycles = 0;
    while (dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[28] !== 32'd1 &&
           cycles < MaxCycles) begin
      @(posedge clk);
      cycles++;
    end
  endtask

  task automatic check_registers();
    check("x1", dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[1], 32'd190);
    check("x28", dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[28], 32'd1);
  endtask

  task automatic check_branches();
    check("branches", branches, 32'd20);
    check("taken", taken, 32'd19);
    check("last taken", 32'(last_taken), 32'd0);
  endtask

  task automatic report_rate();
    $display("branches=%0d mispredicts=%0d rate=%0d%%", branches, mispredicts,
             (branches == 0) ? 0 : (100 * mispredicts) / branches);
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  always @(posedge clk) begin
    if (rst_n && core_valid_ex && core_branch_ex) begin
      branches++;
      if (core_taken_ex) taken++;
      last_taken = core_taken_ex;
      if (core_mispred) mispredicts++;
    end
  end

  initial begin
    // Run to sentinel
    load_program();
    do_reset();
    run_to_sentinel();

    // Loop results
    check_registers();

    // Branch resolutions
    check_branches();

    report_rate();
    verdict();
  end

endmodule

`default_nettype wire
