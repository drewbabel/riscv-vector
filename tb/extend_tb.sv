`default_nettype none

module extend_tb;

  localparam int MinChecks = 7;
  localparam int Xlen = arch_pkg::XLEN;
  localparam logic [2:0] ImmI = 3'd0;
  localparam logic [2:0] ImmS = 3'd1;
  localparam logic [2:0] ImmB = 3'd2;
  localparam logic [2:0] ImmU = 3'd3;
  localparam logic [2:0] ImmJ = 3'd4;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [31:0] instr;
  logic [2:0] imm_src;
  logic [Xlen-1:0] imm_ext;

  extend #(
      .XLEN(Xlen)
  ) dut (
      .instr  (instr),
      .imm_src(imm_src),
      .imm_ext(imm_ext)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic extend_imm(input string name, input logic [31:0] in, input logic [2:0] src,
                            input logic [Xlen-1:0] exp);
    instr   = in;
    imm_src = src;
    #1;
    check(name, imm_ext, exp);
  endtask  // Automatic

  task automatic test_golden();
    extend_imm("I neg addi -4", 32'hffc00093, ImmI, Xlen'(-4));
    extend_imm("I pos addi 5", 32'h00500113, ImmI, Xlen'(5));
    extend_imm("S neg sw -8", 32'hfe322c23, ImmS, Xlen'(-8));
    extend_imm("B neg beq -16", 32'hfe6288e3, ImmB, Xlen'(-16));
    extend_imm("U lui 0x12345", 32'h123453b7, ImmU, Xlen'('h12345000));
    extend_imm("J pos jal +16", 32'h0100046f, ImmJ, Xlen'(16));
    extend_imm("J neg jal -8", 32'hff9ff4ef, ImmJ, Xlen'(-8));
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic do_reset();
    instr   = '0;
    imm_src = '0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("extend_tb.vcd");
    $dumpvars(0, extend_tb);
    do_reset();

    test_golden();

    do_verdict();
  end

endmodule

`default_nettype wire
