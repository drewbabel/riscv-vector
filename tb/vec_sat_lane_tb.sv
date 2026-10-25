`default_nettype none

module vec_sat_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Latency = 1;
  localparam int MinChecks = 10_000_000;
  localparam int MinHold = 50_000;
  localparam int MixN = 50_000;
  localparam int NumEdges = 12;
  localparam int LongW = $bits(longint);

  localparam logic [2:0] SEW8 = 3'd0;
  localparam logic [2:0] SEW16 = 3'd1;
  localparam logic [2:0] SEW32 = 3'd2;
  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));
  localparam logic [1:0] VxrmRnu = 2'd0;
  localparam logic [1:0] VxrmRne = 2'd1;
  localparam logic [1:0] VxrmRdn = 2'd2;
  localparam int NumModes = 4;

  int checks = 0;
  int hold_checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic stalling = 1'b0;

  logic clk = 1'b0;
  logic core_en;
  vec_op_e op;
  logic [2:0] vsew;
  logic [1:0] vxrm;
  logic [ELEN-1:0] a;
  logic [ELEN-1:0] b;
  logic [2*ELEN-1:0] product;
  logic [ELEN-1:0] result;
  logic sat;

  vec_op_e ops[13] = '{
      VEC_SADDU,
      VEC_SADD,
      VEC_SSUBU,
      VEC_SSUB,
      VEC_AADDU,
      VEC_AADD,
      VEC_ASUBU,
      VEC_ASUB,
      VEC_SSRL,
      VEC_SSRA,
      VEC_SMUL,
      VEC_NCLIPU,
      VEC_NCLIP
  };

  logic pend_valid[$];
  logic [$bits(vec_op_e)-1:0] pend_op[$];
  logic [ELEN-1:0] pend_res[$];
  logic pend_sat[$];

  always #5 clk = ~clk;

  vec_sat_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .op(op),
      .vsew(vsew),
      .vxrm(vxrm),
      .a(a),
      .b(b),
      .product(product),
      .result(result),
      .sat(sat)
  );

  task automatic check(input string name, input logic [ELEN-1:0] got, input logic [ELEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    core_en = 1'b1;
    op      = VEC_SADDU;
    vsew    = SEW8;
    vxrm    = VxrmRnu;
    a       = '0;
    b       = '0;
    product = '0;
  endtask  // Automatic

  task automatic retire();
    logic valid;
    vec_op_e o;
    logic [ELEN-1:0] exp_res;
    logic exp_sat;
    if (pend_valid.size() < Latency) return;
    valid = pend_valid.pop_front();
    o = vec_op_e'(pend_op.pop_front());
    exp_res = pend_res.pop_front();
    exp_sat = pend_sat.pop_front();
    if (!valid) return;
    check(o.name(), result, exp_res);
    check({o.name(), " sat"}, ELEN'(sat), ELEN'(exp_sat));
  endtask  // Automatic

  // Clock enable drops
  task automatic stall();
    logic [ELEN-1:0] held_res;
    logic held_sat;
    while (stalling && 1'($urandom)) begin
      held_res = result;
      held_sat = sat;
      core_en = 1'b0;
      op = ops[$urandom_range($size(ops)-1)];
      vsew = 3'($urandom);
      vxrm = 2'($urandom);
      a = rand_elem();
      b = rand_elem();
      product = {rand_elem(), rand_elem()};
      @(negedge clk);
      hold_checks++;
      check("held result", result, held_res);
      check("held sat", ELEN'(sat), ELEN'(held_sat));
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic issue(input logic valid, input vec_op_e o, input logic [2:0] sew,
                       input logic [1:0] mode, input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    logic [ELEN-1:0] exp_res;
    logic exp_sat;
    @(negedge clk);
    retire();
    stall();
    ref_lane(o, 8 << sew, x, y, mode, exp_res, exp_sat);
    op = o;
    vsew = sew;
    vxrm = mode;
    a = x;
    b = y;
    product = full_product(x, y, 8 << sew);
    pend_valid.push_back(valid);
    pend_op.push_back(o);
    pend_res.push_back(exp_res);
    pend_sat.push_back(exp_sat);
  endtask  // Automatic

  // One op
  task automatic run_op(input vec_op_e o, input logic [2:0] sew, input logic [1:0] mode,
                        input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    issue(1'b1, o, sew, mode, x, y);
  endtask  // Automatic

  task automatic drain();
    repeat (Latency) issue(1'b0, VEC_SADDU, SEW8, VxrmRnu, '0, '0);
  endtask  // Automatic

  // Every byte pair
  task automatic sweep8();
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < NumModes; m++)
        for (int i = 0; i < 256; i++)
          for (int j = 0; j < 256; j++)
            run_op(ops[k], SEW8, 2'(m), (rand_elem() << 8) | ELEN'(i),
                   (rand_elem() << 8) | ELEN'(j));
  endtask  // Automatic

  // Narrowing sources
  task automatic sweep_clip8();
    for (int k = 0; k < $size(ops); k++)
      if (ops[k] == VEC_NCLIPU || ops[k] == VEC_NCLIP)
        for (int m = 0; m < NumModes; m++)
          for (int sh = 0; sh < 32; sh++)
            for (int i = 0; i < 4096; i++)
              run_op(ops[k], SEW8, 2'(m), (rand_elem() << 16) | ELEN'(i << 4) | ELEN'(4'($urandom)),
                     (rand_elem() << 5) | ELEN'(sh));
  endtask  // Automatic

  task automatic edges(input logic [2:0] sew);
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < NumModes; m++)
        for (int i = 0; i < NumEdges; i++)
          for (int j = 0; j < NumEdges; j++)
            run_op(ops[k], sew, 2'(m), edge_val(i, 8 << sew), edge_val(j, 8 << sew));
  endtask  // Automatic

  task automatic random_cases(input logic [2:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < NumModes; m++)
        for (int i = 0; i < n; i++) run_op(ops[k], sew, 2'(m), rand_elem(), rand_elem());
  endtask  // Automatic

  // Neighbours differ
  task automatic random_mix(input int n);
    stalling = 1'b1;
    repeat (n)
      run_op(ops[$urandom_range($size(ops)-1)], 3'($urandom_range(SewTop)), 2'($urandom),
             rand_elem(), rand_elem());
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
    do_reset();

    sweep8();
    sweep_clip8();

    // Halfword and word edges
    edges(SEW16);
    edges(SEW32);

    // Random operands
    random_cases(SEW16, 5000);
    random_cases(SEW32, 5000);

    random_mix(MixN);
    drain();

    do_verdict();
  end

  function automatic logic [ELEN-1:0] rand_elem();
    return ELEN'({$urandom, $urandom});
  endfunction

  // Width helpers
  function automatic longint umask(input int w);
    umask = (64'sd1 <<< w) - 64'sd1;
  endfunction

  function automatic longint uval(input logic [ELEN-1:0] x, input int w);
    uval = longint'({{(LongW - ELEN) {1'b0}}, x}) & umask(w);
  endfunction

  function automatic longint sval(input logic [ELEN-1:0] x, input int w);
    longint u;
    u = uval(x, w);
    sval = u[w-1] ? (u - (64'sd1 <<< w)) : u;
  endfunction

  // Floor then round
  function automatic longint roundoff(input longint v, input int d, input logic [1:0] mode);
    longint q;
    longint rem;
    longint half;
    q = v >>> d;
    rem = v - (q <<< d);
    half = (d > 0) ? (64'sd1 <<< (d - 1)) : 64'sd0;
    case (mode)
      VxrmRnu: roundoff = q + ((d > 0 && rem >= half) ? 1 : 0);
      VxrmRne: roundoff = q + ((d > 0 && (rem > half || (rem == half && q[0]))) ? 1 : 0);
      VxrmRdn: roundoff = q;
      default: roundoff = (rem != 0) ? (q | 64'sd1) : q;
    endcase
  endfunction

  // Reference model
  task automatic ref_lane(input vec_op_e o, input int w, input logic [ELEN-1:0] x,
                          input logic [ELEN-1:0] y, input logic [1:0] mode,
                          output logic [ELEN-1:0] res, output logic s);
    longint ux;
    longint uy;
    longint sx;
    longint sy;
    longint smax;
    longint smin;
    longint t;
    ux = uval(x, w);
    uy = uval(y, w);
    sx = sval(x, w);
    sy = sval(y, w);
    smax = (64'sd1 <<< (w - 1)) - 1;
    smin = -(64'sd1 <<< (w - 1));
    s = 1'b0;
    case (o)
      VEC_SADDU: begin
        t = ux + uy;
        if (t > umask(w)) begin
          t = umask(w);
          s = 1'b1;
        end
      end
      VEC_SSUBU: begin
        t = ux - uy;
        if (t < 0) begin
          t = 0;
          s = 1'b1;
        end
      end
      VEC_SADD, VEC_SSUB: begin
        t = (o == VEC_SADD) ? sx + sy : sx - sy;
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
      VEC_AADDU: t = roundoff(ux + uy, 1, mode);
      VEC_AADD:  t = roundoff(sx + sy, 1, mode);
      VEC_ASUBU: t = roundoff(ux - uy, 1, mode);
      VEC_ASUB:  t = roundoff(sx - sy, 1, mode);
      VEC_SSRL:  t = roundoff(ux, int'(uy) & (w - 1), mode);
      VEC_SSRA:  t = roundoff(sx, int'(uy) & (w - 1), mode);
      VEC_SMUL: begin
        t = roundoff(sx * sy, w - 1, mode);
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
      VEC_NCLIPU: begin
        t = roundoff(uval(x, 2 * w), int'(y) & (2 * w - 1), mode);
        if (t > umask(w)) begin
          t = umask(w);
          s = 1'b1;
        end
      end
      default: begin
        t = roundoff(sval(x, 2 * w), int'(y) & (2 * w - 1), mode);
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
    endcase
    if ((o == VEC_NCLIPU || o == VEC_NCLIP) && w == ELEN) begin
      t = 0;
      s = 1'b0;
    end
    res = ELEN'(t & umask(w));
  endtask  // Automatic

  // Product with junk
  function automatic logic [2*ELEN-1:0] full_product(input logic [ELEN-1:0] x,
                                                     input logic [ELEN-1:0] y, input int w);
    logic [2*ELEN-1:0] keep;
    logic [2*ELEN-1:0] prod;
    keep = (w == ELEN) ? '1 : (2 * ELEN)'(umask(2 * w));
    prod = (2 * ELEN)'(sval(x, w) * sval(y, w));
    full_product = (prod & keep) | ({rand_elem(), rand_elem()} & ~keep);
  endfunction

  // Edge values
  function automatic logic [ELEN-1:0] edge_val(input int idx, input int w);
    longint m;
    m = umask(w);
    case (idx)
      0: edge_val = ELEN'(0);
      1: edge_val = ELEN'(1);
      2: edge_val = ELEN'(2);
      3: edge_val = ELEN'(m);
      4: edge_val = ELEN'(m - 1);
      5: edge_val = ELEN'(m >> 1);
      6: edge_val = ELEN'((m >> 1) + 1);
      7: edge_val = ELEN'((m >> 1) - 1);
      8: edge_val = ELEN'((m >> 1) + 2);
      9: edge_val = ELEN'(w - 1);
      10: edge_val = ELEN'(3);
      default: edge_val = ELEN'(m >> 2);
    endcase
  endfunction

endmodule

`default_nettype wire
