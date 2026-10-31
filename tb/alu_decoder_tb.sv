`default_nettype none

module alu_decoder_tb
  import alu_pkg::*;
();

  localparam int MinChecks = 17;
  localparam int CtrlW = $bits(alu_op_e);
  localparam logic [1:0] AluOpAdd = 2'b00;
  localparam logic [1:0] AluOpBranch = 2'b01;
  localparam logic [1:0] AluOpFunct = 2'b10;
  localparam logic [2:0] Funct3AddSub = 3'b000;
  localparam logic [2:0] Funct3Sll = 3'b001;
  localparam logic [2:0] Funct3Slt = 3'b010;
  localparam logic [2:0] Funct3Sltu = 3'b011;
  localparam logic [2:0] Funct3Xor = 3'b100;
  localparam logic [2:0] Funct3Shr = 3'b101;
  localparam logic [2:0] Funct3Or = 3'b110;
  localparam logic [2:0] Funct3And = 3'b111;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [1:0] alu_op;
  logic [2:0] funct3;
  logic funct7b5;
  logic op5;
  alu_op_e alu_ctrl;

  alu_decoder dut (
      .alu_op  (alu_op),
      .funct3  (funct3),
      .funct7b5(funct7b5),
      .op5     (op5),
      .alu_ctrl(alu_ctrl)
  );

  task automatic check(input string name, input logic [CtrlW-1:0] got, input logic [CtrlW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic decode(input string name, input logic [1:0] op, input logic [2:0] f3,
                        input logic f7b5, input logic o5, input alu_op_e exp);
    alu_op   = op;
    funct3   = f3;
    funct7b5 = f7b5;
    op5      = o5;
    #1;
    check(name, alu_ctrl, exp);
  endtask  // Automatic

  task automatic test_fixed_ops();
    decode("add category", AluOpAdd, Funct3AddSub, 1'b0, 1'b0, ALU_ADD);
    decode("add ignores funct", AluOpAdd, Funct3And, 1'b1, 1'b1, ALU_ADD);
    decode("branch category", AluOpBranch, Funct3AddSub, 1'b0, 1'b0, ALU_SUB);
  endtask  // Automatic

  task automatic test_add_sub();
    decode("add", AluOpFunct, Funct3AddSub, 1'b0, 1'b1, ALU_ADD);
    decode("sub", AluOpFunct, Funct3AddSub, 1'b1, 1'b1, ALU_SUB);
    decode("addi bit30 set", AluOpFunct, Funct3AddSub, 1'b1, 1'b0, ALU_ADD);
    decode("addi", AluOpFunct, Funct3AddSub, 1'b0, 1'b0, ALU_ADD);
  endtask  // Automatic

  task automatic test_logic_ops();
    decode("sll", AluOpFunct, Funct3Sll, 1'b0, 1'b1, ALU_SLL);
    decode("slt", AluOpFunct, Funct3Slt, 1'b0, 1'b1, ALU_SLT);
    decode("sltu", AluOpFunct, Funct3Sltu, 1'b0, 1'b1, ALU_SLTU);
    decode("xor", AluOpFunct, Funct3Xor, 1'b0, 1'b1, ALU_XOR);
    decode("or", AluOpFunct, Funct3Or, 1'b0, 1'b1, ALU_OR);
    decode("and", AluOpFunct, Funct3And, 1'b0, 1'b1, ALU_AND);
  endtask  // Automatic

  task automatic test_shifts();
    decode("srl", AluOpFunct, Funct3Shr, 1'b0, 1'b1, ALU_SRL);
    decode("sra", AluOpFunct, Funct3Shr, 1'b1, 1'b1, ALU_SRA);
    decode("srli", AluOpFunct, Funct3Shr, 1'b0, 1'b0, ALU_SRL);
    decode("srai", AluOpFunct, Funct3Shr, 1'b1, 1'b0, ALU_SRA);
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
    alu_op = '0;
    funct3 = '0;
    funct7b5 = '0;
    op5 = '0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("alu_decoder_tb.vcd");
    $dumpvars(0, alu_decoder_tb);
    do_reset();

    test_fixed_ops();
    test_add_sub();
    test_logic_ops();
    test_shifts();

    do_verdict();
  end

endmodule

`default_nettype wire
