`default_nettype none

module predict_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int MaxCycles = 400;
  localparam int MinChecks = 5;
  localparam logic [Xlen-1:0] Nop = Xlen'(opcode_pkg::OpcodeOpImm);

  int              checks = 0;
  int              errors = 0;
  int              max_errors = 0;
  int              branches = 0;
  int              mispredicts = 0;
  int              taken = 0;

  logic            clk = 1'b0;
  logic            rst_n;
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] alu_result;
  logic [Xlen-1:0] write_data;
  logic            mem_write;
  logic            last_taken = 1'b0;
  logic            core_branch;
  logic            core_taken_ex;
  logic            core_mispred;

  always #5 clk = ~clk;

  top #(
      .XLEN(Xlen)
  ) dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .pc              (pc),
      .alu_result      (alu_result),
      .write_data      (write_data),
      .mem_write       (mem_write),
      .sim_branch      (core_branch),
      .sim_branch_taken(core_taken_ex),
      .sim_mispredict  (core_mispred),
      .sim_muldiv_hold ()
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic load_image(input string path);
    for (int i = 0; i < $size(dut.imem_inst.mem); i++) dut.imem_inst.mem[i] = Nop;
    $readmemh(path, dut.imem_inst.mem);
  endtask  // Automatic

  task automatic run_to_sentinel();
    int cycles = 0;
    while (dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[28] !== Xlen'(1) &&
           cycles < MaxCycles) begin
      @(posedge clk);
      cycles++;
    end
    @(negedge clk);
  endtask  // Automatic

  task automatic check_reg(input logic [AWIDTH-1:0] r, input logic [Xlen-1:0] exp);
    check($sformatf("x%0d", r), dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[r],
          exp);
  endtask  // Automatic

  task automatic check_registers();
    check_reg(AWIDTH'(1), Xlen'(190));
    check_reg(AWIDTH'(28), Xlen'(1));
  endtask  // Automatic

  task automatic check_branches();
    check("branches", Xlen'(branches), Xlen'(20));
    check("taken", Xlen'(taken), Xlen'(19));
    check("last taken", Xlen'(last_taken), Xlen'(0));
  endtask  // Automatic

  task automatic report_rate();
    $display("branches=%0d mispredicts=%0d rate=%0d%%", branches, mispredicts,
             (branches == 0) ? 0 : (100 * mispredicts) / branches);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    load_image("tests/pl_predict.hex");
    do_reset();
    run_to_sentinel();

    check_registers();
    check_branches();
    report_rate();
    do_verdict();
  end

  always @(posedge clk) begin
    if (rst_n && core_branch) begin
      branches++;
      if (core_taken_ex) taken++;
      last_taken = core_taken_ex;
      if (core_mispred) mispredicts++;
    end
  end

endmodule

`default_nettype wire
