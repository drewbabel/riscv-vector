`default_nettype none

module vec_mul_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Latency = 1;
  localparam int ProdW = 2 * ELEN;
  localparam int MinChecks = 92000;
  localparam int MinHold = 19000;
  localparam int MixN = 20000;
  localparam int SweepN = 250;

  localparam logic [2:0] SEW8 = 3'b000;
  localparam logic [2:0] SEW16 = 3'b001;
  localparam logic [2:0] SEW32 = 3'b010;
  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));

  int checks = 0;
  int hold_checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic stalling = 1'b0;

  logic clk = 1'b0;
  logic core_en;
  vec_op_e op;
  logic [2:0] vsew;
  logic [ELEN-1:0] a;
  logic [ELEN-1:0] b;
  logic [ELEN-1:0] c;
  logic [ELEN-1:0] result;
  logic [2*ELEN-1:0] product;

  vec_op_e ops[15] = '{
      VEC_MUL,
      VEC_MULH,
      VEC_MULHU,
      VEC_MULHSU,
      VEC_MACC,
      VEC_NMSAC,
      VEC_MADD,
      VEC_NMSUB,
      VEC_WMUL,
      VEC_WMULU,
      VEC_WMULSU,
      VEC_WMACC,
      VEC_WMACCU,
      VEC_WMACCSU,
      VEC_WMACCUS
  };

  logic pend_valid[$];
  string pend_name[$];
  logic [ELEN-1:0] pend_result[$];
  logic [2*ELEN-1:0] pend_product[$];

  always #5 clk = ~clk;

  vec_mul_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .product(product)
  );

  task automatic check(input string name, input logic [2*ELEN-1:0] got,
                       input logic [2*ELEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    core_en = 1'b1;
    op      = VEC_MUL;
    vsew    = SEW8;
    a       = '0;
    b       = '0;
    c       = '0;
  endtask  // Automatic

  task automatic retire();
    logic valid;
    string name;
    logic [ELEN-1:0] exp_result;
    logic [2*ELEN-1:0] exp_product;
    if (pend_valid.size() < Latency) return;
    valid = pend_valid.pop_front();
    name = pend_name.pop_front();
    exp_result = pend_result.pop_front();
    exp_product = pend_product.pop_front();
    if (!valid) return;
    check({name, " result"}, ProdW'(result), ProdW'(exp_result));
    check({name, " product"}, product, exp_product);
  endtask  // Automatic

  // Clock enable drops
  task automatic stall();
    logic [  ELEN-1:0] held_result;
    logic [2*ELEN-1:0] held_product;
    while (stalling && 1'($urandom)) begin
      held_result = result;
      held_product = product;
      core_en = 1'b0;
      op = ops[$urandom_range($size(ops)-1)];
      vsew = 3'($urandom);
      a = rand_elem();
      b = rand_elem();
      c = rand_elem();
      @(negedge clk);
      hold_checks++;
      check("held result", ProdW'(result), ProdW'(held_result));
      check("held product", product, held_product);
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic issue(input logic valid, input vec_op_e op_in, input logic [2:0] vsew_in,
                       input logic [ELEN-1:0] a_in, input logic [ELEN-1:0] b_in,
                       input logic [ELEN-1:0] c_in);
    logic [2*ELEN-1:0] exp_product;
    @(negedge clk);
    retire();
    stall();
    exp_product = product_ref(op_in, vsew_in, a_in, b_in);
    op = op_in;
    vsew = vsew_in;
    a = a_in;
    b = b_in;
    c = c_in;
    pend_valid.push_back(valid);
    pend_name.push_back($sformatf(
                        "op=%s vsew=%b a=%h b=%h c=%h", op_in.name(), vsew_in, a_in, b_in, c_in));
    pend_result.push_back(result_ref(op_in, vsew_in, exp_product, c_in));
    pend_product.push_back(exp_product);
  endtask  // Automatic

  task automatic mac(input vec_op_e op_in, input logic [2:0] vsew_in, input logic [ELEN-1:0] a_in,
                     input logic [ELEN-1:0] b_in, input logic [ELEN-1:0] c_in);
    issue(1'b1, op_in, vsew_in, a_in, b_in, c_in);
  endtask  // Automatic

  task automatic mul(input vec_op_e op_in, input logic [2:0] vsew_in, input logic [ELEN-1:0] a_in,
                     input logic [ELEN-1:0] b_in);
    mac(op_in, vsew_in, a_in, b_in, rand_elem());
  endtask  // Automatic

  task automatic drain();
    repeat (Latency) issue(1'b0, VEC_MUL, SEW8, '0, '0, '0);
  endtask  // Automatic

  // Directed cases
  task automatic test_directed();
    mul(VEC_MUL, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_0003));
    mul(VEC_MULH, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FF));
    mul(VEC_MULHU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_0002));
    mul(VEC_MULHSU, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_0002));

    mul(VEC_MUL, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_0003));
    mul(VEC_MULH, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFF));
    mul(VEC_MULHU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_0002));
    mul(VEC_MULHSU, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_0002));

    mul(VEC_MUL, SEW32, ELEN'('hFFFF_FFFE), ELEN'('h0000_0003));
    mul(VEC_MULH, SEW32, ELEN'('hFFFF_FFFF), ELEN'('hFFFF_FFFF));
    mul(VEC_MULHU, SEW32, ELEN'('hFFFF_FFFF), ELEN'('h0000_0002));
    mul(VEC_MULHSU, SEW32, ELEN'('hFFFF_FFFE), ELEN'('h0000_0002));
  endtask  // Automatic

  // Sign corners
  task automatic test_sign_corners();
    mul(VEC_MULH, SEW8, ELEN'('h0000_0080), ELEN'('h0000_0080));
    mul(VEC_MULHSU, SEW8, ELEN'('h0000_0080), ELEN'('h0000_00FF));
    mul(VEC_MULHU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FF));

    mul(VEC_MULH, SEW16, ELEN'('h0000_8000), ELEN'('h0000_8000));
    mul(VEC_MULHSU, SEW16, ELEN'('h0000_8000), ELEN'('h0000_FFFF));
    mul(VEC_MULHU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFF));

    mul(VEC_MULH, SEW32, ELEN'('h8000_0000), ELEN'('h8000_0000));
    mul(VEC_MULHSU, SEW32, ELEN'('h8000_0000), ELEN'('hFFFF_FFFF));
    mul(VEC_MULHU, SEW32, ELEN'('hFFFF_FFFF), ELEN'('hFFFF_FFFF));
  endtask  // Automatic

  // Widening sign corners
  task automatic test_widen_corners();
    mul(VEC_WMUL, SEW8, ELEN'('h0000_0080), ELEN'('h0000_0080));
    mul(VEC_WMULU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FF));
    mul(VEC_WMULSU, SEW8, ELEN'('h0000_0080), ELEN'('h0000_00FF));

    mul(VEC_WMUL, SEW16, ELEN'('h0000_8000), ELEN'('h0000_8000));
    mul(VEC_WMULU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFF));
    mul(VEC_WMULSU, SEW16, ELEN'('h0000_8000), ELEN'('h0000_FFFF));
  endtask  // Automatic

  // Widening directed cases
  task automatic test_widen_directed();
    mul(VEC_WMUL, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_0003));
    mul(VEC_WMULU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_0002));
    mul(VEC_WMULSU, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_00FF));

    mul(VEC_WMUL, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_0003));
    mul(VEC_WMULU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_0002));
    mul(VEC_WMULSU, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_FFFF));
  endtask  // Automatic

  // Accumulate sign corners
  task automatic test_acc_corners();
    mac(VEC_WMACC, SEW8, ELEN'('h0000_0080), ELEN'('h0000_0080), ELEN'('h0000_0001));
    mac(VEC_WMACCU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FF), ELEN'('h0000_0001));
    mac(VEC_WMACCSU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_0080), ELEN'('h0000_0001));
    mac(VEC_WMACCUS, SEW8, ELEN'('h0000_0080), ELEN'('h0000_00FF), ELEN'('h0000_0001));

    mac(VEC_WMACC, SEW16, ELEN'('h0000_8000), ELEN'('h0000_8000), ELEN'('h0000_0001));
    mac(VEC_WMACCU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFF), ELEN'('h0000_0001));
    mac(VEC_WMACCSU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_8000), ELEN'('h0000_0001));
    mac(VEC_WMACCUS, SEW16, ELEN'('h0000_8000), ELEN'('h0000_FFFF), ELEN'('h0000_0001));
  endtask  // Automatic

  // Accumulate directed cases
  task automatic test_acc_directed();
    mac(VEC_WMACC, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_0003), ELEN'('h0000_0005));
    mac(VEC_WMACCU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_0002), ELEN'('h0000_0001));
    mac(VEC_WMACCSU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FE), ELEN'('h0000_0003));
    mac(VEC_WMACCUS, SEW8, ELEN'('h0000_00FE), ELEN'('h0000_00FF), ELEN'('h0000_0004));

    mac(VEC_WMACC, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_0003), ELEN'('h0000_0005));
    mac(VEC_WMACCU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_0002), ELEN'('h0000_0001));
    mac(VEC_WMACCSU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFE), ELEN'('h0000_0003));
    mac(VEC_WMACCUS, SEW16, ELEN'('h0000_FFFE), ELEN'('h0000_FFFF), ELEN'('h0000_0004));
  endtask  // Automatic

  // Accumulate carries out
  task automatic test_acc_carry();
    mac(VEC_WMACCU, SEW8, ELEN'('h0000_00FF), ELEN'('h0000_00FF), ELEN'('h0000_0200));
    mac(VEC_WMACCU, SEW16, ELEN'('h0000_FFFF), ELEN'('h0000_FFFF), ELEN'('h0002_0000));
  endtask  // Automatic

  // Widening past ELEN
  task automatic test_widen_past_elen();
    mul(VEC_WMUL, SewTop, ELEN'('h1234_5678), ELEN'('h0000_0002));
    mac(VEC_WMACC, SewTop, ELEN'('h1234_5678), ELEN'('h0000_0002), ELEN'('hFFFF_FFFF));
  endtask  // Automatic

  // Randomized sweep
  task automatic test_sweep(input int n);
    for (int s = int'(SEW8); s <= int'(SewTop); s++)
      for (int k = 0; k < 4; k++) repeat (n) mul(ops[k], 3'(s), rand_elem(), rand_elem());
  endtask  // Automatic

  // Widening sweep
  task automatic test_widen_sweep(input int n);
    for (int s = int'(SEW8); s < int'(SewTop); s++)
      for (int k = 0; k < $size(ops); k++)
        if (widen_op(ops[k])) repeat (n) mul(ops[k], 3'(s), rand_elem(), rand_elem());
  endtask  // Automatic

  // Neighbours differ
  task automatic test_mixed(input int n);
    stalling = 1'b1;
    repeat (n)
      mul(ops[$urandom_range($size(ops)-1)], 3'($urandom_range(SewTop)), rand_elem(), rand_elem());
    stalling = 1'b0;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks || hold_checks < MinHold)
      $fatal(
          1,
          "TB UNDER-RAN: %0d checks, %0d hold checks, expected at least %0d and %0d",
          checks,
          hold_checks,
          MinChecks,
          MinHold
      );
    if (errors == 0)
      $display("PASS: %0d checks, %0d hold checks, %0d mismatches", checks, hold_checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("vec_mul_lane_tb.vcd");
    $dumpvars(0, vec_mul_lane_tb);
    do_reset();

    test_directed();
    test_sign_corners();
    test_widen_corners();
    test_widen_directed();
    test_acc_corners();
    test_acc_directed();
    test_acc_carry();
    test_widen_past_elen();
    test_sweep(SweepN);
    test_widen_sweep(SweepN);
    test_mixed(MixN);
    drain();

    do_verdict();
  end

  function automatic logic [ELEN-1:0] rand_elem();
    return ELEN'({$urandom, $urandom});
  endfunction

  function automatic logic widen_op(input vec_op_e o);
    return (o == VEC_WMUL) || (o == VEC_WMULU) || (o == VEC_WMULSU) || (o == VEC_WMACC) ||
        (o == VEC_WMACCU) || (o == VEC_WMACCSU) || (o == VEC_WMACCUS);
  endfunction

  function automatic logic signed [2*ELEN+1:0] extend(input logic [ELEN-1:0] x, input int w,
                                                      input logic sgn);
    logic signed [2*ELEN+1:0] out;
    out = '0;
    for (int i = 0; i < 2 * ELEN + 2; i++) out[i] = (i < w) ? x[i] : (sgn && x[w-1]);
    return out;
  endfunction

  function automatic logic [2*ELEN-1:0] product_ref(input vec_op_e op_in, input logic [2:0] vsew_in,
                                                    input logic [ELEN-1:0] a_in,
                                                    input logic [ELEN-1:0] b_in);
    int w;
    logic sa;
    logic sb;
    logic signed [2*ELEN+1:0] full;
    w = 8 << vsew_in;
    if (vsew_in > SewTop || (widen_op(op_in) && 2 * w > ELEN)) return '0;
    case (op_in)
      VEC_MUL, VEC_MULH, VEC_WMUL, VEC_WMACC: {sa, sb} = 2'b11;
      VEC_MULHSU, VEC_WMULSU, VEC_WMACCUS: {sa, sb} = 2'b10;
      VEC_WMACCSU: {sa, sb} = 2'b01;
      default: {sa, sb} = 2'b00;
    endcase
    full = extend(a_in, w, sa) * extend(b_in, w, sb);
    return full[2*ELEN-1:0] & ({2 * ELEN{1'b1}} >> (2 * ELEN - 2 * w));
  endfunction

  function automatic logic [ELEN-1:0] result_ref(input vec_op_e op_in, input logic [2:0] vsew_in,
                                                 input logic [2*ELEN-1:0] product_in,
                                                 input logic [ELEN-1:0] c_in);
    int w;
    logic [ELEN-1:0] mask;
    logic [ELEN-1:0] wide_mask;
    logic [ELEN-1:0] low;
    w = 8 << vsew_in;
    if (vsew_in > SewTop || (widen_op(op_in) && 2 * w > ELEN)) return '0;
    mask = {ELEN{1'b1}} >> (ELEN - w);
    wide_mask = (2 * w >= ELEN) ? '1 : ({ELEN{1'b1}} >> (ELEN - 2 * w));
    low = product_in[ELEN-1:0];
    case (op_in)
      VEC_MUL: return low & mask;
      VEC_MACC, VEC_MADD: return (low + c_in) & mask;
      VEC_NMSAC, VEC_NMSUB: return (c_in - low) & mask;
      VEC_WMUL, VEC_WMULU, VEC_WMULSU: return low & wide_mask;
      VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS: return (low + c_in) & wide_mask;
      default: return ELEN'(product_in >> w) & mask;
    endcase
  endfunction

endmodule

`default_nettype wire
