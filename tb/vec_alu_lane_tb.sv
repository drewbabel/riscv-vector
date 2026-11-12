`default_nettype none

module vec_alu_lane_tb
  import vec_pkg::*;
();

  localparam int W = arch_pkg::ELEN;
  localparam int SHAMT = $clog2(W);
  localparam int MinChecks = 60000;
  localparam int OpCodes = 2 ** $bits(vec_op_e);
  localparam logic [W-1:0] MinNeg = {1'b1, {(W - 1) {1'b0}}};
  localparam logic [W-1:0] MaxPos = ~MinNeg;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  vec_op_e op;
  logic vm;
  logic mask_bit;
  logic [W-1:0] a;
  logic [W-1:0] b;
  logic [W-1:0] result;

  vec_alu_lane #(
      .W(W)
  ) dut (
      .op(op),
      .vm(vm),
      .mask_bit(mask_bit),
      .a(a),
      .b(b),
      .result(result)
  );

  task automatic check(input string name, input logic [W-1:0] got, input logic [W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic check_case(input logic [W-1:0] a_in, input logic [W-1:0] b_in,
                            input vec_op_e op_in, input logic vm_in, input logic mask_in);
    a = a_in;
    b = b_in;
    op = op_in;
    vm = vm_in;
    mask_bit = mask_in;
    #1;
    check($sformatf("op %0d a=%h b=%h vm=%b m=%b", op_in, a_in, b_in, vm_in, mask_in), result,
          lane_ref(a_in, b_in, op_in, vm_in, mask_in));
  endtask  // Automatic

  task automatic every_op(input logic [W-1:0] x, input logic [W-1:0] y);
    for (int o = 0; o < OpCodes; o++)
      for (int m = 0; m < 4; m++) check_case(x, y, vec_op_e'(o), m[1], m[0]);
  endtask  // Automatic

  task automatic test_directed();
    every_op('0, '0);
    every_op('1, '1);
    every_op(MaxPos, MinNeg);
    every_op(MinNeg, MaxPos);
    every_op(W'(1), '1);
    every_op(MinNeg | W'(1), W'(W - 1));
    every_op(W'('h1234_5678), W'('h8765_4321));
  endtask  // Automatic

  task automatic test_shifts();
    for (int s = 0; s < 2 * W; s++) begin
      check_case(MinNeg | W'('h5A5), W'(s), VEC_SLL, 1'b1, 1'b0);
      check_case(MinNeg | W'('h5A5), W'(s), VEC_SRL, 1'b1, 1'b0);
      check_case(MinNeg | W'('h5A5), W'(s), VEC_SRA, 1'b1, 1'b0);
    end
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n)
      check_case(W'($urandom), W'($urandom), vec_op_e'($urandom_range(OpCodes - 1)), 1'($urandom),
                 1'($urandom));
  endtask  // Automatic

  task automatic near_sweep(input int n);
    logic [W-1:0] x;
    logic [W-1:0] y;
    repeat (n) begin
      x = W'($urandom);
      y = x ^ (W'($urandom) >> $urandom_range(W - 1));
      for (int o = 0; o < OpCodes; o++) check_case(x, y, vec_op_e'(o), 1'($urandom), 1'($urandom));
    end
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
    op = vec_op_e'(0);
    vm = 1'b1;
    mask_bit = 1'b0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("vec_alu_lane_tb.vcd");
    $dumpvars(0, vec_alu_lane_tb);
    do_reset();

    test_directed();
    test_shifts();
    random_sweep(10000);
    near_sweep(400);

    do_verdict();
  end

  // Golden reference
  function automatic logic [W-1:0] lane_ref(input logic [W-1:0] x, input logic [W-1:0] y,
                                            input vec_op_e o, input logic v, input logic m);
    logic sx_lt;
    logic ux_lt;
    sx_lt = $signed(x) < $signed(y);
    ux_lt = x < y;
    case (o)
      VEC_ADD:   return x + y;
      VEC_SUB:   return x - y;
      VEC_RSUB:  return y - x;
      VEC_AND:   return x & y;
      VEC_OR:    return x | y;
      VEC_XOR:   return x ^ y;
      VEC_SLL:   return x << y[SHAMT-1:0];
      VEC_SRL:   return x >> y[SHAMT-1:0];
      VEC_SRA:   return $signed(x) >>> y[SHAMT-1:0];
      VEC_MINU:  return ux_lt ? x : y;
      VEC_MIN:   return sx_lt ? x : y;
      VEC_MAXU:  return (y < x) ? x : y;
      VEC_MAX:   return ($signed(y) < $signed(x)) ? x : y;
      VEC_ADC:   return x + y + W'(m);
      VEC_SBC:   return x - y - W'(m);
      VEC_MERGE: return (v || m) ? y : x;
      VEC_MVNRR: return x;
      default:   return '0;
    endcase
  endfunction

endmodule

`default_nettype wire
