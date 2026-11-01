`default_nettype none

module alu_tb
  import alu_pkg::*;
();

  localparam int MinChecks = 12000;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int SHAMT = $clog2(XLEN);
  localparam logic [XLEN-1:0] MinNeg = {1'b1, {(XLEN - 1) {1'b0}}};
  localparam logic [XLEN-1:0] MaxPos = ~MinNeg;
  localparam logic [XLEN-1:0] Pattern = XLEN'('h1234_5678);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [XLEN-1:0] a;
  logic [XLEN-1:0] b;
  alu_op_e alu_op;
  logic [XLEN-1:0] result;
  logic zero;
  logic lt;
  logic ltu;

  alu #(
      .XLEN(XLEN)
  ) dut (
      .a(a),
      .b(b),
      .alu_op(alu_op),
      .result(result),
      .zero(zero),
      .lt(lt),
      .ltu(ltu)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic check_case(input logic [XLEN-1:0] a_in, input logic [XLEN-1:0] b_in,
                            input alu_op_e op_in);
    logic [XLEN-1:0] exp;
    string tag;
    a = a_in;
    b = b_in;
    alu_op = op_in;
    #1;
    exp = alu_ref(a_in, b_in, op_in);
    tag = $sformatf("%s a=%h b=%h", op_in.name(), a_in, b_in);
    check({tag, " result"}, result, exp);
    check({tag, " zero"}, XLEN'(zero), XLEN'(exp == '0));
    check({tag, " lt"}, XLEN'(lt), XLEN'(lt_ref(a_in, b_in, op_in, exp)));
    check({tag, " ltu"}, XLEN'(ltu), XLEN'(ltu_ref(a_in, b_in, op_in, exp)));
  endtask  // Automatic

  task automatic test_directed();
    check_case('0, '0, ALU_ADD);
    check_case('1, '1, ALU_AND);
    check_case(Pattern, Pattern, ALU_SUB);
    check_case(Pattern, XLEN'(1), ALU_ADD);
    check_case(XLEN'(1), '0, ALU_SLL);
    check_case(Pattern, XLEN'(XLEN - 1), ALU_SLL);
    check_case(Pattern, ~XLEN'('hFA), ALU_SLL);
    check_case(MinNeg | XLEN'(1), XLEN'(4), ALU_SRA);
    check_case(MinNeg | XLEN'(1), XLEN'(4), ALU_SRL);
    check_case(MaxPos, MinNeg, ALU_SLT);
    check_case(MaxPos, MinNeg, ALU_SLTU);
    check_case(Pattern, '0, ALU_OR);
    check_case('1, '0, ALU_OR);
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n)
      check_case(XLEN'($urandom), XLEN'($urandom), alu_op_e'($urandom_range(int'(ALU_AND))));
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
    a = '0;
    b = '0;
    alu_op = alu_pkg::alu_op_e'(0);
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("alu_tb.vcd");
    $dumpvars(0, alu_tb);
    do_reset();

    test_directed();
    random_sweep(3000);

    do_verdict();
  end

  // Golden reference
  function automatic logic [XLEN-1:0] alu_ref(input logic [XLEN-1:0] x, input logic [XLEN-1:0] y,
                                              input alu_op_e op);
    case (op)
      ALU_ADD:  return x + y;
      ALU_SUB:  return x - y;
      ALU_SLL:  return x << y[SHAMT-1:0];
      ALU_SLT:  return XLEN'($signed(x) < $signed(y));
      ALU_SLTU: return XLEN'(x < y);
      ALU_XOR:  return x ^ y;
      ALU_SRL:  return x >> y[SHAMT-1:0];
      ALU_SRA:  return $signed(x) >>> y[SHAMT-1:0];
      ALU_OR:   return x | y;
      ALU_AND:  return x & y;
      default:  return '0;
    endcase
  endfunction

  function automatic logic lt_ref(input logic [XLEN-1:0] x, input logic [XLEN-1:0] y,
                                  input alu_op_e op, input logic [XLEN-1:0] exp);
    return (op == ALU_SLT) ? exp[0] : ($signed(x) < $signed(y));
  endfunction

  function automatic logic ltu_ref(input logic [XLEN-1:0] x, input logic [XLEN-1:0] y,
                                   input alu_op_e op, input logic [XLEN-1:0] exp);
    return (op == ALU_SLTU) ? exp[0] : (x < y);
  endfunction

endmodule

`default_nettype wire
