`default_nettype none

module pl_muldiv_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int MaxCycles = 300;
  localparam int MinChecks = 7;
  localparam int HoldCycles = 10;
  localparam logic [Xlen-1:0] Nop = Xlen'(opcode_pkg::OpcodeOpImm);

  int              checks = 0;
  int              errors = 0;
  int              max_errors = 0;

  logic            clk = 1'b0;
  logic            rst_n;
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] alu_result;
  logic [Xlen-1:0] write_data;
  logic            mem_write;

  int              hold_run = 0;
  logic [Xlen-1:0] drain_x10;
  logic [Xlen-1:0] drain_x11;
  logic            drain_seen = 1'b0;

  always #5 clk = ~clk;

  top #(
      .XLEN(Xlen)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .pc        (pc),
      .alu_result(alu_result),
      .write_data(write_data),
      .mem_write (mem_write)
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

  task automatic run(input int cycles);
    repeat (cycles) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic check_reg(input logic [AWIDTH-1:0] r, input logic [Xlen-1:0] exp);
    check($sformatf("x%0d", r), dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[r],
          exp);
  endtask  // Automatic

  task automatic check_mul();
    check_reg(AWIDTH'(3), Xlen'(42));
  endtask  // Automatic

  task automatic check_div();
    check_reg(AWIDTH'(6), Xlen'(6));
    check_reg(AWIDTH'(7), Xlen'(2));
    check_reg(AWIDTH'(9), Xlen'(-6));
  endtask  // Automatic

  task automatic check_drain();
    check("drain seen", Xlen'(drain_seen), Xlen'(1));
    check("x10 drained", drain_x10, Xlen'(99));
    check("x11 drained", drain_x11, Xlen'(88));
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
    $dumpfile("pl_muldiv_tb.vcd");
    $dumpvars(0, pl_muldiv_tb);
    load_image("tests/pl_muldiv.hex");
    do_reset();
    run(MaxCycles);
    check_mul();
    check_div();
    check_drain();
    do_verdict();
  end

  // Older instructions retire while divide holds EX
  always @(negedge clk) begin
    if (dut.riscv_pipelined_inst.datapath_inst.muldiv_hold) hold_run = hold_run + 1;
    else hold_run = 0;
    if (hold_run == HoldCycles && !drain_seen) begin
      drain_seen = 1'b1;
      drain_x10  = dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[10];
      drain_x11  = dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[11];
    end
  end

endmodule

`default_nettype wire
